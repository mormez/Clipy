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
        window.collectionBehavior = [.moveToActiveSpace]
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
    @State private var showRenameFolder = false
    @State private var renameFolderName = ""

    private var selectedFolderIndex: Int? {
        manager.folders.firstIndex { $0.id == selectedFolderID }
    }

    var body: some View {
        NavigationSplitView {
            folderColumn
        } content: {
            if let fi = selectedFolderIndex {
                SnippetList(folderIndex: fi, selectedSnippetID: $selectedSnippetID)
            } else {
                ContentUnavailableView("Select a Folder", systemImage: "folder")
            }
        } detail: {
            if let fi = selectedFolderIndex,
               fi < manager.folders.count,
               let si = manager.folders[fi].snippets.firstIndex(where: { $0.id == selectedSnippetID }) {
                SnippetEditor(folderIndex: fi, snippetIndex: si)
            } else {
                ContentUnavailableView("Select a Snippet", systemImage: "text.quote")
            }
        }
        // Remove the default sidebar toggle button from the toolbar
        .toolbar(removing: .sidebarToggle)
        .sheet(isPresented: $showAddFolder) { addFolderSheet }
        .sheet(isPresented: $showRenameFolder) { renameFolderSheet }
    }

    // MARK: - Folder column (list + bottom action bar)

    private var folderColumn: some View {
        List(foldersBinding, editActions: .move, selection: $selectedFolderID) { $folder in
            Label(folder.name, systemImage: "folder")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                // Bottom bar: + and − on the left, ✏️ Rename on the right
                HStack(spacing: 0) {
                    Button(action: { showAddFolder = true }) {
                        Image(systemName: "plus").frame(width: 28, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("New Folder")

                    Button(action: deleteSelectedFolder) {
                        Image(systemName: "minus").frame(width: 28, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedFolderID == nil)
                    .help("Delete Folder")

                    Spacer()

                    Button(action: beginRename) {
                        Image(systemName: "pencil").frame(width: 28, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedFolderID == nil)
                    .help("Rename Folder")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .navigationTitle("Folders")
    }

    private var foldersBinding: Binding<[SnippetFolder]> {
        Binding(
            get: { manager.folders },
            set: { manager.folders = $0; manager.persist() }
        )
    }

    private func beginRename() {
        guard let id = selectedFolderID,
              let folder = manager.folders.first(where: { $0.id == id }) else { return }
        renameFolderName = folder.name
        showRenameFolder = true
    }

    private func deleteSelectedFolder() {
        guard let id = selectedFolderID,
              let idx = manager.folders.firstIndex(where: { $0.id == id }) else { return }
        selectedFolderID = nil
        selectedSnippetID = nil
        manager.removeFolder(at: idx)
    }

    // MARK: - Sheets

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

    private var renameFolderSheet: some View {
        VStack(spacing: 20) {
            Text("Rename Folder").font(.headline)
            TextField("Folder name", text: $renameFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { applyRename() }
            HStack(spacing: 12) {
                Button("Cancel") { showRenameFolder = false; renameFolderName = "" }
                Button("Rename") { applyRename() }
                    .buttonStyle(.borderedProminent)
                    .disabled(renameFolderName.isEmpty)
            }
        }
        .padding(24)
    }

    private func applyRename() {
        guard !renameFolderName.isEmpty,
              let id = selectedFolderID,
              let idx = manager.folders.firstIndex(where: { $0.id == id }) else { return }
        manager.renameFolder(at: idx, name: renameFolderName)
        renameFolderName = ""
        showRenameFolder = false
    }
}

// MARK: - Snippet list column

private struct SnippetList: View {
    let folderIndex: Int
    @ObservedObject private var manager = SnippetManager.shared
    @Binding var selectedSnippetID: UUID?
    @State private var showAddSnippet = false
    @State private var newTitle = ""
    @State private var newContent = ""

    private var folder: SnippetFolder? {
        guard folderIndex < manager.folders.count else { return nil }
        return manager.folders[folderIndex]
    }

    var body: some View {
        if let folder {
            VStack(spacing: 0) {
                // Header bar with + / − clearly above the list
                HStack(spacing: 4) {
                    Text("Snippets")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { showAddSnippet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Snippet")

                    Button(action: deleteSelectedSnippet) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedSnippetID == nil)
                    .help("Delete Snippet")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                List(selection: $selectedSnippetID) {
                    ForEach(folder.snippets) { snippet in
                        Text(snippet.title).tag(snippet.id)
                    }
                    .onMove { manager.moveSnippet(in: folderIndex, from: $0, to: $1) }
                }
            }
            .navigationTitle(folder.name)
            .sheet(isPresented: $showAddSnippet) { addSnippetSheet }
        } else {
            ContentUnavailableView("Folder not found", systemImage: "folder")
        }
    }

    private func deleteSelectedSnippet() {
        guard let id = selectedSnippetID,
              let si = folder?.snippets.firstIndex(where: { $0.id == id }) else { return }
        selectedSnippetID = nil
        manager.removeSnippet(at: si, from: folderIndex)
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

// MARK: - Snippet editor

private struct SnippetEditor: View {
    let folderIndex: Int
    let snippetIndex: Int
    @ObservedObject private var manager = SnippetManager.shared
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var isDirty = false

    private var snippet: Snippet? {
        guard folderIndex < manager.folders.count,
              snippetIndex < manager.folders[folderIndex].snippets.count else { return nil }
        return manager.folders[folderIndex].snippets[snippetIndex]
    }

    var body: some View {
        if let snippet {
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
                        manager.updateSnippet(at: snippetIndex, in: folderIndex,
                                              title: title, content: content)
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
                if let s = self.snippet { title = s.title; content = s.content; isDirty = false }
            }
        } else {
            ContentUnavailableView("Snippet not found", systemImage: "text.quote")
        }
    }
}
