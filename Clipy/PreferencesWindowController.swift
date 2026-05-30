import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    static let shared: PreferencesWindowController = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Modern Clipy Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: PreferencesView())
        return PreferencesWindowController(window: window)
    }()

    private override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { fatalError() }
}

private struct PreferencesView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var historyCountText: String = "\(Preferences.shared.maxHistoryItems)"
    @State private var excludedText: String = Preferences.shared.excludedBundleIDs.joined(separator: "\n")

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            excludeTab.tabItem { Label("Exclude Apps", systemImage: "app.badge.minus") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320)
    }

    private var generalTab: some View {
        Form {
            Section("Clipboard History") {
                HStack {
                    Text("Maximum items:")
                    TextField("", text: $historyCountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                        .onSubmit { applyHistoryCount() }
                    Text("(1 – 50)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            Section("Startup") {
                Toggle("Launch Modern Clipy at login", isOn: $prefs.launchAtLogin)
            }
            Section("Hotkey") {
                Text("⇧ ⌘ V — show clipboard history popup")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text("(Hotkey customization coming in a future version)")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { historyCountText = "\(prefs.maxHistoryItems)" }
        .onDisappear { applyHistoryCount() }
    }

    private func applyHistoryCount() {
        guard let value = Int(historyCountText) else { return }
        let clamped = min(max(value, 1), 50)
        prefs.maxHistoryItems = clamped
        // Correct the text if it was out of range
        if clamped != value { historyCountText = "\(clamped)" }
    }

    private var excludeTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bundle IDs of apps to exclude from clipboard tracking (one per line):")
                .font(.callout)
            TextEditor(text: $excludedText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(Color.gray.opacity(0.4))
            HStack {
                Spacer()
                Button("Save") {
                    prefs.excludedBundleIDs = excludedText
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            }
        }
        .padding()
        .onAppear { excludedText = prefs.excludedBundleIDs.joined(separator: "\n") }
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.blue)
            Text("Modern Clipy").font(.largeTitle.bold())
            Text("Version 1.0").foregroundStyle(.secondary)
            Text("A modern clipboard manager for Apple Silicon Mac")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
