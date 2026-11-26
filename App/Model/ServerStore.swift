import Foundation
import MusicsCore
import Observation

/// The servers the user added and which one is active.
@MainActor
@Observable
final class ServerStore {
    private(set) var profiles: [ServerProfile]
    var activeID: UUID? {
        didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: "activeServer") }
    }

    init() {
        profiles = UserDefaults.standard.decoded([ServerProfile].self, forKey: "servers") ?? []
        activeID = UserDefaults.standard.string(forKey: "activeServer").flatMap(UUID.init(uuidString:))
        if activeID == nil || !profiles.contains(where: { $0.id == activeID }) { activeID = profiles.first?.id }
    }

    var active: ServerProfile? { profiles.first { $0.id == activeID } }

    func credentials(for profile: ServerProfile) -> ServerCredentials? {
        Keychain.get(profile.id).map(ServerCredentials.init(secret:))
    }

    func upsert(_ profile: ServerProfile, secret: String?) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
        }
        if let secret { Keychain.set(secret, for: profile.id) }
        if profile.auth == .none { Keychain.set(nil, for: profile.id) }
        persist()
        if activeID == nil { activeID = profile.id }
    }

    func remove(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        Keychain.set(nil, for: id)
        try? FileManager.default.removeItem(at: Paths.server(id))
        try? FileManager.default.removeItem(at: Paths.streamCache(id))
        persist()
        if activeID == id { activeID = profiles.first?.id }
    }

    private func persist() {
        UserDefaults.standard.setEncoded(profiles, forKey: "servers")
    }
}
