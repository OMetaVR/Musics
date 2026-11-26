import Foundation
import MusicsCore
import Observation

/// Listening history for the active server, saved a few seconds after each change.
@MainActor
@Observable
final class StatsStore {
    private(set) var stats = ListeningStats()
    @ObservationIgnored private var serverID: UUID?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private func url(_ id: UUID) -> URL { Paths.server(id).appendingPathComponent("stats.json") }

    func load(serverID id: UUID) {
        serverID = id
        stats = Store.load(ListeningStats.self, from: url(id)) ?? ListeningStats()
    }

    func update(_ change: (inout ListeningStats) -> Void) {
        change(&stats)
        scheduleSave()
    }

    private func scheduleSave() {
        guard let id = serverID else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.stats
            let url = self.url(id)
            await Task.detached(priority: .utility) { Store.save(snapshot, to: url) }.value
        }
    }

    func flush() {
        guard let id = serverID else { return }
        saveTask?.cancel()
        Store.save(stats, to: url(id))
    }
}
