import Foundation
import MusicsCore
import Observation

/// User preferences, persisted to UserDefaults on every change.
@MainActor
@Observable
final class AppSettings {
    private let d = UserDefaults.standard

    var wifiQuality: StreamQuality { didSet { d.set(wifiQuality.rawValue, forKey: "wifiQuality") } }
    var cellularQuality: StreamQuality { didSet { d.set(cellularQuality.rawValue, forKey: "cellularQuality") } }
    var downloadQuality: StreamQuality { didSet { d.set(downloadQuality.rawValue, forKey: "downloadQuality") } }
    /// Keep the queue going with radio suggestions when it runs out.
    var autoplay: Bool { didSet { d.set(autoplay, forKey: "autoplay") } }
    /// Prefetch upcoming songs to disk and keep recently played ones.
    var smartCache: Bool { didSet { d.set(smartCache, forKey: "smartCache") } }
    var cacheLimitMB: Int { didSet { d.set(cacheLimitMB, forKey: "cacheLimitMB") } }
    var prefetchCount: Int { didSet { d.set(prefetchCount, forKey: "prefetchCount") } }
    var downloadOverCellular: Bool { didSet { d.set(downloadOverCellular, forKey: "downloadOverCellular") } }
    var autoDownloadLiked: Bool { didSet { d.set(autoDownloadLiked, forKey: "autoDownloadLiked") } }
    /// Share what's playing with the server (music.lan forwards it to Discord).
    var reportNowPlaying: Bool { didSet { d.set(reportNowPlaying, forKey: "reportNowPlaying") } }
    var scrobble: Bool { didSet { d.set(scrobble, forKey: "scrobble") } }
    var showAudioSearch: Bool { didSet { d.set(showAudioSearch, forKey: "showAudioSearch") } }
    var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }

    /// Stable per-install id the server uses to tell clients apart.
    let clientID: String

    init() {
        d.register(defaults: [
            "wifiQuality": StreamQuality.original.rawValue,
            "cellularQuality": StreamQuality.original.rawValue,
            "downloadQuality": StreamQuality.original.rawValue,
            "autoplay": true, "smartCache": true, "cacheLimitMB": 2048, "prefetchCount": 2,
            "downloadOverCellular": false, "autoDownloadLiked": false, "reportNowPlaying": true,
            "scrobble": true, "showAudioSearch": true, "haptics": true,
        ])
        wifiQuality = StreamQuality(rawValue: d.string(forKey: "wifiQuality") ?? "") ?? .original
        cellularQuality = StreamQuality(rawValue: d.string(forKey: "cellularQuality") ?? "") ?? .original
        downloadQuality = StreamQuality(rawValue: d.string(forKey: "downloadQuality") ?? "") ?? .original
        autoplay = d.bool(forKey: "autoplay")
        smartCache = d.bool(forKey: "smartCache")
        cacheLimitMB = d.integer(forKey: "cacheLimitMB")
        prefetchCount = d.integer(forKey: "prefetchCount")
        downloadOverCellular = d.bool(forKey: "downloadOverCellular")
        autoDownloadLiked = d.bool(forKey: "autoDownloadLiked")
        reportNowPlaying = d.bool(forKey: "reportNowPlaying")
        scrobble = d.bool(forKey: "scrobble")
        showAudioSearch = d.bool(forKey: "showAudioSearch")
        haptics = d.bool(forKey: "haptics")
        if let id = d.string(forKey: "clientID") {
            clientID = id
        } else {
            let id = "ios-" + UUID().uuidString.prefix(8).lowercased()
            d.set(id, forKey: "clientID")
            clientID = id
        }
    }
}

extension StreamQuality {
    var label: String {
        switch self {
        case .original: return "Original"
        case .efficient: return "Data saver"
        }
    }

    var detail: String {
        switch self {
        case .original: return "The file as stored. Formats iOS can't play are converted to AAC."
        case .efficient: return "AAC or MP3 around 160 kbit/s."
        }
    }
}
