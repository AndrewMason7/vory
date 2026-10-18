"""Unit tests for the companion (hermes_push.py).

No Hermes is imported or run: a fake gateway answers the companion's calls over a local
WebSocket. Run from the repo root:

    PYTHONPATH=<a folder with websockets> python3 -m unittest discover -s server/hermes-push/tests

PyJWT (used only to sign APNs requests) is replaced by an empty module when it is not installed.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
os.environ.setdefault("HERMES_PUSH_GATEWAY_URL", "http://127.0.0.1:9")
if "jwt" not in sys.modules:
    try:
        import jwt  # noqa: F401
    except ImportError:
        sys.modules["jwt"] = types.ModuleType("jwt")
sys.path.insert(0, str(ROOT))
import hermes_push  # noqa: E402
import websockets  # noqa: E402


class FakeGateway:
    """Answers every call with an empty result, client.capabilities as told: "ok", "unknown"
    (JSON-RPC -32601), "unknown-text" (an error whose message says so, with no code) or "fail"."""

    def __init__(self, capabilities: str) -> None:
        self.capabilities = capabilities
        self.calls: list[str] = []

    async def handler(self, ws) -> None:
        async for raw in ws:
            msg = json.loads(raw)
            self.calls.append(msg["method"])
            if msg["method"] == "client.capabilities" and self.capabilities != "ok":
                err = {"unknown": {"code": -32601, "message": "Method not found"},
                       "unknown-text": {"message": "unknown method: client.capabilities"},
                       "fail": {"code": -32000, "message": "boom"}}[self.capabilities]
                await ws.send(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "error": err}))
            else:
                await ws.send(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {}}))


class CapabilitiesTests(unittest.IsolatedAsyncioTestCase):
    """#400: an older Hermes answers client.capabilities with "unknown method". The relay goes on
    without it, says once what is missing, and tells the app; any other failure still fails."""

    async def connect(self, capabilities: str):
        fake = FakeGateway(capabilities)
        server = await websockets.serve(fake.handler, "127.0.0.1", 0)
        port = server.sockets[0].getsockname()[1]
        gw = hermes_push.Gateway()
        gw._ws_for = lambda url: (f"ws://127.0.0.1:{port}/api/ws", "test")
        self.addAsyncCleanup(self.close, server, gw)
        return gw, fake

    async def close(self, server, gw) -> None:
        if gw.ws is not None:
            await gw.ws.close()
        server.close()
        await server.wait_closed()

    async def test_a_gateway_that_takes_it(self) -> None:
        gw, fake = await self.connect("ok")
        await gw.connect()
        self.assertTrue(gw.server_requests)
        self.assertEqual(fake.calls, ["client.capabilities"])
        # The connection goes on working.
        self.assertEqual(await gw.call("session.list"), {})

    async def test_an_older_gateway_is_not_fatal_and_says_so_once(self) -> None:
        for answer in ("unknown", "unknown-text"):
            with self.subTest(answer=answer):
                gw, _ = await self.connect(answer)
                with self.assertLogs("hermes-push", level="WARNING") as logs:
                    await gw.connect()
                self.assertIs(gw.server_requests, False)
                self.assertEqual(len(logs.records), 1)
                self.assertIn("Update Hermes", logs.output[0])
                self.assertEqual(await gw.call("session.list"), {})

    async def test_the_hint_is_not_repeated_on_a_reconnect(self) -> None:
        gw, _ = await self.connect("unknown")
        with self.assertLogs("hermes-push", level="WARNING"):
            await gw.connect()
        await gw.ws.close()
        logger = logging.getLogger("hermes-push")
        seen: list[logging.LogRecord] = []
        handler = logging.Handler()
        handler.emit = seen.append
        logger.addHandler(handler)
        try:
            await gw.connect()
        finally:
            logger.removeHandler(handler)
        self.assertEqual([r for r in seen if r.levelno >= logging.WARNING], [])

    async def test_any_other_failure_still_fails(self) -> None:
        gw, _ = await self.connect("fail")
        with self.assertRaises(hermes_push.RPCError) as caught:
            await gw.connect()
        self.assertEqual(caught.exception.code, -32000)

    def test_the_status_tells_the_app(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            status = Path(d) / "status.json"
            old = hermes_push.status_path
            hermes_push.status_path = lambda: status
            try:
                relay = hermes_push.Relay.__new__(hermes_push.Relay)
                relay.gw = types.SimpleNamespace(server_requests=False)
                relay.last_test, relay.last_la = {}, {}
                relay._status(connected=True)
            finally:
                hermes_push.status_path = old
            written = json.loads(status.read_text())
        self.assertIs(written["server_requests"], False)
        self.assertEqual(written["version"], hermes_push.VERSION)


if __name__ == "__main__":
    unittest.main()
