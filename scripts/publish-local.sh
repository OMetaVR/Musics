#!/usr/bin/env bash
# Publishes the newest CI-built IPA to your tailnet, for installing on a phone.
#
# Downloads the IPA artifact from the latest successful "Build" run (or the run id given), writes an
# install page and an AltStore-format source (works in SideStore and Feather) next to it, and serves the
# folder at https://<this machine>.<tailnet>.ts.net/musics/ with `tailscale serve` (tailnet only).
#
# Usage: scripts/publish-local.sh [run-id]
# Env:   MUSICS_DIST (default ~/.local/share/musics-dist), MUSICS_SERVE_PATH (default /musics)
set -euo pipefail
cd "$(dirname "$0")/.."

DIST=${MUSICS_DIST:-$HOME/.local/share/musics-dist}
SERVE_PATH=${MUSICS_SERVE_PATH:-/musics}
RUN=${1:-$(gh run list --workflow Build --branch main --status success -L 1 --json databaseId -q '.[0].databaseId')}
[ -n "$RUN" ] || { echo "No successful Build run yet." >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh run download "$RUN" -n Musics-ipa -D "$tmp"
ipa=$(ls "$tmp"/*.ipa | head -1)

mkdir -p "$DIST"
cp "$ipa" "$DIST/Musics.ipa.tmp" && mv "$DIST/Musics.ipa.tmp" "$DIST/Musics.ipa"
cp App/Assets.xcassets/AppIcon.appiconset/icon-1024.png "$DIST/icon.png"

host=$(tailscale status --self --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
base="https://${host}${SERVE_PATH}"
commit=$(gh run view "$RUN" --json headSha -q .headSha)

python3 - "$DIST" "$base" "$RUN" "$commit" <<'PY'
import datetime, html, json, os, plistlib, sys, zipfile
dist, base, run, commit = sys.argv[1:5]
ipa = os.path.join(dist, "Musics.ipa")
with zipfile.ZipFile(ipa) as z:
    info = plistlib.loads(z.read("Payload/Musics.app/Info.plist"))
version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
size = os.path.getsize(ipa)
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
url = f"{base}/Musics.ipa?b={build}"
desc = "Native player for self-hosted music: music.lan and Subsonic/Navidrome."
source = {
    "name": "Musics (tailnet)",
    "identifier": "com.ometavr.musics.tailnet",
    "iconURL": f"{base}/icon.png",
    "apps": [{
        "name": "Musics", "bundleIdentifier": info["CFBundleIdentifier"], "developerName": "OMetaVR",
        "version": version, "versionDate": now.isoformat(), "downloadURL": url, "size": size,
        "iconURL": f"{base}/icon.png", "localizedDescription": desc, "subtitle": "Your music, your server",
        "tintColor": "5CCB8A",
        "versions": [{"version": version, "buildVersion": build, "date": now.isoformat(),
                      "downloadURL": url, "size": size, "localizedDescription": f"CI run {run}, commit {commit[:7]}"}],
    }],
}
with open(os.path.join(dist, "source.json"), "w") as f:
    json.dump(source, f, indent=2)

src = f"{base}/source.json"
page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Musics</title>
<style>
:root{{color-scheme:dark}}body{{margin:0;background:#0A0A0B;color:#E8E9EB;font:16px/1.45 -apple-system,system-ui,sans-serif}}
main{{max-width:520px;margin:0 auto;padding:32px 16px}}img{{width:88px;height:88px;border-radius:20px;border:1px solid #2A2D32}}
h1{{margin:14px 0 2px;font-size:28px}}.meta{{color:#80848C;font-size:14px}}
a.btn{{display:block;text-align:center;margin:22px 0 10px;padding:14px;border-radius:10px;background:#5CCB8A;color:#000;font-weight:600;text-decoration:none}}
.card{{background:#121316;border:1px solid #1E2024;border-radius:10px;padding:14px;margin-top:18px}}
code{{display:block;word-break:break-all;background:#0F1012;border:1px solid #1E2024;border-radius:6px;padding:8px;margin:8px 0;font-size:13px}}
ol{{padding-left:20px;margin:6px 0}}li{{margin:4px 0}}button{{background:#16171B;color:#5CCB8A;border:1px solid #2A2D32;border-radius:8px;padding:8px 12px;font:inherit}}
</style></head><body><main>
<img src="icon.png" alt=""><h1>Musics</h1>
<div class="meta">Version {html.escape(version)} (build {html.escape(build)}) · {size/1048576:.1f} MB · {now:%Y-%m-%d %H:%M} UTC · commit {commit[:7]}</div>
<a class="btn" href="Musics.ipa?b={build}" download>Download IPA</a>
<div class="meta">Unsigned. Install it with Feather, SideStore, AltStore or TrollStore, which sign it on install.</div>
<div class="card"><b>Get updates automatically</b>
<ol><li>Copy the source URL below.</li><li>Feather: Sources → + · SideStore/AltStore: Sources → +.</li><li>New builds appear as updates.</li></ol>
<code id="src">{html.escape(src)}</code><button onclick="navigator.clipboard.writeText(document.getElementById('src').textContent);this.textContent='Copied'">Copy source URL</button>
</div>
<div class="card"><b>Install from the download</b>
<ol><li>Tap Download IPA; it lands in Files → Downloads.</li><li>Open it and share it to Feather (or SideStore) to install.</li></ol></div>
</main></body></html>"""
with open(os.path.join(dist, "index.html"), "w") as f:
    f.write(page)
print(f"Musics {version} ({build}) published")
PY

if ! tailscale serve --bg --set-path "$SERVE_PATH" "$DIST" >/dev/null 2>&1; then
  sudo tailscale serve --bg --set-path "$SERVE_PATH" "$DIST" >/dev/null
fi
echo "Install page: ${base}/"
echo "Source:       ${base}/source.json"
