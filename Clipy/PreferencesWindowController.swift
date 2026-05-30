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
    @State private var historyCount: Double = Double(Preferences.shared.maxHistoryItems)
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
                    Slider(value: $historyCount, in: 10...500, step: 10)
                    Text("\(Int(historyCount))").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                .onChange(of: historyCount) { _, v in prefs.maxHistoryItems = Int(v) }
            }
            Section("Startup") {
                Toggle("Launch Modern Clipy at login", isOn: $prefs.launchAtLogin)
            }
            Section("Hotkey") {
                Text("Ctrl + Shift + V — show clipboard history")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text("(Hotkey customization coming in a future version)")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { historyCount = Double(prefs.maxHistoryItems) }
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
