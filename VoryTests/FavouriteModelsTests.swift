import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// Favourite models (#401): the store, and how the iCloud merge carries them between devices. Each favourite is
/// its own cloud entry (a removal is kept as a "gone" marker) and each gateway's order is one more, the last one set.
@MainActor
struct FavouriteModelsTests {
    final class Clock { var t: Double = 1_000 }

    private let gw = UUID(uuidString: "6F1C2B9A-0000-4000-8000-00000000A001")!
    private let other = UUID(uuidString: "6F1C2B9A-0000-4000-8000-00000000B002")!
    private let x = FavouriteModel(provider: "openrouter", model: "acme/model-0001")
    private let y = FavouriteModel(provider: "anthropic", model: "claude-sonnet-4-6")
    private let z = FavouriteModel(provider: "together", model: "borealis/model-0712")
    private let w = FavouriteModel(provider: "openrouter", model: "cobalt/model-0042")

    private func suite(_ id: String) -> UserDefaults {
        let name = "favourites-test-\(id)-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func device(_ cloud: MemoryCloudStore, _ clock: Clock, id: String) -> (CloudMerge, FavouriteModels) {
        let defaults = suite(id)
        var merge = CloudMerge(cloud: cloud, defaults: defaults)
        merge.deviceID = id
        merge.deviceName = id
        merge.now = { clock.t += 1; return clock.t }
        return (merge, FavouriteModels(defaults: defaults))
    }

    /// The device's list as the sync left it in its defaults.
    private func stored(_ f: FavouriteModels) -> [FavouriteModel] { f.reload(); return f.list(gw) }

    // MARK: The store

    @Test func addsGoAtTheEndAndEachGatewayKeepsItsOwn() {
        let f = FavouriteModels(defaults: suite("store"))
        f.add(x, gw); f.add(y, gw); f.add(x, gw)
        f.add(z, other)
        #expect(f.list(gw) == [x, y])
        #expect(f.list(other) == [z])
        f.toggle(x, gw)
        #expect(f.list(gw) == [y])
        f.toggle(x, gw)
        #expect(f.list(gw) == [y, x])
        f.move(gw, from: IndexSet(integer: 1), to: 0)
        #expect(f.list(gw) == [x, y])
    }

    @Test func theListOutlivesTheAppAndAnEmptyOneIsNotKept() {
        let d = suite("persist")
        let f = FavouriteModels(defaults: d)
        f.add(x, gw); f.add(y, gw); f.add(z, other)
        #expect(FavouriteModels(defaults: d).list(gw) == [x, y])
        f.remove(z, other)
        #expect(FavouriteModels(defaults: d).list(other).isEmpty)
        f.remove(x, gw); f.remove(y, gw)
        #expect(d.object(forKey: FavouriteModels.storageKey) == nil)
        #expect(FavouriteModels.decode("not json").isEmpty)
    }

    @Test func aFavouriteTheGatewayNoLongerOffersIsUnavailable() {
        let options = ModelOptionsResult(providers: [
            ModelProvider(slug: "openrouter", name: "OpenRouter", models: ["acme/model-0001"], featuredModels: ["acme/model-0001"]),
            ModelProvider(slug: "anthropic", name: "Anthropic", featuredModels: ["claude-sonnet-4-6"]),
        ])
        #expect(options.offers(x))
        #expect(options.offers(y))
        // Its provider still there, the model gone; the provider gone altogether.
        #expect(!options.offers(w))
        #expect(!options.offers(z))
        #expect(options.providerName("anthropic") == "Anthropic")
        #expect(options.providerName("together") == "together")
    }

    @Test func cloudKeysFitTheStore() {
        let long = FavouriteModel(provider: String(repeating: "p", count: 80), model: String(repeating: "m", count: 300))
        #expect(CloudMerge.favouriteKey(gw.uuidString, long.id).utf8.count <= 64)
        #expect(CloudMerge.favouriteOrderKey(gw.uuidString).utf8.count <= 64)
        #expect(CloudMerge.favouriteKey(gw.uuidString, x.id) != CloudMerge.favouriteKey(other.uuidString, x.id))
        #expect(!CloudMerge.favouriteOrderKey(gw.uuidString).hasPrefix(CloudMerge.favouritePrefix))
    }

    // MARK: Between devices

    @Test func aFavouriteAndItsPlaceReachTheOtherDevice() {
        let cloud = MemoryCloudStore(), clock = Clock()
        let (phone, phoneFavs) = device(cloud, clock, id: "phone")
        let (mac, macFavs) = device(cloud, clock, id: "mac")
        phone.reconcile(.merge); mac.reconcile(.merge)

        phoneFavs.add(x, gw); phoneFavs.add(y, gw); phoneFavs.add(z, gw)
        phone.reconcile(.merge)
        mac.reconcile(.merge)
        #expect(stored(macFavs) == [x, y, z])

        // Reordered on the Mac: the phone takes the order.
        macFavs.move(gw, from: IndexSet(integer: 2), to: 0)
        mac.reconcile(.merge)
        phone.reconcile(.merge)
        #expect(stored(phoneFavs) == [z, x, y])

        // Settled: nothing moves either way.
        #expect(mac.reconcile(.merge) == CloudMerge.Outcome())
        #expect(phone.reconcile(.merge) == CloudMerge.Outcome())
    }

