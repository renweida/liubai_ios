import SwiftUI

struct ArticleView: View {
    @Environment(ReadingStore.self) private var library
    let article: Article
    @State private var showingCollections = false
    @State private var showingNote = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArticleMeta(article: article)
                    .padding(.bottom, 15)
                Text(article.displayTitle)
                    .font(ReadingPalette.editorial(43, relativeTo: .largeTitle))
                    .tracking(-1.25)
                    .lineSpacing(2)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 13)

                Text(article.excerpt)
                    .font(.body)
                    .foregroundStyle(ReadingPalette.muted)
                    .lineSpacing(5)
                    .padding(.bottom, 23)

                SectionRule().padding(.bottom, 24)
                MarkdownArticle(markdown: article.markdown)
                    .environment(\.openURL, OpenURLAction { url in
                        url.scheme?.lowercased() == "https" ? .systemAction : .discarded
                    })

                Button {
                    showingNote = true
                } label: {
                    Label(library.data.notes[article.id] == nil ? "写下我的想法" : "继续写我的笔记",
                          systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 16)
                        .foregroundStyle(ReadingPalette.accent)
                        .paperCard(radius: 17)
                }
                .buttonStyle(.plain)
                .padding(.top, 30)
            }
            .padding(.horizontal, 25)
            .padding(.top, 15)
            .padding(.bottom, 30)
            .readingWidth()
        }
        .accessibilityIdentifier("article.content")
        .safeAreaInset(edge: .bottom, spacing: 6) {
            ArticleActions(article: article, notes: { showingNote = true },
                           collection: { showingCollections = true }, onError: { error = $0 })
                .frame(maxWidth: 610, alignment: .trailing)
                .padding(.horizontal, 25)
                .padding(.top, 9)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity)
                .background {
                    LinearGradient(colors: [ReadingPalette.paper.opacity(0), ReadingPalette.paper],
                                   startPoint: .top, endPoint: .center)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
        }
        .readingBackground()
        .navigationTitle("阅读")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .sheet(isPresented: $showingCollections) { CollectionSheet(article: article) }
        .sheet(isPresented: $showingNote) { NoteEditorView(articleID: article.id, article: article) }
        .messageAlert($error)
    }
}

private struct MarkdownBlock: Identifiable {
    let id: Int
    let intents: [PresentationIntent.IntentType]
    var text: AttributedString

    static func parse(_ markdown: String) -> [Self] {
        let parsed = (try? AttributedString(markdown: markdown, options: .init(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible
        ))) ?? AttributedString(markdown)
        var blocks: [Self] = []
        for run in parsed.runs {
            let intents = run.presentationIntent?.components ?? []
            let id = intents.first?.identity ?? 0
            var text = AttributedString(parsed[run.range])
            text.presentationIntent = nil
            if blocks.last?.id == id {
                blocks[blocks.count - 1].text.append(text)
            } else {
                blocks.append(Self(id: id, intents: intents, text: text))
            }
        }
        return blocks
    }

    var ordinal: Int? {
        for intent in intents {
            if case .listItem(let ordinal) = intent.kind { return ordinal }
        }
        return nil
    }

    var ordered: Bool {
        for intent in intents {
            switch intent.kind {
            case .orderedList: return true
            case .unorderedList: return false
            default: continue
            }
        }
        return false
    }

    var indent: Int {
        intents.filter {
            if case .listItem = $0.kind { return true }
            return false
        }.count
    }

    var quoted: Bool { intents.contains { $0.kind == .blockQuote } }

    var tableID: Int? {
        intents.first {
            if case .table = $0.kind { return true }
            return false
        }?.identity
    }

    var tableRow: Int? {
        intents.first {
            switch $0.kind {
            case .tableHeaderRow, .tableRow: true
            default: false
            }
        }?.identity
    }

    var tableHeader: Bool { intents.contains { $0.kind == .tableHeaderRow } }
}

private struct MarkdownSection: Identifiable {
    let id: Int
    var blocks: [MarkdownBlock]
}

struct MarkdownArticle: View {
    private let sections: [MarkdownSection]

