import Foundation
import SwiftUI
import Testing
import VoryCore
@testable import Vory

/// The chat list beside the open chat: selecting replaces, the phone pushes, a fresh chat is
/// never equal to the last fresh one, and routes survive being saved (1.5 iPad and Duo).
@Suite struct ChatNavigationTests {
    @Test func selectingReplacesTheDetailAndPushingAppends() {
        var path = NavigationPath()
        ChatNavigation.push(ChatRoute(storedID: "a"), onto: &path)
        ChatNavigation.push(ChatRoute(storedID: "b"), onto: &path)
        #expect(path.count == 2)
        ChatNavigation.select(ChatRoute(storedID: "c"), in: &path)
        #expect(path.count == 1)
        ChatNavigation.select(RoomRoute(room: Room(roomId: "r1", name: "Ops", members: [], updatedAt: 0), initialText: nil), in: &path)
        #expect(path.count == 1)
    }

    @Test func aFreshChatGetsItsOwnTokenAndAStoredOneDoesNot() {
        let fresh = ChatRoute(storedID: nil, profile: "work")
        let one = ChatNavigation.tokened(fresh), two = ChatNavigation.tokened(fresh)
        #expect(one.token != nil && two.token != nil && one != two)
        let stored = ChatRoute(storedID: "s1")
        #expect(ChatNavigation.tokened(stored) == stored)
    }

    @Test func theSelectionIDNamesTheRowToHighlight() {
        #expect(ChatNavigation.selectionID(of: ChatRoute(storedID: "s1")) == "s1")
        #expect(ChatNavigation.selectionID(of: ChatRoute(storedID: nil)) == nil)
        let room = RoomRoute(room: Room(roomId: "r1", name: "Ops", members: [], updatedAt: 0), initialText: nil)
        #expect(ChatNavigation.selectionID(of: room) == ChatNavigation.selectionID(ofRoom: "r1"))
        #expect(ChatNavigation.selectionID(of: 42) == nil)
    }

    @Test func routesAreSavedWithoutThePickedFiles() throws {
        var route = ChatRoute(storedID: "s1", title: "Disk", profile: "work", initialText: "hi", readOnly: true, cwd: "/srv", token: UUID(), startVoice: true)
        route.initialAttachments = [AttachmentPreview(id: "f", name: "a.pdf", serverPath: nil, kind: .pdf, localURL: nil, byteCount: 3)]
        let back = try JSONDecoder().decode(ChatRoute.self, from: JSONEncoder().encode(route))
        #expect(back.initialAttachments.isEmpty)
        #expect(back.storedID == "s1" && back.title == "Disk" && back.profile == "work" && back.initialText == "hi")
        #expect(back.readOnly && back.cwd == "/srv" && back.token == route.token && back.startVoice)
        let room = RoomRoute(room: Room(roomId: "r1", name: "Ops", members: [], updatedAt: 0), initialText: "go")
        let roomBack = try JSONDecoder().decode(RoomRoute.self, from: JSONEncoder().encode(room))
        #expect(roomBack == room)
    }
}
