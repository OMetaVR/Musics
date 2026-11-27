import SwiftUI
import MusicsCore

struct WelcomeView: View {
    @State private var adding = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 26) {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your music,\nyour server.")
                        .font(Typeface.condensed(56, .extraBold, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.paper)
                        .lineSpacing(0)
                        .minimumScaleFactor(0.6)
                    Text("Musics plays the library you host yourself: music.lan, Navidrome, or any Subsonic server.")
                        .font(.system(size: 17)).foregroundStyle(Theme.dust)
                }
                VStack(alignment: .leading, spacing: 14) {
                    point("network", "Home, Tailscale and public addresses in one server. The working one is picked automatically.")
                    point("bolt", "Instant search across your whole library, even offline.")
                    point("arrow.down.circle", "Downloads, plus a smart cache that keeps the next songs ready.")
                    point("waveform.path.ecg", "Radio, search by sound and Sonic Adventure on music.lan.")
                }
                Spacer()
                NavigationLink { ServerEditorView(existing: nil) } label: {
                    Text("Add your server").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(primary: true))
            }
            .padding(24)
            .background(Theme.bg.ignoresSafeArea())
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.lan).frame(width: 24)
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.paper.opacity(0.85))
        }
    }
}
