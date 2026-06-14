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
        // 1. Image
        if let image = NSImage(pasteboard: pb), let data = image.tiffRepresentation {
            ClipboardHistory.shared.add(ClipItem(
                id: UUID(), type: .image,
                stringValue: nil, imageData: data, timestamp: Date()
            ))
            return
        }

        // 2. File URL
        if let str = pb.string(forType: .fileURL), !str.isEmpty {
            ClipboardHistory.shared.add(ClipItem(
                id: UUID(), type: .fileURL,
                stringValue: str, imageData: nil, timestamp: Date()
            ))
            return
        }

        // 3. Plain text — always preferred over rich formats for clean display
        if let str = pb.string(forType: .string), !str.isEmpty {
            var richData: Data? = nil
            var richFormat: ClipType? = nil
            if Preferences.shared.preserveFormatting {
                if let rtf = pb.data(forType: .rtf) {
                    richData = rtf
                    richFormat = .rtf
                } else if let html = pb.data(forType: .html) {
                    richData = html
                    richFormat = .html
                }
            }
            ClipboardHistory.shared.add(ClipItem(
                id: UUID(), type: .string,
                stringValue: str, imageData: nil, timestamp: Date(),
                richData: richData, richFormat: richFormat
            ))
            return
        }

        // 4. RTF — extract plain text so no markup code is shown
        if let data = pb.data(forType: .rtf),
           let attrStr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            let plain = attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                ClipboardHistory.shared.add(ClipItem(
                    id: UUID(), type: .string,
                    stringValue: plain, imageData: nil, timestamp: Date()
                ))
                return
            }
        }

        // 5. HTML — extract plain text so no markup code is shown
        if let data = pb.data(forType: .html),
           let attrStr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html],
               documentAttributes: nil
           ) {
            let plain = attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                ClipboardHistory.shared.add(ClipItem(
                    id: UUID(), type: .string,
                    stringValue: plain, imageData: nil, timestamp: Date()
                ))
            }
        }
    }
}
