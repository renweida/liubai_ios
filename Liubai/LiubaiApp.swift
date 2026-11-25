import SwiftUI

@main
struct LiubaiApp: App {
    @State private var library: ReadingStore
    @State private var feed = ArticleFeed()
    @State private var tips = TipStore()
    @AppStorage("appearance") private var appearance = Appearance.system

    init() {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["LIUBAI_UI_TEST_LIBRARY"], let id = UUID(uuidString: value) {
            _library = State(initialValue: ReadingStore(directory: URL.temporaryDirectory.appending(path: id.uuidString)))
            return
        }
        #endif
        _library = State(initialValue: ReadingStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView(appearance: $appearance)
                .environment(library)
                .environment(feed)
                .environment(tips)
                .preferredColorScheme(appearance.colorScheme)
                .tint(ReadingPalette.accent)
                .task { await feed.refresh() }
                .task { await tips.observeTransactions() }
        }
    }
}

struct RootView: View {
    @Binding var appearance: Appearance

    var body: some View {
        TabView {
            Tab("阅读", systemImage: "book.pages") {
                NavigationStack { FeedView(appearance: $appearance) }
            }
            Tab("书架", systemImage: "books.vertical") {
                NavigationStack { LibraryView() }
            }
            Tab("设置", systemImage: "gearshape") {
                NavigationStack { SettingsView(appearance: $appearance) }
            }
        }
        .tabViewStyle(.tabBarOnly)
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

enum ReadingPalette {
    static let paper = adaptive(0xF8F6EF, 0x181B18)
    static let surface = adaptive(0xFFFCF6, 0x20251F)
    static let ink = adaptive(0x222B23, 0xEEECE2)
    static let muted = adaptive(0x586357, 0xB4BEB0)
    static let accent = adaptive(0x345942, 0xC0D2A8)
    static let actionFill = adaptive(0x2D4937, 0xCBDAB9)
    static let actionInk = adaptive(0xFFFDF3, 0x233128)
    static let quiet = adaptive(0xEAEDE1, 0x30392D)
    static let rule = adaptive(0xDCDDD0, 0x3B4438)
    static let heart = adaptive(0xB3444D, 0xF08A91)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }

    static func editorial(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("SourceHanSerifCN-Medium", size: size, relativeTo: style)
    }
}

struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(ReadingPalette.actionFill)
            Canvas { context, size in
                let x = size.width / 2
                let y = size.height / 2
                var lines = Path()
                for radius in [CGFloat(10.5), 7, 3.5] {
                    lines.addArc(center: CGPoint(x: x, y: y), radius: radius,
                                 startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    lines.move(to: CGPoint(x: x + radius, y: y))
                }
                lines.move(to: CGPoint(x: x - 11, y: y + 4))
                lines.addLine(to: CGPoint(x: x + 11, y: y + 4))
                context.stroke(lines, with: .color(ReadingPalette.actionInk), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }
}

struct GlassIcon: View {
    let symbol: String
    let label: String
    var color = ReadingPalette.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 47, height: 47)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

struct SectionRule: View {
    var body: some View { Rectangle().fill(ReadingPalette.rule).frame(height: 1).accessibilityHidden(true) }
}

struct PaperCard: ViewModifier {
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(ReadingPalette.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(ReadingPalette.rule.opacity(0.75), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func paperCard(radius: CGFloat = 22) -> some View { modifier(PaperCard(radius: radius)) }

    func readingWidth(_ width: CGFloat = 660) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }

    func readingBackground() -> some View {
        background { ReadingPalette.paper.ignoresSafeArea() }
        .foregroundStyle(ReadingPalette.ink)
    }
}

struct MessageAlert: ViewModifier {
    @Binding var message: String?
    var title: String

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func messageAlert(_ message: Binding<String?>, title: String = "留白") -> some View {
        modifier(MessageAlert(message: message, title: title))
    }
}
