import SwiftUI
import MusicsCore

struct WelcomeView: View {
    @State private var adding = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 26) {
                Spacer()
                Image(systemName: "waveform").font(.system(size: 44, weight: .semibold)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Musics").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.inkHi)
                    Text("A player for the music you host yourself: music.lan, Navidrome, or any Subsonic server.")
                        .font(.system(size: 17)).foregroundStyle(Theme.ink2)
                }
                VStack(alignment: .leading, spacing: 14) {
                    point("network", "Home, Tailscale and public addresses in one server. The working one is picked automatically.")
                    point("bolt", "Instant search across your whole library, even offline.")
                    point("arrow.down.circle", "Downloads, plus a smart cache that keeps the next songs ready.")
                    point("waveform.path.ecg", "Radio, search by sound and Sonic Adventure on music.lan.")
                }
                Spacer()
                NavigationLink { ServerEditorView(existing: nil) } label: {
                    Text("Add a Server").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(primary: true))
            }
            .padding(24)
            .background(Theme.bg.ignoresSafeArea())
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.accent).frame(width: 24)
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.ink2)
        }
    }
}