    init(markdown: String) {
        var sections: [MarkdownSection] = []
        for block in MarkdownBlock.parse(markdown) {
            if let tableID = block.tableID, sections.last?.id == tableID {
                sections[sections.count - 1].blocks.append(block)
            } else {
                sections.append(MarkdownSection(id: block.tableID ?? block.id, blocks: [block]))
            }
        }
        self.sections = sections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            ForEach(sections) { section in
                if section.blocks.first?.tableID != nil {
                    table(section.blocks)
                } else if let block = section.blocks.first {
                    render(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body)
        .lineSpacing(8)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func render(_ block: MarkdownBlock) -> some View {
        switch block.intents.first?.kind {
        case .header(let level):
            Text(block.text)
                .font(ReadingPalette.editorial(level <= 2 ? 27 : 22, relativeTo: .title2))
                .lineSpacing(4)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        case .thematicBreak:
            SectionRule().padding(.vertical, 6)
        case .codeBlock:
            Text(block.text)
                .font(.system(.footnote, design: .monospaced))
                .lineSpacing(4)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ReadingPalette.quiet, in: .rect(cornerRadius: 12))
        default:
            if let ordinal = block.ordinal {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(block.ordered ? "\(ordinal)." : "•")
                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                        .foregroundStyle(ReadingPalette.accent)
                        .accessibilityHidden(!block.ordered)
                    Text(block.text)
                }
                .padding(.leading, CGFloat(max(0, block.indent - 1)) * 14)
                .accessibilityElement(children: .combine)
            } else if block.quoted {
                HStack(spacing: 13) {
                    Capsule().fill(ReadingPalette.accent.opacity(0.55)).frame(width: 3)
                        .accessibilityHidden(true)
                    Text(block.text)
                        .font(ReadingPalette.editorial(21, relativeTo: .body))
                        .foregroundStyle(ReadingPalette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(15)
                .background(ReadingPalette.quiet, in: .rect(cornerRadius: 13))
            } else {
                Text(block.text)
            }
        }
    }

    private func table(_ cells: [MarkdownBlock]) -> some View {
        let grouped = Dictionary(grouping: cells) { $0.tableRow ?? $0.id }
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                ForEach(grouped.keys.sorted(), id: \.self) { row in
                    GridRow {
                        ForEach(grouped[row] ?? []) { cell in
                            Text(cell.text)
                                .font(cell.tableHeader ? .footnote.bold() : .footnote)
                                .padding(.vertical, 9)
                        }
                    }
                    Divider()
                }
            }
            .padding(.horizontal, 13)
        }
        .background(ReadingPalette.quiet, in: .rect(cornerRadius: 12))
    }
}

struct CollectionSheet: View {
    @Environment(ReadingStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let article: Article
    @State private var editor = false
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(article.displayTitle)
                        .font(ReadingPalette.editorial(26, relativeTo: .title2))
                        .padding(.bottom, 5)
                    if library.data.folders.isEmpty {
                        Text("创建一个收藏夹，把喜欢的文章收在一起。")
                            .font(.subheadline)
                            .foregroundStyle(ReadingPalette.muted)
                    }
                    ForEach(library.data.folders) { folder in
                        let selected = folder.articleIDs.contains(article.id)
                        Button {
                            do { try library.setMembership(article, in: folder.id, included: !selected) }
                            catch { self.error = error.localizedDescription }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundStyle(ReadingPalette.accent)
                                Text(folder.name).foregroundStyle(ReadingPalette.ink)
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? ReadingPalette.accent : ReadingPalette.muted)
                            }
                            .padding(15)
                            .frame(minHeight: 52)
                            .paperCard(radius: 15)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    Button {
                        name = ""
                        editor = true
                    } label: {
                        Label("新建收藏夹", systemImage: "folder.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 3)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ReadingPalette.accent)
                    .accessibilityIdentifier("collection.create")
                }
                .padding(24)
                .readingWidth()
            }
            .readingBackground()
            .navigationTitle("收藏到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("collection.done")
                }
            }
            .alert("新建收藏夹", isPresented: $editor) {
                TextField("收藏夹名称", text: $name).accessibilityIdentifier("folder.name")
                Button("取消", role: .cancel) {}
                Button("创建并收藏") {
                    do { try library.addFolder(name, saving: article) }
                    catch { self.error = error.localizedDescription }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .messageAlert($error)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