    /// An add on one device and a removal on the other, between two syncs: the removed favourite stays removed and the
    /// added one arrives, whichever device syncs first.
    @Test(arguments: [true, false])
    func aRemovalIsNotUndoneByAnAddElsewhere(phoneFirst: Bool) {
        let cloud = MemoryCloudStore(), clock = Clock()
        let (phone, phoneFavs) = device(cloud, clock, id: "phone")
        let (mac, macFavs) = device(cloud, clock, id: "mac")
        phone.reconcile(.merge); mac.reconcile(.merge)
        phoneFavs.add(x, gw); phoneFavs.add(y, gw)
        phone.reconcile(.merge); mac.reconcile(.merge)
        #expect(stored(macFavs) == [x, y])

        phoneFavs.remove(x, gw)
        macFavs.add(z, gw)
        let order = phoneFirst ? [phone, mac, phone, mac] : [mac, phone, mac, phone]
        for d in order { d.reconcile(.merge) }

        #expect(stored(phoneFavs) == [y, z])
        #expect(stored(macFavs) == [y, z])
        // And it stays that way.
        for d in order { d.reconcile(.merge) }
        #expect(stored(phoneFavs) == [y, z])
        #expect(stored(macFavs) == [y, z])
    }

    /// A removal on one device while the other reorders a list that still has it: the reorder's order names the
    /// removed favourite, and it is not brought back by it.
    @Test func aReorderThatStillNamesARemovedFavouriteDoesNotBringItBack() {
        let cloud = MemoryCloudStore(), clock = Clock()
        let (phone, phoneFavs) = device(cloud, clock, id: "phone")
        let (mac, macFavs) = device(cloud, clock, id: "mac")
        phone.reconcile(.merge); mac.reconcile(.merge)
        for f in [x, y, z] { phoneFavs.add(f, gw) }
        phone.reconcile(.merge); mac.reconcile(.merge)

        phoneFavs.remove(y, gw)
        phone.reconcile(.merge)
        macFavs.move(gw, from: IndexSet(integer: 2), to: 0)   // z, x, y: still names y
        mac.reconcile(.merge)
        phone.reconcile(.merge)
        mac.reconcile(.merge)

        #expect(stored(phoneFavs) == [z, x])
        #expect(stored(macFavs) == [z, x])
    }

    /// Both devices reorder between two syncs: the order set last wins on both, and nothing is lost or doubled.
    @Test func twoReordersAtOnceTheLastOneWins() {
        let cloud = MemoryCloudStore(), clock = Clock()
        let (phone, phoneFavs) = device(cloud, clock, id: "phone")
        let (mac, macFavs) = device(cloud, clock, id: "mac")
        phone.reconcile(.merge); mac.reconcile(.merge)
        for f in [x, y, z] { phoneFavs.add(f, gw) }
        phone.reconcile(.merge); mac.reconcile(.merge)

        phoneFavs.move(gw, from: IndexSet(integer: 0), to: 3)   // y, z, x
        macFavs.move(gw, from: IndexSet(integer: 2), to: 0)     // z, x, y
        phone.reconcile(.merge)   // the phone's order goes up first
        mac.reconcile(.merge)     // the Mac changed its own since: its order is the later act, and goes up
        phone.reconcile(.merge)

        #expect(stored(macFavs) == [z, x, y])
        #expect(stored(phoneFavs) == [z, x, y])
        #expect(mac.reconcile(.merge) == CloudMerge.Outcome())
        #expect(phone.reconcile(.merge) == CloudMerge.Outcome())
    }

    /// A removal stays in the cloud as a marker, so a device that has not seen it yet cannot put the favourite back.
    @Test func aRemovalIsKeptAsAMarker() {
        let cloud = MemoryCloudStore(), clock = Clock()
        let (phone, phoneFavs) = device(cloud, clock, id: "phone")
        phone.reconcile(.merge)
        phoneFavs.add(x, gw)
        phone.reconcile(.merge)
        let key = CloudMerge.favouriteKey(gw.uuidString, x.id)
        #expect((cloud.cloudValue(key) as? [String: Any])?["m"] as? String == x.model)
        phoneFavs.remove(x, gw)
        phone.reconcile(.merge)
        #expect((cloud.cloudValue(key) as? [String: Any])?["gone"] as? Bool == true)
        #expect((cloud.cloudValue(CloudMerge.favouriteOrderKey(gw.uuidString)) as? [String: Any])?["o"] as? [String] == [])
    }
}
