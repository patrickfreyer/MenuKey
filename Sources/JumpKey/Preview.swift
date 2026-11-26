import AppKit
import ScreenCaptureKit
import SwiftUI

/// A small, quiet thumbnail of the selected window, shown beside the panel.
/// Opt-in, because capturing other windows needs Screen Recording permission.
@MainActor
final class PreviewController: ObservableObject {
    @Published private(set) var image: NSImage?

    private let panel: NSPanel
    private var cache: [CGWindowID: NSImage] = [:]
    private var content: SCShareableContent?
    private var currentID: CGWindowID?
    private var task: Task<Void, Never>?

    static let width: CGFloat = 300

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSHostingView(rootView: PreviewView(controller: self))
        host.sizingOptions = []
        panel.contentView = host
    }

    static var isEnabled: Bool { Settings.windowPreviews && CGPreflightScreenCaptureAccess() }

    func beginSession() {
        cache = [:]
        content = nil
    }

    func hide() {
        task?.cancel()
        currentID = nil
        panel.orderOut(nil)
    }

    func show(for item: SearchItem?, beside host: NSWindow) {
        guard Self.isEnabled, let item, item.kind == .window, let wid = item.windowID else {
            hide()
            return
        }
        if wid == currentID, panel.isVisible { position(beside: host); return }
        currentID = wid
        task?.cancel()

        if let cached = cache[wid] {
            present(cached, beside: host)
            return
        }
        task = Task { [weak self, weak host] in
            try? await Task.sleep(for: .milliseconds(70))
            guard let self, !Task.isCancelled else { return }
            guard let img = await self.capture(wid), !Task.isCancelled, self.currentID == wid, let host else { return }
            self.cache[wid] = img
            self.present(img, beside: host)
        }
    }

    private func present(_ img: NSImage, beside host: NSWindow) {
        image = img
        position(beside: host)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        }
    }

    private func position(beside host: NSWindow) {
        guard let img = image else { return }
        let w = Self.width
        let h = min(max(w * img.size.height / max(img.size.width, 1), 120), 240) + 16
        let hf = host.frame
        let screen = host.screen?.visibleFrame ?? .infinite
        var x = hf.maxX + 14
        if x + w > screen.maxX { x = hf.minX - 14 - w }
        panel.setFrame(NSRect(x: x, y: hf.maxY - h, width: w, height: h), display: true)
        panel.invalidateShadow()
    }

    private func capture(_ wid: CGWindowID) async -> NSImage? {
        do {
            if content == nil {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            }
            guard let window = content?.windows.first(where: { $0.windowID == wid }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale: CGFloat = 2
            let maxW = Self.width * scale
            let ratio = window.frame.height / max(window.frame.width, 1)
            config.width = Int(maxW)
            config.height = Int(maxW * ratio)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        } catch {
            return nil
        }
    }
}

private struct PreviewView: View {
    @ObservedObject var controller: PreviewController

    var body: some View {
        Group {
            if let img = controller.image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
