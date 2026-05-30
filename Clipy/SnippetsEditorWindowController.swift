import AppKit
import SwiftUI

final class SnippetsEditorWindowController: NSWindowController {
    static let shared: SnippetsEditorWindowController = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Snippets"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 380)
        window.center()
        window.contentView = NSHostingView(rootView: SnippetsEditorView())
        return SnippetsEditorWindowController(window: window)
    }()

    private override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { fatalError() }
}

private struct SnippetsEditorView: View {
    @ObservedObject private var manager = SnippetManager.shared
    @State private var selectedFolderID: UUID?
    @State private var selectedSnippetID: UUID?
    @State private var showAddFolder = false
    @State private var newFolderName = ""

    private var selectedFolderIndex: Int? {
        manager.folders.firstIndex { $0.id == selectedFolderID }
    }

    var body: some View {
        NavigationSplitView {
            folderList
        } content: {
            if let fi = selectedFolderIndex {
                SnippetList(folderIndex: fi, selectedSnippetID: $selectedSnippetID)
            } else {
                ContentUnavailableView("Select a Folder", systemImage: "folder")
            }
        } detail: {
            if let fi = selectedFolderIndex,
               let si = manager.folders[fi].snippets.firstIndex(where: { $0.id == selectedSnippetID }) {
                SnippetEditor(folderIndex: fi, snippetIndex: si)
            } else {
                ContentUnavailableView("Select a Snippet", systemImage: "text.quote")
            }
        }
        .sheet(isPresented: $showAddFolder) {
            addFolderSheet
        }
    }

    private var folderList: some View {
        List(selection: $selectedFolderID) {
            ForEach(manager.folders) { folder in
                Label(folder.name, systemImage: "folder")
                    .tag(folder.id)
            }
            .onMove { manager.moveFolder(from: $0, to: $1) }
            .onDelete { indexSet in indexSet.sorted(by: >).forEach { manager.removeFolder(at: $0) } }
        }
        .navigationTitle("Folders")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showAddFolder = true }) { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    guard let id = selectedFolderID,
                          let idx = manager.folders.firstIndex(where: { $0.id == id }) else { return }
                    manager.removeFolder(at: idx)
                    selectedFolderID = nil
                }) { Image(systemName: "minus") }
                .disabled(selectedFolderID == nil)
            }
        }
    }

    private var addFolderSheet: some View {
        VStack(spacing: 20) {
            Text("New Folder").font(.headline)
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack(spacing: 12) {
                Button("Cancel") { showAddFolder = false; newFolderName = "" }
                Button("Add") {
                    guard !newFolderName.isEmpty else { return }
                    manager.addFolder(name: newFolderName)
                    newFolderName = ""
                    showAddFolder = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newFolderName.isEmpty)
            }
        }
        .padding(24)
    }
}

private struct SnippetList: View {
    let folderIndex: Int
    @ObservedObject private var manager = SnippetManager.shared
    @Binding var selectedSnippetID: UUID?
    @State private var showAddSnippet = false
    @State private var newTitle = ""
    @State private var newContent = ""

    var body: some View {
        let folder = manager.folders[folderIndex]
        List(selection: $selectedSnippetID) {
            ForEach(folder.snippets) { snippet in
                Text(snippet.title).tag(snippet.id)
            }
            .onMove { manager.moveSnippet(in: folderIndex, from: $0, to: $1) }
            .onDelete { indexSet in indexSet.sorted(by: >).forEach { manager.removeSnippet(at: $0, from: folderIndex) } }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showAddSnippet = true }) { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    guard let id = selectedSnippetID,
                          let si = manager.folders[folderIndex].snippets.firstIndex(where: { $0.id == id }) else { return }
                    manager.removeSnippet(at: si, from: folderIndex)
                    selectedSnippetID = nil
                }) { Image(systemName: "minus") }
                .disabled(selectedSnippetID == nil)
            }
        }
        .sheet(isPresented: $showAddSnippet) {
            addSnippetSheet
        }
    }

    private var addSnippetSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Snippet").font(.headline)
            TextField("Title", text: $newTitle).textFieldStyle(.roundedBorder)
            TextEditor(text: $newContent)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .border(Color.gray.opacity(0.3))
            HStack {
                Spacer()
                Button("Cancel") { showAddSnippet = false; newTitle = ""; newContent = "" }
                Button("Add") {
                    manager.addSnippet(Snippet(title: newTitle, content: newContent), to: folderIndex)
                    showAddSnippet = false; newTitle = ""; newContent = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct SnippetEditor: View {
    let folderIndex: Int
    let snippetIndex: Int
    @ObservedObject private var manager = SnippetManager.shared
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var isDirty = false

    private var snippet: Snippet { manager.folders[folderIndex].snippets[snippetIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: title) { _, _ in isDirty = true }

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(Color.gray.opacity(0.3))
                .onChange(of: content) { _, _ in isDirty = true }

            HStack {
                Spacer()
                Button("Save") {
                    manager.updateSnippet(at: snippetIndex, in: folderIndex, title: title, content: content)
                    isDirty = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty)
            }
        }
        .padding()
        .navigationTitle("Edit Snippet")
        .onAppear { title = snippet.title; content = snippet.content }
        .onChange(of: snippetIndex) { _, _ in
            title = snippet.title; content = snippet.content; isDirty = false
        }
    }
}
