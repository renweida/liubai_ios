import SwiftUI

enum MiniGame: String, Hashable {
    case numbers, piano

    var title: String {
        switch self {
        case .numbers: "叠数"
        case .piano: "逐拍"
        }
    }

    var symbol: String {
        switch self {
        case .numbers: "square.grid.2x2"
        case .piano: "pianokeys"
        }
    }

    var summary: String {
        switch self {
        case .numbers: "滑动数字，合并相同的方块，试着叠到 2048。"
        case .piano: "看着音块落下，在它经过拍线时按下琴键。"
        }
    }
}

struct MiniGameCard: View {
    let game: MiniGame
    let height: CGFloat
    let open: () -> Void

    var body: some View {
        let compact = height < 535
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            Button(action: open) {
                MiniGameCover(game: game)
                    .frame(height: max(78, min(280, height * (compact ? 0.38 : 0.44))))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("玩\(game.title)")
            .accessibilityIdentifier("reading.game.\(game.rawValue)")

            Label("小游戏", systemImage: game.symbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(ReadingPalette.accent)
            Text(game.title)
                .font(ReadingPalette.editorial(compact ? 35 : 48, relativeTo: .largeTitle))
                .accessibilityAddTraits(.isHeader)
                .layoutPriority(1)
            Text(game.summary)
                .font(.subheadline)
                .foregroundStyle(ReadingPalette.muted)
                .lineSpacing(4)
                .layoutPriority(1)

            Spacer(minLength: 4)
            Button(action: open) {
                Label("开始游戏", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 47)
                    .foregroundStyle(ReadingPalette.actionInk)
                    .background(ReadingPalette.actionFill, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 5)
    }
}

private struct MiniGameCover: View {
    let game: MiniGame

    var body: some View {
        ZStack {
            LinearGradient(colors: [base, shade], startPoint: .bottomLeading, endPoint: .topTrailing)
            Canvas { context, size in
                let spacing = min(size.width, size.height) * 0.15
                let center = CGPoint(x: size.width * 0.56, y: size.height * 0.5)
                let gleam = Color(red: 0.91, green: 0.88, blue: 0.74)

                switch game {
                case .numbers:
                    for row in 0..<4 {
                        for column in 0..<4 {
                            let origin = CGPoint(x: center.x + (CGFloat(column) - 2) * spacing,
                                                 y: center.y + (CGFloat(row) - 2) * spacing)
                            let rect = CGRect(origin: origin, size: CGSize(width: spacing - 4, height: spacing - 4))
                            let tile = Path(roundedRect: rect, cornerRadius: spacing * 0.2)
                            let marked = column == row || (row == 2 && column == 1)
                            context.fill(tile, with: .color(gleam.opacity(marked ? 0.21 : 0.06)))
                            context.stroke(tile, with: .color(gleam.opacity(marked ? 0.78 : 0.26)), lineWidth: 0.75)
                            if marked {
                                let text = Text("\(2 << (row + column))")
                                    .font(.system(size: spacing * 0.35, weight: .medium, design: .serif))
                                    .foregroundStyle(gleam)
                                context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
                            }
                        }
                    }
                case .piano:
                    for column in 0..<4 {
                        let x = center.x + (CGFloat(column) - 2) * spacing
                        let track = CGRect(x: x, y: size.height * 0.18, width: spacing - 5, height: size.height * 0.64)
                        context.stroke(Path(roundedRect: track, cornerRadius: 8),
                                       with: .color(gleam.opacity(0.38)), lineWidth: 0.75)
                        let y = size.height * [0.49, 0.25, 0.58, 0.37][column]
                        let note = CGRect(x: x + 3, y: y, width: track.width - 6, height: spacing * 0.8)
                        context.fill(Path(roundedRect: note, cornerRadius: 6), with: .color(gleam.opacity(0.85)))
                    }
                    var line = Path()
                    line.move(to: CGPoint(x: center.x - spacing * 2.6, y: size.height * 0.74))
                    line.addLine(to: CGPoint(x: center.x + spacing * 2.5, y: size.height * 0.74))
                    context.stroke(line, with: .color(gleam.opacity(0.65)), lineWidth: 1)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityHidden(true)
    }

    private var base: Color {
        switch game {
        case .numbers: Color(red: 0.13, green: 0.24, blue: 0.19)
        case .piano: Color(red: 0.18, green: 0.21, blue: 0.31)
        }
    }

    private var shade: Color {
        switch game {
        case .numbers: Color(red: 0.31, green: 0.40, blue: 0.29)
        case .piano: Color(red: 0.36, green: 0.35, blue: 0.46)
        }
    }
}

struct MiniGameScreen: View {
    let game: MiniGame

    var body: some View {
        Group {
            switch game {
            case .numbers: NumberMergeView()
            case .piano: PianoRhythmView()
            }
        }
        .readingBackground()
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

struct MiniGameScore: View {
    let score: Int
    let best: Int

    var body: some View {
        HStack(spacing: 0) {
            value("本局", score: score, id: "game.score")
            Rectangle().fill(ReadingPalette.rule).frame(width: 1, height: 30)
                .accessibilityHidden(true)
            value("最高分", score: best, id: "game.best")
        }
        .padding(.vertical, 10)
        .paperCard(radius: 15)
    }

    private func value(_ title: String, score: Int, id: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(ReadingPalette.muted)
            Text(score, format: .number)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity)
    }
}
