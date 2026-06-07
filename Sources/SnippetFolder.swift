import Foundation

struct SnippetFolder: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var snippets: [Snippet]

    init(id: UUID = UUID(), name: String, snippets: [Snippet] = []) {
        self.id = id
        self.name = name
        self.snippets = snippets
    }
}
