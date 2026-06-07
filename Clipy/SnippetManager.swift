import Foundation

final class SnippetManager: ObservableObject {
    static let shared = SnippetManager()

    @Published var folders: [SnippetFolder] = []
    private let storageKey = "com.modernclipboard.snippets"

    private init() {
        load()
        if folders.isEmpty { seedSampleData() }
    }

    // MARK: - Folder operations

    func addFolder(name: String) {
        folders.append(SnippetFolder(name: name))
        persist()
    }

    func renameFolder(at index: Int, name: String) {
        guard index < folders.count else { return }
        folders[index].name = name
        persist()
    }

    func removeFolder(at index: Int) {
        guard index < folders.count else { return }
        folders.remove(at: index)
        persist()
    }

    func moveFolder(from source: IndexSet, to destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Snippet operations

    func addSnippet(_ snippet: Snippet, to folderIndex: Int) {
        guard folderIndex < folders.count else { return }
        folders[folderIndex].snippets.append(snippet)
        persist()
    }

    func updateSnippet(at snippetIndex: Int, in folderIndex: Int, title: String, content: String) {
        guard folderIndex < folders.count, snippetIndex < folders[folderIndex].snippets.count else { return }
        objectWillChange.send()
        folders[folderIndex].snippets[snippetIndex].title = title
        folders[folderIndex].snippets[snippetIndex].content = content
        persist()
    }

    func removeSnippet(at snippetIndex: Int, from folderIndex: Int) {
        guard folderIndex < folders.count, snippetIndex < folders[folderIndex].snippets.count else { return }
        folders[folderIndex].snippets.remove(at: snippetIndex)
        persist()
    }

    func moveSnippet(in folderIndex: Int, from source: IndexSet, to destination: Int) {
        guard folderIndex < folders.count else { return }
        folders[folderIndex].snippets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Persistence

    func persist() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .snippetsChanged, object: nil)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([SnippetFolder].self, from: data) else { return }
        folders = loaded
    }

    private func seedSampleData() {
        folders = [SnippetFolder(name: "My Snippets")]
        persist()
    }
}
