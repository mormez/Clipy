import AppKit
import SwiftUI
import Carbon
import UniformTypeIdentifiers

final class PreferencesWindowController: NSWindowController {
    static let shared: PreferencesWindowController = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 550),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Modern Clipboard Preferences"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        window.contentView = NSHostingView(rootView: PreferencesView())
        return PreferencesWindowController(window: window)
    }()

    private override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        // Stop any active hotkey recording before showing, so closing and
        // reopening Preferences never leaves the hotkey in an unregistered state.
        NotificationCenter.default.post(name: .stopHotkeyRecording, object: nil)
        super.showWindow(sender)
    }
}

private struct PreferencesView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var selectedExcludedID: String? = nil   // used for row highlight only

    private let historyOptions   = stride(from: 5, through: 50, by: 5).map { $0 }
    private let widthOptions     = stride(from: 200, through: 600, by: 50).map { $0 }
    private let lineOptions      = [1, 2, 3]

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            excludeTab.tabItem { Label("Exclude Apps", systemImage: "app.badge.minus") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 550)
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
                Picker("Menu style:", selection: $prefs.historyMenuStyle) {
                    ForEach(HistoryMenuStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 320)

                HStack {
                    Picker("Maximum items:", selection: $prefs.maxHistoryItems) {
                        ForEach(historyOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    Button("Restore Default") { prefs.maxHistoryItems = 20 }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                HStack {
                    Picker("Items popup width:", selection: $prefs.itemsPanelWidth) {
                        ForEach(widthOptions, id: \.self) { w in
                            Text("\(w) px").tag(w)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    Button("Restore Default") { prefs.itemsPanelWidth = 400 }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                HStack {
                    Picker("Preview lines:", selection: $prefs.previewLines) {
                        ForEach(lineOptions, id: \.self) { n in
                            Text(n == 1 ? "1 line" : "\(n) lines").tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    Button("Restore Default") { prefs.previewLines = 2 }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Picker("Sort history order by:", selection: $prefs.historySortOrder) {
                    ForEach(HistorySortOrder.allCases, id: \.self) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 320)

                Toggle("Preserve formatting when pasting", isOn: $prefs.preserveFormatting)
                Text("When enabled, copied text keeps its original formatting (bold, links, colors, etc.) when pasted. When disabled, everything is pasted as plain text.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch Modern Clipboard at login", isOn: $prefs.launchAtLogin)
            }
            Section("Hotkeys") {
                HStack {
                    Text("Show history popup:")
                    Spacer()
                    HotkeyRecorderView(keyCode: $prefs.mainMenuKeyCode, modifiers: $prefs.mainMenuModifiers)
                    Button("Restore Default") {
                        prefs.mainMenuKeyCode   = UInt32(kVK_ANSI_V)
                        prefs.mainMenuModifiers = UInt32(cmdKey | shiftKey)
                        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                HStack {
                    Text("Show snippets popup:")
                    Spacer()
                    HotkeyRecorderView(keyCode: $prefs.snippetsMenuKeyCode, modifiers: $prefs.snippetsMenuModifiers)
                    Button("Restore Default") {
                        prefs.snippetsMenuKeyCode   = UInt32(kVK_ANSI_S)
                        prefs.snippetsMenuModifiers = UInt32(cmdKey | shiftKey)
                        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }

                Picker("Paste and match style modifier:", selection: $prefs.matchStyleModifier) {
                    ForEach(MatchStyleModifier.allCases, id: \.self) { modifier in
                        Text(modifier.label).tag(modifier)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 320)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            // Snap to nearest valid option if stored value is outside range
            if !historyOptions.contains(prefs.maxHistoryItems) {
                let nearest = historyOptions.min(by: { abs($0 - prefs.maxHistoryItems) < abs($1 - prefs.maxHistoryItems) }) ?? 20
                prefs.maxHistoryItems = nearest
            }
            if !widthOptions.contains(prefs.itemsPanelWidth) {
                let nearest = widthOptions.min(by: { abs($0 - prefs.itemsPanelWidth) < abs($1 - prefs.itemsPanelWidth) }) ?? 400
                prefs.itemsPanelWidth = nearest
            }
        }
    }

    private var excludeTab: some View {
        VStack(spacing: 0) {
            Text("Modern Clipboard won't record content copied from these apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    if prefs.excludedBundleIDs.isEmpty {
                        Text("No apps excluded")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(prefs.excludedBundleIDs, id: \.self) { bundleID in
                            HStack {
                                ExcludedAppRow(bundleID: bundleID)
                                Spacer()
                                Button {
                                    removeApp(bundleID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 15))
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 8)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                bundleID == selectedExcludedID
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedExcludedID = (selectedExcludedID == bundleID) ? nil : bundleID
                            }

                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))

            // + toolbar
            Divider()
            HStack(spacing: 6) {
                Button { pickApp() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add apps to exclude")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))

            // Auto-exclude button
            Button(action: autoExcludePasswordManagers) {
                Label("Auto-exclude known password managers", systemImage: "lock.shield")
            }
            .buttonStyle(.bordered)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private static let knownPasswordManagers: [String] = [
        "com.1password.1password",          // 1Password 8
        "com.agilebits.onepassword7",       // 1Password 7
        "com.bitwarden.desktop",            // Bitwarden
        "com.lastpass.lastpassmac",         // LastPass
        "com.dashlane.Dashlane",            // Dashlane
        "org.keepassxc.keepassxc",          // KeePassXC
        "com.pinkymacware.Strongbox",       // Strongbox
        "com.nordpass.macos",               // NordPass
        "com.siber.roboform",               // RoboForm
        "in.sinew.Enpass-Desktop",          // Enpass
        "com.callpod.keeperdesktop",        // Keeper
        "me.proton.pass.macos",             // Proton Pass
    ]

    private func removeApp(_ bundleID: String) {
        // Full reassignment guarantees @Published triggers a SwiftUI update
        prefs.excludedBundleIDs = prefs.excludedBundleIDs.filter { $0 != bundleID }
        if selectedExcludedID == bundleID { selectedExcludedID = nil }
    }

    private func autoExcludePasswordManagers() {
        let toAdd = Self.knownPasswordManagers.filter { !prefs.excludedBundleIDs.contains($0) }
        prefs.excludedBundleIDs.append(contentsOf: toAdd)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to exclude"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  !prefs.excludedBundleIDs.contains(bundleID) else { continue }
            prefs.excludedBundleIDs.append(bundleID)
        }
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
            Text("A modern clipboard manager")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 40)

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("Developer:").foregroundStyle(.secondary)
                    Text("Developed by Mor Mezrich for Myrrh Labs.").fontWeight(.medium)
                }
                HStack(spacing: 4) {
                    Text("Contact:").foregroundStyle(.secondary)
                    Link("modern.clipboard@gmail.com",
                         destination: URL(string: "mailto:modern.clipboard@gmail.com")!)
                        .foregroundStyle(.blue)
                }
                HStack(spacing: 4) {
                    Text("Modern Clipboard is based on Clipy.").foregroundStyle(.secondary)
                    CopyrightLinkView(label: "See copyright notice")
                }
                .padding(.top, 8)
            }
            .font(.system(size: 13))

            Button("Check for Updates…") {
                UpdaterManager.shared.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)

            Spacer()

            HStack(spacing: 4) {
                Text("Modern Clipboard is provided as-is.").foregroundStyle(.secondary)
                CopyrightLinkView(label: "See license")
            }
            .font(.system(size: 13))

            Divider().padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text("Documentation")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    DocDownloadButton(
                        label: "Quick Start Guide",
                        icon: "arrow.down.doc",
                        resource: "Modern Clipboard Quick Start",
                        ext: "docx"
                    )
                    DocDownloadButton(
                        label: "User Manual",
                        icon: "arrow.down.doc",
                        resource: "Modern Clipboard User Manual",
                        ext: "docx"
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Copyright notice

private struct CopyrightLinkView: View {
    let label: String
    @State private var showingCopyright = false

    var body: some View {
        Button(label) {
            showingCopyright = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .sheet(isPresented: $showingCopyright) {
            CopyrightModalView(isPresented: $showingCopyright)
        }
    }
}

private struct CopyrightModalView: View {
    @Binding var isPresented: Bool
    @State private var copied = false

    private let licenseText = """
The MIT License (MIT)
Copyright (c) 2015-2018 Clipy Project

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Copyright Notice")
                .font(.headline)

            ScrollView {
                Text(licenseText)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button(copied ? "Copied!" : "Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(licenseText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .disabled(copied)

                Button("Save as .txt…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "LICENSE.txt"
                    panel.allowedContentTypes = [.plainText]
                    if panel.runModal() == .OK, let url = panel.url {
                        try? licenseText.write(to: url, atomically: true, encoding: .utf8)
                    }
                }

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 320)
    }
}

// MARK: - Doc download button

private struct DocDownloadButton: View {
    let label: String
    let icon: String
    let resource: String
    let ext: String

    @State private var feedback: DownloadFeedback = .idle

    enum DownloadFeedback { case idle, success, failure }

    var body: some View {
        Button {
            download()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: feedbackIcon)
                    .foregroundStyle(feedbackColor)
                Text(feedback == .success ? "Saved" : label)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(feedback != .idle)
    }

    private var feedbackIcon: String {
        switch feedback {
        case .idle:    return icon
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private var feedbackColor: Color {
        switch feedback {
        case .idle:    return .primary
        case .success: return .green
        case .failure: return .red
        }
    }

    private func download() {
        guard let src = Bundle.main.url(forResource: resource, withExtension: ext) else {
            flash(.failure); return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(resource).\(ext)"
        panel.allowedContentTypes = [.init(filenameExtension: ext) ?? .data]
        // Default to ~/Downloads
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        do {
            // Replace any existing file at the chosen location
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            flash(.success)
        } catch {
            flash(.failure)
        }
    }

    private func flash(_ state: DownloadFeedback) {
        feedback = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { feedback = .idle }
    }
}

// MARK: - Excluded app row

private struct ExcludedAppRow: View {
    let bundleID: String

    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    private var appName: String {
        guard let url = appURL, let bundle = Bundle(url: url) else { return bundleID }
        return bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
    }
    private var appIcon: NSImage {
        guard let url = appURL else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 24, height: 24)
        return icon
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable().scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(appName).font(.system(size: 13))
                Text(bundleID).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
        .onReceive(NotificationCenter.default.publisher(for: .stopHotkeyRecording)) { _ in
            stopRecording()
        }
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
        guard isRecording else { return }
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        // Re-register with the current hotkey (new or unchanged)
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
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
