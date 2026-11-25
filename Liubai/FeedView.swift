import SwiftUI

struct FeedView: View {
    @Environment(ArticleFeed.self) private var feed
    @Environment(ReadingStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var appearance: Appearance
    @State private var activeID: String?
    @State private var openedArticle: Article?
    @State private var collectingArticle: Article?
    @State private var error: String?

    private var index: Int {
        feed.articles.firstIndex(where: { $0.id == activeID }) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(feed.articles.enumerated()), id: \.element.id) { index, article in
                            preview(article, index: index, height: geometry.size.height)
                                .frame(height: geometry.size.height)
                                .id(article.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $activeID)
                .accessibilityIdentifier("reading.feed")
                .accessibilityScrollAction { direction in
                    if direction == .top { move(by: 1) }
                    if direction == .bottom { move(by: -1) }
                }
            }
            pager
        }
        .readingWidth()
        .readingBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(item: $openedArticle) { ArticleView(article: $0) }
        .sheet(item: $collectingArticle) { CollectionSheet(article: $0) }
        .task { if let storageError = library.storageError { error = storageError } }
        .messageAlert($error)
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandMark()
            Text("留白")
                .font(ReadingPalette.editorial(32, relativeTo: .title2))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Picker("外观", selection: $appearance) {
                    ForEach(Appearance.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
            } label: {
                Image(systemName: appearance.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ReadingPalette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel("切换外观")
            .accessibilityIdentifier("reading.appearance")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var pager: some View {
        HStack {
            Spacer()
            Button {
                move(by: index == feed.articles.count - 1 ? -index : 1)
            } label: {
                Label(index == feed.articles.count - 1 ? "回到第一篇" : "上滑切换",
                      systemImage: index == feed.articles.count - 1 ? "arrow.counterclockwise" : "chevron.up")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReadingPalette.muted)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reading.next")
        }
        .padding(.horizontal, 24)
    }

    private func move(by amount: Int) {
        let target = index + amount
        guard feed.articles.indices.contains(target) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            activeID = feed.articles[target].id
        }
    }

    private func preview(_ article: Article, index: Int, height: CGFloat) -> some View {
        let compact = height < 535
        let coverHeight = max(78, min(280, height * (compact ? 0.38 : 0.44)))

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                openedArticle = article
            } label: {
                ArticleCover(theme: article.theme, variant: index, height: coverHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("阅读\(article.displayTitle)")
            .accessibilityIdentifier("reading.cover.\(article.id)")
            .padding(.bottom, compact ? 15 : 24)

            ArticleMeta(article: article, showsSource: false)
                .padding(.bottom, compact ? 8 : 13)
                .layoutPriority(1)

            Button {
                openedArticle = article
            } label: {
                Text(compact || article.subtitle.isEmpty ? article.displayTitle : "\(article.title)\n\(article.subtitle)")
                    .font(ReadingPalette.editorial(compact ? 35 : 48, relativeTo: .largeTitle))
                    .tracking(-1.4)
                    .lineSpacing(-2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(ReadingPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .layoutPriority(2)
            .padding(.bottom, compact ? 8 : 12)

            Text(article.excerpt)
                .font(.subheadline)
                .foregroundStyle(ReadingPalette.muted)
                .lineSpacing(4)
                .lineLimit(2)
                .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                Button {
                    openedArticle = article
                } label: {
                    HStack(spacing: 12) {
                        Text("阅读全文").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 47)
                    .foregroundStyle(ReadingPalette.actionInk)
                    .background(ReadingPalette.actionFill, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reading.open")
                Spacer(minLength: 0)
                ArticleActions(article: article, collection: { collectingArticle = article }, onError: { error = $0 })
            }
            .layoutPriority(3)
        }
        .padding(.horizontal, 24)
        .padding(.top, 5)
        .padding(.bottom, 5)
    }
}

struct ArticleMeta: View {
    let article: Article
    var showsSource = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                category
                Text("·").accessibilityHidden(true)
                Text("\(article.minutes) 分钟阅读")
                if showsSource {
                    Text("·").accessibilityHidden(true)
                    Text(article.source)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                category
                Text("\(article.minutes) 分钟阅读")
                if showsSource { Text(article.source) }
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(ReadingPalette.muted)
        .accessibilityElement(children: .combine)
    }

    private var category: some View {
        HStack(spacing: 6) {
            Circle().fill(ReadingPalette.accent).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(article.category).foregroundStyle(ReadingPalette.accent)
        }
    }
}

struct ArticleActions: View {
    @Environment(ReadingStore.self) private var library
    let article: Article
    var notes: (() -> Void)?
    let collection: () -> Void
    let onError: (String) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                GlassIcon(symbol: library.isLiked(article.id) ? "heart.fill" : "heart",
                          label: library.isLiked(article.id) ? "取消喜欢" : "喜欢",
                          color: library.isLiked(article.id) ? ReadingPalette.heart : ReadingPalette.ink) {
                    do { try library.toggleLike(article) }
                    catch { onError(error.localizedDescription) }
                }
                .accessibilityIdentifier("article.like")
                .sensoryFeedback(.selection, trigger: library.isLiked(article.id))
                GlassIcon(symbol: library.isSaved(article.id) ? "bookmark.fill" : "bookmark",
                          label: "收藏到收藏夹",
                          color: library.isSaved(article.id) ? ReadingPalette.accent : ReadingPalette.ink,
                          action: collection)
                .accessibilityIdentifier("article.collect")
                .accessibilityValue(library.isSaved(article.id) ? "已收藏" : "")
                if let notes {
                    GlassIcon(symbol: library.data.notes[article.id] == nil ? "square.and.pencil" : "note.text",
                              label: "我的笔记", action: notes)
                    .accessibilityIdentifier("article.note")
                }
            }
        }
    }
}

struct ArticleCover: View {
    let theme: String
    let variant: Int
    let height: CGFloat

    private var colors: (Color, Color, Color) {
        switch variant % 4 {
        case 1: (Color(red: 0.21, green: 0.19, blue: 0.29), Color(red: 0.38, green: 0.31, blue: 0.43), Color(red: 0.87, green: 0.77, blue: 0.88))
        case 2: (Color(red: 0.30, green: 0.18, blue: 0.16), Color(red: 0.46, green: 0.30, blue: 0.24), Color(red: 0.94, green: 0.77, blue: 0.66))
        case 3: (Color(red: 0.15, green: 0.24, blue: 0.32), Color(red: 0.24, green: 0.37, blue: 0.45), Color(red: 0.74, green: 0.86, blue: 0.91))
        default: (Color(red: 0.10, green: 0.21, blue: 0.16), Color(red: 0.24, green: 0.36, blue: 0.26), Color(red: 0.81, green: 0.87, blue: 0.68))
        }
    }

    var body: some View {
        let palette = colors
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [palette.0, palette.1], startPoint: .bottomLeading, endPoint: .topTrailing)
            Canvas { context, size in
                let unit = min(size.width, size.height * 1.62)
                let center = CGPoint(x: size.width * 0.71, y: size.height * 0.46)
                let angle = [-36.0, 25, -13, 43][variant % 4] * .pi / 180
                var transform = CGAffineTransform(rotationAngle: angle)
                transform.tx = center.x
                transform.ty = center.y

                for index in 0..<23 {
                    let fraction = CGFloat(index) / 22
                    let radius = unit * (0.09 + fraction * 0.30)
                    let yRadius = radius * (0.47 + fraction * 0.17)
                    let xOffset = unit * (fraction - 0.5) * 0.23
                    let orbit = Path(ellipseIn: CGRect(x: xOffset - radius, y: -yRadius,
                                                     width: radius * 2, height: yRadius * 2))
                    context.stroke(orbit.applying(transform),
                                   with: .color(palette.2.opacity(index.isMultiple(of: 7) ? 0.82 : 0.43)),
                                   lineWidth: index.isMultiple(of: 7) ? 0.85 : 0.52)
                }

                var axis = Path()
                axis.move(to: CGPoint(x: center.x - unit * 0.32, y: center.y))
                axis.addLine(to: CGPoint(x: center.x + unit * 0.32, y: center.y))
                axis.move(to: CGPoint(x: center.x, y: center.y - unit * 0.27))
                axis.addLine(to: CGPoint(x: center.x, y: center.y + unit * 0.27))
                context.stroke(axis, with: .color(palette.2.opacity(0.34)),
                               style: StrokeStyle(lineWidth: 0.55, dash: [2, 4]))

                let mote = CGPoint(x: size.width * 0.88, y: size.height * 0.19)
                let star = Path { path in
                    path.move(to: CGPoint(x: mote.x, y: mote.y - 6))
                    path.addQuadCurve(to: CGPoint(x: mote.x + 6, y: mote.y), control: mote)
                    path.addQuadCurve(to: CGPoint(x: mote.x, y: mote.y + 6), control: mote)
                    path.addQuadCurve(to: CGPoint(x: mote.x - 6, y: mote.y), control: mote)
                    path.addQuadCurve(to: CGPoint(x: mote.x, y: mote.y - 6), control: mote)
                }
                context.fill(star, with: .color(palette.2))

                var speckles = Path()
                for index in 0..<410 {
                    let x = CGFloat((index * 107 + 19) % 509) / 509 * size.width
                    let y = CGFloat((index * index * 41 + index * 11) % 499) / 499 * size.height
                    speckles.addEllipse(in: CGRect(x: x, y: y, width: 0.75, height: 0.75))
                }
                context.fill(speckles, with: .color(palette.2.opacity(0.19)))
            }
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(palette.2.opacity(0.8)).frame(width: 21, height: 1)
                Text(theme)
                    .font(ReadingPalette.editorial(height < 150 ? 23 : 31))
                    .tracking(3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(palette.2)
            .padding(height < 150 ? 16 : 22)
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityHidden(true)
    }
}
