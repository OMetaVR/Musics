import SwiftUI
import MusicsCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClearCache = false
    @State private var editing: ServerProfile?

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                serversSection

                Section {
                    Picker("Wi-Fi Streaming", selection: $settings.wifiQuality) {
                        ForEach(StreamQuality.allCases, id: \.self) { Text($0.label) }
                    }
                    Picker("Cellular Streaming", selection: $settings.cellularQuality) {
                        ForEach(StreamQuality.allCases, id: \.self) { Text($0.label) }
                    }
                    Toggle("Autoplay Similar Songs", isOn: $settings.autoplay)
                } header: { Text("Playback") } footer: {
                    Text("Original plays the file as stored (formats iOS can't play, like Opus, are converted to AAC by the server). Data saver asks for about 160 kbit/s. Autoplay keeps music going with radio suggestions when the queue ends.")
                }

                Section {
                    Toggle("Smart Cache", isOn: $settings.smartCache)
                    if settings.smartCache {
                        Picker("Cache Size", selection: $settings.cacheLimitMB) {
                            Text("500 MB").tag(500)
                            Text("1 GB").tag(1024)
                            Text("2 GB").tag(2048)
                            Text("5 GB").tag(5120)
                            Text("10 GB").tag(10240)
                        }
                        Stepper("Prefetch \(settings.prefetchCount) upcoming", value: $settings.prefetchCount, in: 0...6)
                    }
                    LabeledContent("Cache in Use", value: Format.bytes(model.downloads.cachedBytes))
                    Button("Clear Cache") { confirmClearCache = true }
                } header: { Text("Smart Cache") } footer: {
                    Text("Upcoming songs are saved ahead of time, so track changes are instant and music keeps playing through dead zones. Recently played songs stay until the cache is full.")
                }

                Section {
                    Picker("Download Quality", selection: $settings.downloadQuality) {
                        ForEach(StreamQuality.allCases, id: \.self) { Text($0.label) }
                    }
                    Toggle("Download over Cellular", isOn: $settings.downloadOverCellular)
                    Toggle("Download Liked Songs", isOn: $settings.autoDownloadLiked)
                    LabeledContent("Downloaded", value: "\(Format.songs(model.downloads.downloaded.count)), \(Format.bytes(model.downloads.downloadedBytes))")
                    if settings.autoDownloadLiked {
                        Button("Download All Liked Songs Now") { model.download(model.library.likedTracks) }
                    }
                } header: { Text("Downloads") }

                Section {
                    if model.capabilities.contains(.nowPlaying) {
                        Toggle("Share Now Playing", isOn: $settings.reportNowPlaying)
                    }
                    if model.capabilities.contains(.scrobble) {
                        Toggle("Scrobble Plays", isOn: $settings.scrobble)
                    }
                    if model.capabilities.contains(.semanticSearch) {
                        Toggle("Search by Sound", isOn: $settings.showAudioSearch)
                    }
                    Toggle("Haptics", isOn: $settings.haptics)
                } header: { Text("Features") } footer: {
                    Text(model.session?.profile.kind == .musicLan
                         ? "Share Now Playing lets music.lan show what this phone plays (its Discord presence picks it up). Search by Sound adds matches from the server's audio embeddings to search results."
                         : "Scrobbling records plays on the server, which some servers forward to Last.fm or ListenBrainz.")
                }

                Section("Library") {
                    LabeledContent("Songs", value: model.library.index.tracks.count.formatted())
                    LabeledContent("Albums", value: model.library.index.albums.count.formatted())
                    LabeledContent("Updated", value: model.library.isLoaded ? model.library.fetchedAt.formatted(.relative(presentation: .named)) : "Never")
                    Button {
                        Task { if let s = model.session { await model.library.refresh(session: s, force: true) } }
                    } label: {
                        HStack { Text("Refresh Library"); Spacer(); if model.library.isRefreshing { ProgressView() } }
                    }
                    .disabled(model.library.isRefreshing || model.session?.isOnline != true)
                    Button("Clear Artwork Cache") { ArtworkLoader.shared.clearDisk() }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–")
                    LabeledContent("Client ID", value: model.settings.clientID)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(item: $editing) { ServerEditorView(existing: $0) }
            .confirmationDialog("Clear the smart cache?", isPresented: $confirmClearCache, titleVisibility: .visible) {
                Button("Clear \(Format.bytes(model.downloads.cachedBytes))", role: .destructive) { model.downloads.clearCache() }
            } message: { Text("Downloads are kept.") }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.paper)
    }

    private var serversSection: some View {
        Section {
            ForEach(model.servers.profiles) { p in
                let active = p.id == model.servers.activeID
                HStack(spacing: 12) {
                    Button {
                        if !active { Task { await model.activate(p) } }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(active ? Theme.accent : Theme.ink3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).foregroundStyle(Theme.ink)
                                Text(active ? (model.session?.statusText ?? "") : "\(p.kind.displayName), \(p.endpoints.count) address\(p.endpoints.count == 1 ? "" : "es")")
                                    .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button { editing = p } label: {
                        Image(systemName: "info.circle").font(.system(size: 18)).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit \(p.name)")
                }
            }
            NavigationLink { ServerEditorView(existing: nil) } label: { Label("Add Server", systemImage: "plus") }
            if let session = model.session {
                NavigationLink { ConnectionDetailView(session: session) } label: { Label("Connection Details", systemImage: "network") }
            }
        } header: { Text("Servers") }
    }
}

/// Every address of the active server with its last probe result, and the phone's network state.
struct ConnectionDetailView: View {
    let session: ServerSession

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Server", value: session.profile.name)
                LabeledContent("Using", value: session.baseURL?.absoluteString ?? "None")
                LabeledContent("State", value: session.statusText)
            }
            Section("This Phone") {
                LabeledContent("Network", value: session.network.isConnected ? (session.network.isExpensive ? "Cellular / hotspot" : "Wi-Fi") : "Offline")
                LabeledContent("Tailscale", value: NetworkInterfaces.tailscaleAddress().map { "Connected, \($0)" } ?? "Not connected")
            }
            Section("Addresses") {
                ForEach(session.resolution?.results ?? []) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: r.reachable ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(r.reachable ? Theme.accent : Theme.ink3)
                            Text(r.endpoint.url.absoluteString).lineLimit(1)
                            if r.endpoint.id == session.resolution?.active?.endpoint.id {
                                Text("In use").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.night)
                                    .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.lan, in: Capsule())
                            }
                        }
                        Text(r.reachable ? "\(r.kind.displayName), \(Int((r.latency ?? 0) * 1000)) ms" : "\(r.kind.displayName), \(r.error ?? "No answer")")
                            .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                    }
                }
            }
            Section {
                Button {
                    Task { await session.resolve() }
                } label: {
                    HStack { Text("Check Again"); Spacer(); if session.isResolving { ProgressView() } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Connection")
    }
}
