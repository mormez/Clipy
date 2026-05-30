import AppKit

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    var isPaused = false
    private var pauseResumeWorkItem: DispatchWorkItem?

    private init() {}

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pause(for duration: TimeInterval = 1.5) {
        isPaused = true
        pauseResumeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastChangeCount = NSPasteboard.general.changeCount
            self.isPaused = false
        }
        pauseResumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func checkClipboard() {
        guard !isPaused else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let excluded = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Preferences.shared.excludedBundleIDs.contains(excluded) { return }

        captureClipboard(pb)
    }

    private func captureClipboard(_ pb: NSPasteboard) {
        // Image first
        if let image = NSImage(pasteboard: pb), let data = image.tiffRepresentation {
            ClipboardHistory.shared.add(ClipItem(
                id: UUID(), type: .image,
                stringValue: nil, imageData: data, timestamp: Date()
            ))
            return
        }

        let checks: [(NSPasteboard.PasteboardType, ClipType)] = [
            (.rtf, .rtf),
            (.html, .html),
            (.string, .string),
            (.fileURL, .fileURL),
        ]
        for (pbType, clipType) in checks {
            if let str = pb.string(forType: pbType), !str.isEmpty {
                ClipboardHistory.shared.add(ClipItem(
                    id: UUID(), type: clipType,
                    stringValue: str, imageData: nil, timestamp: Date()
                ))
                return
            }
        }
    }
}
