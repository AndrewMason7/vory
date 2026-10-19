"""Hermes plugin wrapper around hermes_push.py: the same relay loop, run inside Hermes as a
daemon thread so nothing needs systemd or launchd. Config comes from
<HERMES_HOME>/push/hermes-push.conf (written by the Vory app)."""
from __future__ import annotations

import logging
import sys
import threading
from pathlib import Path

log = logging.getLogger("vory-push")
_stop = threading.Event()


def _run() -> None:
    here = Path(__file__).resolve().parent
    if str(here) not in sys.path:
        sys.path.insert(0, str(here))
    try:
        import asyncio
        import importlib
        import hermes_push
        hermes_push._load_conf()
        if not _claim_single_instance(hermes_push):
            return
        while not _stop.is_set():
            try:
                asyncio.run(hermes_push.Relay().run())
                return
            except hermes_push.CodeChanged:
                # The app put a newer hermes_push.py next to us: pick it up in place, no gateway restart.
                log.info("vory-push: reloading updated hermes_push.py")
                hermes_push = importlib.reload(hermes_push)
                hermes_push._CONF.clear()
                hermes_push._load_conf()
    except SystemExit as exc:
        log.warning("vory-push not started: %s", exc)
    except Exception:  # noqa: BLE001
        log.exception("vory-push relay stopped")


_lock_handle = None


def _try_lock(handle) -> bool:
    """One try at the relay's lock: True when this process now holds it. flock where there is
    one; on Windows, which has no fcntl, the lock on the file's first byte (#403: without it both
    the dashboard and the gateway ran a relay there, and every push arrived twice). With neither,
    the relay runs regardless."""
    try:
        import fcntl
    except ImportError:
        fcntl = None
    try:
        if fcntl is not None:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        else:
            try:
                import msvcrt
            except ImportError:
                return True
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        return True
    except OSError:
        return False


def _claim_single_instance(hermes_push) -> bool:
    """Hermes loads plugins in more than one process (dashboard, gateway). Only one relay may run,
    or every push arrives twice. Others wait for the lock rather than giving up: during a gateway
    restart the old process can still hold it for a few seconds after the new one has started."""
    global _lock_handle
    import time
    path = hermes_push.status_path().with_name("relay.lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    _lock_handle = open(path, "w")
    waited = False
    while not _stop.is_set():
        if _try_lock(_lock_handle):
            if waited:
                log.info("vory-push relay lock acquired; starting")
            return True
        if not waited:
            log.info("vory-push relay running in another Hermes process; waiting for it to stop")
            waited = True
        time.sleep(5)
    return False


def register(ctx) -> None:
    t = threading.Thread(target=_run, name="vory-push", daemon=True)
    t.start()
    try:
        ctx.on_unload(lambda: _stop.set())
    except Exception:  # noqa: BLE001
        pass
    log.info("vory-push plugin started")
