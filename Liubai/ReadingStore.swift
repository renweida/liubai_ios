import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct CollectionFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var articleIDs: [String] = []
}

struct ReadingNote: Codable, Equatable {
    var markdown: String
    var modifiedAt: Date
}

struct ArticleReference: Codable, Equatable {
    let title: String
    let category: String

    init(_ article: Article) {
        title = article.displayTitle
        category = article.category
    }
}

struct ReadingBackup: Codable, Equatable {
    var version = 1
    var likes: Set<String> = []
    var folders: [CollectionFolder] = []
    var notes: [String: ReadingNote] = [:]
    var references: [String: ArticleReference] = [:]

    func validated() throws -> Self {
        guard version == 1 else { throw ReadingStoreError.unsupportedVersion }
        guard Set(folders.map(\.id)).count == folders.count,
              folders.allSatisfy({
                  !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.name.count <= 40
                      && Set($0.articleIDs).count == $0.articleIDs.count
              }),
              likes.allSatisfy({ !$0.isEmpty }),
              notes.allSatisfy({ !$0.key.isEmpty && !$0.value.markdown.isEmpty }),
              folders.flatMap(\.articleIDs).allSatisfy({ !$0.isEmpty }) else {
            throw ReadingStoreError.invalidBackup
        }
        return self
    }

    mutating func merge(_ backup: Self) {
        likes.formUnion(backup.likes)
        notes.merge(backup.notes) { local, imported in
            imported.modifiedAt > local.modifiedAt ? imported : local
        }
        references.merge(backup.references) { local, _ in local }
        for folder in backup.folders {
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                let existing = Set(folders[index].articleIDs)
                folders[index].articleIDs.append(contentsOf: folder.articleIDs.filter { !existing.contains($0) })
            } else {
                folders.append(folder)
            }
        }
    }
}

enum ReadingStoreError: LocalizedError {
    case unsupportedVersion, invalidBackup, backupTooLarge, badFolderName, duplicateFolderName, missingFolder

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "此备份版本暂不支持。"
        case .invalidBackup: "无法读取留白备份，请选择有效的 JSON 备份文件。"
        case .backupTooLarge: "备份超过 20 MB，无法导入。"
        case .badFolderName: "请输入 1 到 40 个字符作为收藏夹名称。"
        case .duplicateFolderName: "已有同名收藏夹，请换个名称。"
        case .missingFolder: "这个收藏夹已删除。"
        }
    }
}

@MainActor
@Observable final class ReadingStore {
    private(set) var data = ReadingBackup()
    private(set) var storageError: String?
    private let directory: URL
    private var readFailed = false

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Liubai", directoryHint: .isDirectory)) {
        self.directory = directory
        let file = directory.appending(path: "library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            data = try JSONDecoder().decode(ReadingBackup.self, from: Data(contentsOf: file)).validated()
        } catch {
            readFailed = true
            storageError = "本机资料暂时无法读取。原始文件已保留，可从备份导入恢复。"
        }
    }

    func isLiked(_ id: String) -> Bool { data.likes.contains(id) }
    func isSaved(_ id: String) -> Bool { data.folders.contains { $0.articleIDs.contains(id) } }

    func toggleLike(_ article: Article) throws {
        try change {
            if !$0.likes.insert(article.id).inserted { $0.likes.remove(article.id) }
            $0.references[article.id] = ArticleReference(article)
        }
    }

    func addFolder(_ name: String, saving article: Article? = nil) throws {
        let name = try folderName(name)
        try change {
            $0.folders.append(CollectionFolder(name: name, articleIDs: article.map { [$0.id] } ?? []))
            if let article { $0.references[article.id] = ArticleReference(article) }
        }
    }

    func renameFolder(_ id: UUID, to name: String) throws {
        let name = try folderName(name, excluding: id)
        try change {
            guard let index = $0.folders.firstIndex(where: { $0.id == id }) else { throw ReadingStoreError.missingFolder }
            $0.folders[index].name = name
        }
    }

    func deleteFolder(_ id: UUID) throws {
        try change { $0.folders.removeAll { $0.id == id } }
    }

    func setMembership(_ article: Article, in id: UUID, included: Bool) throws {
        try change {
            guard let index = $0.folders.firstIndex(where: { $0.id == id }) else { throw ReadingStoreError.missingFolder }
            if included {
                if !$0.folders[index].articleIDs.contains(article.id) {
                    $0.folders[index].articleIDs.append(article.id)
                }
                $0.references[article.id] = ArticleReference(article)
            } else {
                $0.folders[index].articleIDs.removeAll { $0 == article.id }
            }
        }
    }

    func saveNote(_ markdown: String, for id: String, article: Article?) throws {
        guard !markdown.isEmpty else { try deleteNote(id); return }
        guard data.notes[id]?.markdown != markdown else { return }
        try change {
            $0.notes[id] = ReadingNote(markdown: markdown, modifiedAt: .now)
            if let article { $0.references[id] = ArticleReference(article) }
        }
    }

    func deleteNote(_ id: String) throws {
        try change { $0.notes.removeValue(forKey: id) }
    }

    func importBackup(_ backup: ReadingBackup) throws {
        let validated = try backup.validated()
        var updated = data
        updated.merge(validated)
        if readFailed {
            let file = directory.appending(path: "library.json")
            let preserved = directory.appending(path: "unreadable-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: file, to: preserved)
        }
        try persist(updated)
        readFailed = false
        storageError = nil
    }

    private func folderName(_ name: String, excluding id: UUID? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(trimmed.count) else { throw ReadingStoreError.badFolderName }
        guard !data.folders.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame })
        else { throw ReadingStoreError.duplicateFolderName }
        return trimmed
    }

    private func change(_ edit: (inout ReadingBackup) throws -> Void) throws {
        guard !readFailed else { throw ReadingStoreError.invalidBackup }
        var updated = data
        try edit(&updated)
        try persist(updated)
    }

    private func persist(_ updated: ReadingBackup) throws {
        var localDirectory = directory
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        try localDirectory.setResourceValues(resource)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(updated)
        try bytes.write(to: localDirectory.appending(path: "library.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        data = updated
    }
}

struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let backup: ReadingBackup

    init(backup: ReadingBackup) { self.backup = backup }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw ReadingStoreError.invalidBackup }
        backup = try Self.read(bytes)
    }

    static func read(_ bytes: Data) throws -> ReadingBackup {
        guard bytes.count <= 20_000_000 else { throw ReadingStoreError.backupTooLarge }
        guard let decoded = try? JSONDecoder().decode(ReadingBackup.self, from: bytes)
        else { throw ReadingStoreError.invalidBackup }
        return try decoded.validated()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try FileWrapper(regularFileWithContents: encoder.encode(backup))
    }
}
