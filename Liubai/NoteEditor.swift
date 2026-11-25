import Observation
import SwiftUI
import UIKit

@MainActor
@Observable private final class NoteSession {
    var markdown: String
    var style: NoteStyle = []
    var block: NoteBlock = .body
    @ObservationIgnored weak var editor: RichNoteEditor.Coordinator?

    init(markdown: String) { self.markdown = markdown }
}

struct NoteEditorView: View {
    @Environment(ReadingStore.self) private var library
    let articleID: String
    var article: Article?

    var body: some View {
        NoteComposer(articleID: articleID, article: article, initial: library.data.notes[articleID]?.markdown ?? "")
    }
}

private struct NoteComposer: View {
    @Environment(ReadingStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var session: NoteSession
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var error: String?
    let articleID: String
    let article: Article?
    let initial: String

    init(articleID: String, article: Article?, initial: String) {
        self.articleID = articleID
        self.article = article
        self.initial = initial
        _session = State(initialValue: NoteSession(markdown: initial))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 15) {
                Text(article?.displayTitle ?? library.data.references[articleID]?.title ?? "已保存的文章")
                    .font(ReadingPalette.editorial(27, relativeTo: .title2))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 9)

                ZStack(alignment: .topLeading) {
                    RichNoteEditor(session: session)
                    if session.markdown.isEmpty {
                        Text("此刻，你想记下什么？")
                            .font(.body)
                            .foregroundStyle(ReadingPalette.muted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .paperCard(radius: 19)
                formattingBar
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
            .readingWidth()
            .readingBackground()
            .navigationTitle("我的笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { close() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if !initial.isEmpty {
                        Menu {
                            Button("删除笔记", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        } label: {
                            Image(systemName: "ellipsis").accessibilityLabel("笔记操作")
                        }
                    }
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("note.save")
                }
            }
            .confirmationDialog("放弃这次笔记修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .confirmationDialog("删除这篇笔记？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除笔记", role: .destructive) {
                    do { try library.deleteNote(articleID); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
            .messageAlert($error)
        }
        .interactiveDismissDisabled(session.markdown != initial)
    }

    private var formattingBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                Menu {
                    ForEach([NoteBlock.body, .heading, .subheading, .quote], id: \.self) { block in
                        Button {
                            session.editor?.apply(block)
                        } label: {
                            Label(block.label, systemImage: session.block == block ? "checkmark" : block.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .frame(width: 47, height: 44)
                }
                .accessibilityLabel("段落样式")
                .accessibilityIdentifier("note.paragraph")
                Divider().frame(height: 20).padding(.horizontal, 2)
                formatButton("bold", label: "粗体", selected: session.style.contains(.bold), id: "bold") {
                    session.editor?.toggle(.bold)
                }
                formatButton("italic", label: "斜体", selected: session.style.contains(.italic), id: "italic") {
                    session.editor?.toggle(.italic)
                }
                formatButton("underline", label: "下划线", selected: session.style.contains(.underline), id: "underline") {
                    session.editor?.toggle(.underline)
                }
                Divider().frame(height: 20).padding(.horizontal, 2)
                formatButton("list.bullet", label: "项目列表", selected: session.block == .bullet, id: "bullets") {
                    session.editor?.apply(session.block == .bullet ? .body : .bullet)
                }
                formatButton("list.number", label: "编号列表", selected: session.block == .numbered, id: "numbers") {
                    session.editor?.apply(session.block == .numbered ? .body : .numbered)
                }
            }
            .padding(.horizontal, 5)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(ReadingPalette.accent)
        .glassEffect(.regular, in: .capsule)
    }

    private func formatButton(_ symbol: String, label: String, selected: Bool,
                              id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .background(selected ? ReadingPalette.quiet : Color.clear, in: .circle)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("note.format.\(id)")
    }

    private func close() {
        session.editor?.finishComposition()
        if session.markdown == initial { dismiss() }
        else { confirmDiscard = true }
    }

    private func save() {
        session.editor?.finishComposition()
        do {
            try library.saveNote(session.markdown, for: articleID, article: article)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct RichNoteEditor: UIViewRepresentable {
    let session: NoteSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIView(context: Context) -> UITextView {
        let layout = NoteLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let view = UITextView(frame: .zero, textContainer: container)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 14, left: 16, bottom: 18, right: 16)
        view.keyboardDismissMode = .interactive
        view.adjustsFontForContentSizeCategory = true
        view.attributedText = NoteMarkup.decode(session.markdown)
        view.accessibilityLabel = "笔记内容"
        view.accessibilityIdentifier = "note.text"
        context.coordinator.attach(to: view, layout: layout)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        private let session: NoteSession
        private weak var view: UITextView?
        private weak var layout: NoteLayoutManager?
        private var changingFormat = false
        private var nextBlock: NoteBlock?
        private var insertionBlock: NoteBlock = .body
        private var insertionStyle: NoteStyle = []
        private var traitRegistration: (any UITraitChangeRegistration)?

        init(session: NoteSession) { self.session = session }

        func attach(to view: UITextView, layout: NoteLayoutManager) {
            self.view = view
            self.layout = layout
            session.editor = self
            render(view)
            updateSelection(view)
            traitRegistration = view.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
                [weak self] (view: UITextView, _) in
                guard view.markedTextRange == nil else { return }
                self?.render(view)
                self?.updateTypingAttributes(view)
            }
        }

        func finishComposition() {
            guard let view else { return }
            view.unmarkText()
            sync(view)
        }

        func toggle(_ style: NoteStyle) {
            guard let view else { return }
            view.unmarkText()
            let selection = view.selectedRange
            let enabled = !insertionStyle.contains(style)
            if selection.length > 0 {
                let storage = view.textStorage
                var ranges: [(NSRange, NoteStyle)] = []
                storage.enumerateAttribute(.noteStyle, in: selection) { value, range, _ in
                    var changed = NoteStyle(rawValue: value as? Int ?? 0)
                    if enabled { changed.insert(style) } else { changed.remove(style) }
                    ranges.append((range, changed))
                }
                storage.beginEditing()
                for (range, changed) in ranges {
                    storage.addAttribute(.noteStyle, value: changed.rawValue, range: range)
                }
                storage.endEditing()
                render(view)
            }
            if enabled { insertionStyle.insert(style) } else { insertionStyle.remove(style) }
            updateTypingAttributes(view)
            sync(view)
            view.becomeFirstResponder()
        }

        func apply(_ block: NoteBlock) {
            guard let view else { return }
            view.unmarkText()
            let storage = view.textStorage
            let text = storage.string as NSString
            let range = text.paragraphRange(for: view.selectedRange)
            if range.length > 0 {
                storage.addAttribute(.noteBlock, value: block.rawValue, range: range)
            }
            insertionBlock = block
            render(view)
            updateTypingAttributes(view)
            sync(view)
            view.becomeFirstResponder()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            nextBlock = nil
            guard text == "\n", textView.markedTextRange == nil else { return true }
            if insertionBlock.repeatsOnReturn {
                let string = textView.textStorage.string as NSString
                let line = string.substring(with: string.paragraphRange(for: range))
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    apply(.body)
                    return false
                }
            } else {
                nextBlock = .body
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil, !changingFormat else { return }
            if let nextBlock {
                let range = (textView.textStorage.string as NSString).paragraphRange(for: textView.selectedRange)
                if range.length > 0 { textView.textStorage.addAttribute(.noteBlock, value: nextBlock.rawValue, range: range) }
                insertionBlock = nextBlock
                insertionStyle = []
                self.nextBlock = nil
            }
            render(textView)
            updateTypingAttributes(textView)
            sync(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil, !changingFormat, nextBlock == nil else { return }
            updateSelection(textView)
        }

        private func updateSelection(_ view: UITextView) {
            let storage = view.textStorage
            let selection = view.selectedRange
            if selection.location < storage.length ||
                (selection.location == storage.length && storage.length > 0 && !storage.string.hasSuffix("\n")) {
                let string = storage.string as NSString
                let paragraph = string.paragraphRange(for: NSRange(location: selection.location, length: 0))
                insertionBlock = storage.noteBlock(at: paragraph.location)
                let styleLocation = selection.length == 0 && selection.location > paragraph.location
                    ? selection.location - 1 : selection.location
                insertionStyle = storage.noteStyle(at: styleLocation)
            }
            updateTypingAttributes(view, report: view.delegate != nil)
        }

        private func updateTypingAttributes(_ view: UITextView, report: Bool = true) {
            let storage = view.textStorage
            let number: Int
            if insertionBlock == .numbered {
                let paragraph = (storage.string as NSString).paragraphRange(for: view.selectedRange)
                if paragraph.location < storage.length {
                    number = storage.attribute(.noteNumber, at: paragraph.location, effectiveRange: nil) as? Int ?? 1
                } else if storage.length > 0 {
                    let previous = storage.attribute(.noteNumber, at: storage.length - 1, effectiveRange: nil) as? Int ?? 0
                    number = previous + 1
                } else { number = 1 }
            } else { number = 0 }
            view.typingAttributes = NoteTypography.attributes(for: insertionBlock, style: insertionStyle,
                                                              number: number, traits: view.traitCollection)
            let lastParagraphIsEmpty = view.selectedRange.location == storage.length
                && (storage.length == 0 || storage.string.hasSuffix("\n"))
            layout?.emptyMarker = lastParagraphIsEmpty ? NoteTypography.marker(for: insertionBlock, number: number) : nil
            layout?.markerFont = NoteTypography.markerFont(view.traitCollection)
            view.setNeedsDisplay()
            if report {
                if session.block != insertionBlock { session.block = insertionBlock }
                if session.style != insertionStyle { session.style = insertionStyle }
            }
        }

        private func render(_ view: UITextView) {
            changingFormat = true
            defer { changingFormat = false }
            let storage = view.textStorage
            let text = storage.string as NSString
            let selection = view.selectedRange
            var numbered = 0
            storage.beginEditing()
            NoteMarkup.enumerateParagraphs(in: text) { paragraph, _ in
                let block = storage.noteBlock(at: paragraph.location)
                numbered = block == .numbered ? numbered + 1 : 0
                var styles: [(NSRange, NoteStyle)] = []
                storage.enumerateAttribute(.noteStyle, in: paragraph) { raw, range, _ in
                    styles.append((range, NoteStyle(rawValue: raw as? Int ?? 0)))
                }
                for (range, style) in styles {
                    storage.setAttributes(NoteTypography.attributes(for: block, style: style, number: numbered,
                                                                    traits: view.traitCollection), range: range)
                }
            }
            storage.endEditing()
            if view.selectedRange != selection { view.selectedRange = selection }
        }

        private func sync(_ view: UITextView) {
            let markdown = NoteMarkup.encode(view.textStorage)
            if markdown != session.markdown { session.markdown = markdown }
        }
    }
}

private enum NoteTypography {
    static func marker(for block: NoteBlock, number: Int) -> String? {
        switch block {
        case .bullet: "•"
        case .numbered: "\(max(1, number))."
        case .quote: "│"
        default: nil
        }
    }

    static func markerFont(_ traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 15, weight: .medium), compatibleWith: traits
        )
    }

    static func attributes(for block: NoteBlock, style: NoteStyle, number: Int, traits: UITraitCollection) -> [NSAttributedString.Key: Any] {
        let base: UIFont
        let metric: UIFont.TextStyle
        switch block {
        case .heading:
            base = .systemFont(ofSize: 26, weight: style.contains(.bold) ? .heavy : .semibold)
            metric = .title1
        case .subheading:
            base = .systemFont(ofSize: 21, weight: style.contains(.bold) ? .heavy : .semibold)
            metric = .title2
        default:
            base = .systemFont(ofSize: 17)
            metric = .body
        }
        var symbols = base.fontDescriptor.symbolicTraits
        if style.contains(.bold), block != .heading, block != .subheading { symbols.insert(.traitBold) }
        if style.contains(.italic) { symbols.insert(.traitItalic) }
        let font = base.fontDescriptor.withSymbolicTraits(symbols).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 8
        paragraph.paragraphSpacingBefore = block == .heading || block == .subheading ? 5 : 0
        if let marker = marker(for: block, number: number) {
            let width = (marker as NSString).size(withAttributes: [.font: markerFont(traits)]).width
            paragraph.firstLineHeadIndent = max(22, width + 10)
            paragraph.headIndent = paragraph.firstLineHeadIndent
        }
        return [
            .font: UIFontMetrics(forTextStyle: metric).scaledFont(for: font, compatibleWith: traits),
            .foregroundColor: UIColor(ReadingPalette.ink),
            .paragraphStyle: paragraph,
            .underlineStyle: style.contains(.underline) ? NSUnderlineStyle.single.rawValue : 0,
            .noteStyle: style.rawValue,
            .noteBlock: block.rawValue,
            .noteNumber: number
        ]
    }
}

private final class NoteLayoutManager: NSLayoutManager {
    var emptyMarker: String?
    var markerFont = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium)

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: markerFont, .foregroundColor: UIColor(ReadingPalette.accent)]
        NoteMarkup.enumerateParagraphs(in: string) { range, _ in
            let firstGlyph = glyphIndexForCharacter(at: range.location)
            guard NSLocationInRange(firstGlyph, glyphsToShow) else { return }
            let number = storage.attribute(.noteNumber, at: range.location, effectiveRange: nil) as? Int ?? 0
            guard let marker = NoteTypography.marker(for: storage.noteBlock(at: range.location), number: number) else { return }
            let fragment = lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            let baseline = location(forGlyphAt: firstGlyph).y
            (marker as NSString).draw(at: CGPoint(x: origin.x, y: origin.y + fragment.minY + baseline - markerFont.ascender),
                                      withAttributes: attributes)
        }
        if let emptyMarker, extraLineFragmentTextContainer != nil {
            (emptyMarker as NSString).draw(at: CGPoint(x: origin.x, y: origin.y + extraLineFragmentRect.minY + 2),
                                           withAttributes: attributes)
        }
    }
}
