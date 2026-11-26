import SwiftUI
import MusicsCore

/// Add or edit a server: any number of addresses (LAN, Tailscale, public), server type auto-detected,
/// optional auth, and a live check of every address before saving.
struct ServerEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existing: ServerProfile?
    var onSaved: (() -> Void)?

    @State private var name: String
    @State private var kind: ServerKind?
    @State private var addresses: [AddressRow]
    @State private var auth: AuthMethod
    @State private var username: String
    @State private var secret: String
    @State private var headerName: String
    @State private var checking = false
    @State private var results: [ProbeResult] = []
    @State private var detectError: String?

    init(existing: ServerProfile?, onSaved: (() -> Void)? = nil) {
        self.existing = existing
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind)
        _addresses = State(initialValue: (existing.map { $0.endpoints.map(\.url.absoluteString) } ?? [""]).map { AddressRow(text: $0) })
        _auth = State(initialValue: existing?.auth ?? .none)
        _username = State(initialValue: existing?.username ?? "")
        _secret = State(initialValue: existing.flatMap { Keychain.get($0.id) } ?? "")
        _headerName = State(initialValue: existing?.headerName ?? "Authorization")
    }

    private var endpoints: [Endpoint] {
        addresses.compactMap { EndpointClassifier.normalizeURL($0.text) }.map { url in
            // Keep ids stable for existing addresses so ordering preferences survive edits.
            let old = existing?.endpoints.first { $0.url == url }
            return Endpoint(url: url, enabled: old?.enabled ?? true, id: old?.id ?? UUID())
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach($addresses) { $row in
                    HStack {
                        TextField("music.lan, 100.x.y.z or https://…", text: $row.text)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if let url = EndpointClassifier.normalizeURL(row.text) {
                            kindBadge(results.first { $0.endpoint.url == url }?.kind ?? EndpointClassifier.classify(host: url.host ?? ""))
                        }
                    }
                }
                .onDelete { addresses.remove(atOffsets: $0) }
                .onMove { addresses.move(fromOffsets: $0, toOffset: $1) }
                Button { addresses.append(AddressRow(text: "")) } label: { Label("Add Another Address", systemImage: "plus") }
            } header: {
                Text("Addresses")
            } footer: {
                Text("Add every way to reach this server: home network, Tailscale (MagicDNS name, 100.x address or *.ts.net) and a public URL. Musics uses the fastest one that answers and switches automatically when your network changes.")
            }

            Section("Server") {
                TextField("Name", text: $name, prompt: Text(suggestedName))
                Picker("Type", selection: $kind) {
                    Text("Detect automatically").tag(ServerKind?.none)
                    ForEach(ServerKind.allCases, id: \.self) { Text($0.displayName).tag(ServerKind?.some($0)) }
                }
            }

            Section {
                Picker("Sign-in", selection: $auth) {
                    Text("None").tag(AuthMethod.none)
                    Text("Username & password (Basic)").tag(AuthMethod.basic)
                    Text("Header token").tag(AuthMethod.header)
                    Text("Subsonic account").tag(AuthMethod.subsonic)
                }
                switch auth {
                case .none:
                    EmptyView()
                case .basic, .subsonic:
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $secret)
                case .header:
                    TextField("Header name", text: $headerName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Value (e.g. Bearer …)", text: $secret)
                }
            } header: {
                Text("Sign-in")
            } footer: {
                Text(auth == .none ? "music.lan on Tailscale needs no sign-in: the tailnet is the access control. Use sign-in for a public address behind Caddy basic_auth, a token header, or a Subsonic server."
                                   : "Stored in the iOS Keychain on this device.")
            }

            Section {
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Text("Check Connection")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(endpoints.isEmpty || checking)
                ForEach(results) { r in
                    HStack(alignment: .top) {
                        Image(systemName: r.reachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r.reachable ? Theme.accent : Theme.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.endpoint.url.absoluteString).font(.system(size: 14)).lineLimit(1)
                            Text(r.reachable ? "\(r.kind.displayName) · \(Int((r.latency ?? 0) * 1000)) ms" : (r.error ?? "No answer"))
                                .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                        }
                    }
                }
                if let detectError {
                    Text(detectError).font(.system(size: 13)).foregroundStyle(Theme.danger)
                }
                if results.contains(where: { !$0.reachable && $0.kind == .tailscale }) && !NetworkInterfaces.tailscaleActive() {
                    Label("Tailscale doesn't look connected on this phone. Turn it on in the Tailscale app to reach tailnet addresses.",
                          systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(Theme.ink2)
                }
            }

            if let existing, model.servers.profiles.count > 0 {
                Section {
                    Button("Remove Server", role: .destructive) {
                        Task {
                            await model.removeServer(existing.id)
                            dismiss()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(existing == nil ? "Add Server" : "Edit Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(endpoints.isEmpty || checking)
            }
        }
    }

    private var suggestedName: String {
        endpoints.first?.url.host?.components(separatedBy: ".").first?.capitalized ?? "My Music"
    }

    private func kindBadge(_ k: EndpointKind) -> some View {
        Text(k.displayName).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(k == .tailscale ? Color.black : Theme.ink2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(k == .tailscale ? Theme.accent : Theme.cellHi, in: RoundedRectangle(cornerRadius: 4))
    }

    private func draft(kind: ServerKind) -> ServerProfile {
        ServerProfile(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedName : name,
                      kind: kind, endpoints: endpoints, auth: auth, username: username, headerName: headerName)
    }

    /// Detects the server type if needed, then probes every address.
    @discardableResult
    private func check() async -> ServerKind? {
        checking = true
        detectError = nil
        defer { checking = false }
        let creds = secret.isEmpty ? nil : ServerCredentials(secret: secret)
        let candidates: [ServerKind] = kind.map { [$0] } ?? [.musicLan, .subsonic]
        var best: (ServerKind, [ProbeResult])?
        for k in candidates {
            let provider = ProviderFactory.make(draft(kind: k), credentials: creds)
            let prober = HTTPEndpointProber(provider: provider, timeout: 4)
            var rs: [ProbeResult] = []
            await withTaskGroup(of: ProbeResult.self) { g in
                for e in endpoints { g.addTask { await prober.probe(e) } }
                for await r in g { rs.append(r) }
            }
            let order = endpoints.map(\.id)
            rs.sort { (order.firstIndex(of: $0.endpoint.id) ?? 0) < (order.firstIndex(of: $1.endpoint.id) ?? 0) }
            if rs.contains(where: \.reachable) {
                best = (k, rs)
                break
            }
            if best == nil { best = (k, rs) }
        }
        results = best?.1 ?? []
        if let best, best.1.contains(where: \.reachable) {
            if kind == nil { kind = best.0 }
            return best.0
        }
        detectError = kind == nil ? "No address answered as a music.lan or Subsonic server." : "No address answered."
        return nil
    }

    private func save() async {
        var resolvedKind = kind
        if resolvedKind == nil { resolvedKind = await check() }
        // Saving an unreachable server is allowed (e.g. adding the Tailscale address while away from it),
        // defaulting to music.lan.
        let profile = draft(kind: resolvedKind ?? .musicLan)
        model.servers.upsert(profile, secret: auth == .none ? nil : secret)
        if existing == nil || model.servers.activeID == profile.id || model.session == nil {
            await model.activate(profile)
        }
        onSaved?()
        dismiss()
    }
}

struct AddressRow: Identifiable, Hashable {
    let id = UUID()
    var text: String
}
