// Renders every figure page in build/figures/*.html to docs/img/<name>.png (2x on a Retina Mac).
//
//     lune run scripts/figures        # writes the HTML pages from real data
//     swift tools/render-figures.swift
//
// macOS only (uses WebKit). Each page sizes itself; the renderer measures the
// body and snapshots exactly that area.

import AppKit
import WebKit

let inputDir = URL(fileURLWithPath: "build/figures", isDirectory: true)
let outputDir = URL(fileURLWithPath: "docs/img", isDirectory: true)
// The offscreen window renders at the screen's backing scale (2x on Retina),
// so CSS pixels map 1:1 to points here and the PNG comes out at 2x.
let scale: CGFloat = 1

final class Renderer: NSObject, WKNavigationDelegate {
    private var queue: [URL]
    private let webView: WKWebView
    private let window: NSWindow
    private var current: URL?

    init(pages: [URL]) {
        queue = pages
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1200), configuration: config)
        window = NSWindow(
            contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        webView.navigationDelegate = self
        webView.pageZoom = scale
    }

    func next() {
        guard !queue.isEmpty else {
            NSApplication.shared.terminate(nil)
            return
        }
        let page = queue.removeFirst()
        current = page
        webView.setFrameSize(NSSize(width: 1600, height: 1200))
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Let fonts settle, then measure the figure root.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let js = "(() => { const r = document.querySelector('.figure').getBoundingClientRect(); return [Math.ceil(r.width), Math.ceil(r.height)]; })()"
            webView.evaluateJavaScript(js) { result, error in
                guard let size = result as? [Double], size.count == 2 else {
                    print("could not measure \(self.current?.lastPathComponent ?? "?"): \(String(describing: error))")
                    self.next()
                    return
                }
                let w = CGFloat(size[0]) * scale
                let h = CGFloat(size[1]) * scale
                webView.setFrameSize(NSSize(width: w, height: h))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let snap = WKSnapshotConfiguration()
                    snap.rect = NSRect(x: 0, y: 0, width: w, height: h)
                    snap.snapshotWidth = NSNumber(value: Double(w))
                    webView.takeSnapshot(with: snap) { image, error in
                        if let image = image, let tiff = image.tiffRepresentation,
                            let rep = NSBitmapImageRep(data: tiff),
                            let png = rep.representation(using: .png, properties: [:])
                        {
                            let name = self.current!.deletingPathExtension().lastPathComponent + ".png"
                            try? png.write(to: outputDir.appendingPathComponent(name))
                            print("\(name)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
                        } else {
                            print("snapshot failed: \(String(describing: error))")
                        }
                        self.next()
                    }
                }
            }
        }
    }
}

let pages = (try? FileManager.default.contentsOfDirectory(at: inputDir, includingPropertiesForKeys: nil))?
    .filter { $0.pathExtension == "html" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
if pages.isEmpty {
    print("no pages in build/figures; run `lune run scripts/figures` first")
    exit(1)
}
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer(pages: pages)
DispatchQueue.main.async { renderer.next() }
app.run()
