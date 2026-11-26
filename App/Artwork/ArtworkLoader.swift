import SwiftUI
import UIKit
import CoreImage
import MusicsCore

/// Memory + disk image cache keyed by URL. Requests for the same URL share one download.
final class ArtworkLoader: @unchecked Sendable {
    static let shared = ArtworkLoader()

    private let memory = NSCache<NSURL, UIImage>()
    private let colors = NSCache<NSURL, UIColor>()
    private let lock = NSLock()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    var headers: [String: String] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = nil
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: c)
    }()

    init() {
        memory.totalCostLimit = 80 * 1_048_576
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    private func diskURL(_ url: URL) -> URL {
        Paths.artwork.appendingPathComponent(MD5.hex(url.absoluteString) + ".img")
    }

    func image(for url: URL) async -> UIImage? {
        if let img = cached(url) { return img }
        if let existing = lock.withLock({ inflight[url] }) { return await existing.value }
        let headers = self.headers
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> UIImage? in
            guard let self else { return nil }
            let file = self.diskURL(url)
            if let data = try? Data(contentsOf: file), let img = Self.decode(data) {
                self.store(img, for: url)
                return img
            }
            var req = URLRequest(url: url)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            guard let result = try? await self.session.data(for: req),
                  ((result.1 as? HTTPURLResponse)?.statusCode ?? 0) == 200,
                  let img = Self.decode(result.0) else { return nil }
            let data = result.0
            try? data.write(to: file, options: .atomic)
            self.store(img, for: url)
            return img
        }
        lock.withLock { inflight[url] = task }
        let img = await task.value
        lock.withLock { inflight[url] = nil }
        return img
    }

    private func store(_ img: UIImage, for url: URL) {
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        memory.setObject(img, forKey: url as NSURL, cost: cost)
    }

    /// Decodes off the main thread so scrolling never waits on JPEG decoding.
    private static func decode(_ data: Data) -> UIImage? {
        guard let img = UIImage(data: data) else { return nil }
        return img.preparingForDisplay() ?? img
    }

    /// Average colour of an image, darkened to sit behind white text (for servers without accent colours).
    func accentColor(for url: URL, image: UIImage) -> UIColor {
        if let c = colors.object(forKey: url as NSURL) { return c }
        var color = UIColor(white: 0.16, alpha: 1)
        if let ci = CIImage(image: image) {
            let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci,
                                                                      kCIInputExtentKey: CIVector(cgRect: ci.extent)])
            var px = [UInt8](repeating: 0, count: 4)
            if let out = filter?.outputImage {
                CIContext(options: [.workingColorSpace: NSNull()]).render(out, toBitmap: &px, rowBytes: 4,
                                                                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                                                         format: .RGBA8, colorSpace: nil)
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
                    .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                color = UIColor(hue: h, saturation: min(s, 0.7), brightness: min(max(b, 0.25), 0.38), alpha: 1)
            }
        }
        colors.setObject(color, forKey: url as NSURL)
        return color
    }

    func clearDisk() {
        try? FileManager.default.removeItem(at: Paths.artwork)
        Paths.dir(Paths.artwork)
        memory.removeAllObjects()
    }

    var diskBytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.artwork, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

/// Square artwork with a solid placeholder; fades in when loaded.
struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 6
    var placeholder: Color = Theme.cell
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Image(systemName: "music.note").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.ink3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.line.opacity(0.7), lineWidth: 0.5))
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ArtworkLoader.shared.cached(url) { image = hit; return }
            image = nil
            let loaded = await ArtworkLoader.shared.image(for: url)
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.2)) { image = loaded } }
        }
        .accessibilityHidden(true)
    }
}
