import AppKit
import SwiftUI
import Carbon

final class PreferencesWindowController: NSWindowController {
    static let shared: PreferencesWindowController = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Modern Clipboard Preferences"
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
    @State private var excludedText: String = Preferences.shared.excludedBundleIDs.joined(separator: "\n")

    private let historyOptions = stride(from: 5, through: 50, by: 5).map { $0 }

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
            Section("Permissions") {
                HStack {
                    Image(systemName: AXIsProcessTrustedWithOptions(nil) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(AXIsProcessTrustedWithOptions(nil) ? .green : .orange)
                    Text(AXIsProcessTrustedWithOptions(nil) ? "Accessibility granted" : "Accessibility not granted")
                        .foregroundStyle(AXIsProcessTrustedWithOptions(nil) ? Color.primary : Color.orange)
                    Spacer()
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Section("Clipboard History") {
                Picker("Maximum items:", selection: $prefs.maxHistoryItems) {
                    ForEach(historyOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)

                Picker("Menu style:", selection: $prefs.historyMenuStyle) {
                    ForEach(HistoryMenuStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 320)
            }
            Section("Startup") {
                Toggle("Launch Modern Clipboard at login", isOn: $prefs.launchAtLogin)
            }
            Section("Hotkey") {
                HStack {
                    Text("Show history popup:")
                    Spacer()
                    HotkeyRecorderView(
                        keyCode: $prefs.mainMenuKeyCode,
                        modifiers: $prefs.mainMenuModifiers
                    )
                    Button("Restore Default") {
                        prefs.mainMenuKeyCode  = UInt32(kVK_ANSI_V)
                        prefs.mainMenuModifiers = UInt32(controlKey | shiftKey)
                        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            // If stored value isn't one of our valid options, snap to nearest
            if !historyOptions.contains(prefs.maxHistoryItems) {
                let nearest = historyOptions.min(by: { abs($0 - prefs.maxHistoryItems) < abs($1 - prefs.maxHistoryItems) }) ?? 20
                prefs.maxHistoryItems = nearest
            }
        }
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
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
            }
            Text("Modern Clipboard").font(.largeTitle.bold())
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

// MARK: - Hotkey recorder

struct HotkeyRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "Press shortcut…" : hotkeyLabel)
                .frame(minWidth: 100, alignment: .center)
                .foregroundStyle(isRecording ? Color.red : Color.primary)
        }
        .buttonStyle(.bordered)
        .onDisappear { stopRecording() }
    }

    private var hotkeyLabel: String { modString(modifiers) + keyString(keyCode) }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        // Temporarily unregister the current hotkey so it doesn't fire while recording
        HotkeyManager.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { self.stopRecording(); return nil } // Esc = cancel
            guard !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
                return event
            }
            self.apply(event)
            return nil
        }
    }

    private func apply(_ event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var m: UInt32 = 0
        if event.modifierFlags.contains(.control) { m |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option)  { m |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift)   { m |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { m |= UInt32(cmdKey) }
        modifiers = m
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        // Re-register with (possibly new) hotkey
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    private func modString(_ m: UInt32) -> String {
        var s = ""
        if m & UInt32(controlKey) != 0 { s += "⌃" }
        if m & UInt32(optionKey)  != 0 { s += "⌥" }
        if m & UInt32(shiftKey)   != 0 { s += "⇧" }
        if m & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    private func keyString(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            0x00:"A", 0x01:"S", 0x02:"D", 0x03:"F", 0x04:"H", 0x05:"G",
            0x06:"Z", 0x07:"X", 0x08:"C", 0x09:"V", 0x0B:"B", 0x0C:"Q",
            0x0D:"W", 0x0E:"E", 0x0F:"R", 0x10:"Y", 0x11:"T", 0x12:"1",
            0x13:"2", 0x14:"3", 0x15:"4", 0x16:"6", 0x17:"5", 0x18:"=",
            0x19:"9", 0x1A:"7", 0x1B:"-", 0x1C:"8", 0x1D:"0", 0x1E:"]",
            0x1F:"O", 0x20:"U", 0x21:"[", 0x22:"I", 0x23:"P", 0x25:"L",
            0x26:"J", 0x27:"'", 0x28:"K", 0x29:";", 0x2A:"\\",0x2B:",",
            0x2C:"/", 0x2D:"N", 0x2E:"M", 0x2F:".", 0x32:"`",
            0x24:"↩", 0x30:"⇥", 0x31:"Space", 0x33:"⌫", 0x35:"⎋",
            0x7A:"F1",0x78:"F2",0x63:"F3",0x76:"F4",0x60:"F5",0x61:"F6",
            0x62:"F7",0x64:"F8",0x65:"F9",0x6D:"F10",0x67:"F11",0x6F:"F12",
            0x7B:"←", 0x7C:"→", 0x7D:"↓", 0x7E:"↑",
        ]
        return map[code] ?? "?"
    }
}
