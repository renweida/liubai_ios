import SwiftUI

struct LibraryView: View {
    private enum Shelf: String, CaseIterable {
        case folders = "收藏夹", likes = "喜欢", notes = "笔记"
    }

    @Environment(ReadingStore.self) private var library
    @Environment(ArticleFeed.self) private var feed
    @State private var shelf = Shelf.folders
    @State private var folderName = ""
    @State private var showingNewFolder = false
    @State private var noteID: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("书架")
                        .font(ReadingPalette.editorial(44, relativeTo: .largeTitle))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if shelf == .folders {
                        GlassIcon(symbol: "plus", label: "新建收藏夹") {
                            folderName = ""
                            showingNewFolder = true
                        }
                    }
                }

                Picker("书架分类", selection: $shelf) {
                    ForEach(Shelf.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch shelf {
                case .folders: folders
                case .likes: likes
                case .notes: notes
                }
            }
            .padding(24)
            .readingWidth()
        }
        .readingBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .alert("新建收藏夹", isPresented: $showingNewFolder) {
            TextField("收藏夹名称", text: $folderName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                do { try library.addFolder(folderName) }
                catch { self.error = error.localizedDescription }
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(isPresented: Binding(get: { noteID != nil }, set: { if !$0 { noteID = nil } })) {
            if let noteID { NoteEditorView(articleID: noteID, article: feed.article(noteID)) }
        }
        .messageAlert($error)
    }

    @ViewBuilder
    private var folders: some View {
        if library.data.folders.isEmpty {
            ShelfEmpty(icon: "folder", title: "还没有收藏夹", description: "把想重读的文章放到同一个收藏夹。")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(library.data.folders) { folder in
                    NavigationLink {
                        FolderView(id: folder.id)
                    } label: {
                        ShelfRow(icon: "folder", title: folder.name, detail: "\(folder.articleIDs.count) 篇文章")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var likes: some View {
        if library.data.likes.isEmpty {
            ShelfEmpty(icon: "heart", title: "还没有喜欢的文章", description: "点亮文章旁的红心，就能在这里找到它。")
        } else {
            let ids = feed.articles.map(\.id).filter(library.data.likes.contains)
            let remaining = library.data.likes.subtracting(ids).sorted()
            LazyVStack(spacing: 10) {
                ForEach(ids + remaining, id: \.self) { id in
                    ShelfArticleRow(id: id, icon: "heart")
                }
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if library.data.notes.isEmpty {
            ShelfEmpty(icon: "note.text", title: "还没有笔记", description: "读到想停一停的地方，写下当时的想法。")
        } else {
            let ordered = library.data.notes.sorted { lhs, rhs in
                lhs.value.modifiedAt == rhs.value.modifiedAt
                    ? lhs.key < rhs.key : lhs.value.modifiedAt > rhs.value.modifiedAt
            }
            LazyVStack(spacing: 10) {
                ForEach(ordered, id: \.key) { item in
                    Button {
                        noteID = item.key
                    } label: {
                        ShelfRow(icon: "note.text",
                                 title: feed.article(item.key)?.displayTitle ?? library.data.references[item.key]?.title ?? "已保存的文章",
                                 detail: notePreview(item.value.markdown),
                                 trailing: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func notePreview(_ markdown: String) -> String {
        NoteMarkup.decode(markdown).string
            .split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

private struct FolderView: View {
    @Environment(ReadingStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var renaming = false
    @State private var deleting = false
    @State private var name = ""
    @State private var error: String?

    private var folder: CollectionFolder? { library.data.folders.first { $0.id == id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let folder {
                    if folder.articleIDs.isEmpty {
                        ShelfEmpty(icon: "bookmark", title: "收藏夹是空的", description: "阅读时点击收藏按钮，即可把文章放进来。")
                    } else {
                        ForEach(folder.articleIDs, id: \.self) { id in
                            ShelfArticleRow(id: id, icon: "bookmark")
                        }
                    }
                }
            }
            .padding(24)
            .readingWidth()
        }
        .readingBackground()
        .navigationTitle(folder?.name ?? "收藏夹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("重命名", systemImage: "pencil") {
                        name = folder?.name ?? ""
                        renaming = true
                    }
                    Button("删除收藏夹", systemImage: "trash", role: .destructive) { deleting = true }
                } label: {
                    Image(systemName: "ellipsis").accessibilityLabel("收藏夹操作")
                }
            }
        }
        .alert("重命名收藏夹", isPresented: $renaming) {
            TextField("收藏夹名称", text: $name)
            Button("取消", role: .cancel) {}
            Button("保存") {
                do { try library.renameFolder(id, to: name) }
                catch { self.error = error.localizedDescription }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("删除这个收藏夹？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除收藏夹", role: .destructive) {
                do { try library.deleteFolder(id); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
        .messageAlert($error)
    }
}

private struct ShelfArticleRow: View {
    @Environment(ArticleFeed.self) private var feed
    @Environment(ReadingStore.self) private var library
    let id: String
    let icon: String

    var body: some View {
        let reference = library.data.references[id]
        NavigationLink {
            ShelfArticleDetail(id: id)
        } label: {
            if let article = feed.article(id) {
                ShelfRow(icon: icon, title: article.displayTitle,
                         detail: "\(article.category) · \(article.minutes) 分钟阅读")
            } else {
                ShelfRow(icon: icon, title: reference?.title ?? "已保存的文章",
                         detail: reference?.category ?? "查看正文")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.article.\(id)")
    }
}

private struct ShelfArticleDetail: View {
    @Environment(ArticleFeed.self) private var feed
    let id: String
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if let article = feed.article(id) {
                ArticleView(article: article)
            } else if let error {
                ContentUnavailableView {
                    Label("正文暂不可用", systemImage: "book.closed")
                } description: {
                    Text(error)
                } actions: {
                    Button("重新加载") { Task { await load() } }
                        .buttonStyle(.glass)
                }
            } else {
                ProgressView("正在加载文章")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .readingBackground()
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            try await feed.loadArticle(id)
        } catch {
            if !Task.isCancelled { self.error = ArticleFeed.message(for: error) }
        }
    }
}

private struct ShelfRow: View {
    let icon: String
    let title: String
    let detail: String
    var trailing: String? = "chevron.right"

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ReadingPalette.accent)
                .frame(width: 43, height: 43)
                .background(ReadingPalette.quiet, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(ReadingPalette.ink)
                Text(detail).font(.footnote).lineLimit(2).foregroundStyle(ReadingPalette.muted)
            }
            Spacer(minLength: 0)
            if let trailing {
                Image(systemName: trailing)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ReadingPalette.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .paperCard(radius: 17)
        .accessibilityElement(children: .combine)
    }
}

private struct ShelfEmpty: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(ReadingPalette.accent)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(title).font(ReadingPalette.editorial(25, relativeTo: .title2))
            Text(description).font(.subheadline).foregroundStyle(ReadingPalette.muted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 36)
        .paperCard()
    }
}
