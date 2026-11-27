import SwiftUI

struct NumberMergeBoard {
    enum Direction: String, CaseIterable {
        case left, up, down, right

        var label: String {
            switch self {
            case .left: "向左移动"
            case .up: "向上移动"
            case .down: "向下移动"
            case .right: "向右移动"
            }
        }

        func indices(for line: Int) -> [Int] {
            (0..<4).map { step in
                switch self {
                case .left: line * 4 + step
                case .right: line * 4 + (3 - step)
                case .up: step * 4 + line
                case .down: (3 - step) * 4 + line
                }
            }
        }
    }

    private(set) var tiles = Array(repeating: 0, count: 16)
    private(set) var score = 0

    init() {
        let start = Int.random(in: 0..<4) * 4 + Int.random(in: 0..<3)
        tiles[start] = 2
        tiles[start + 1] = 2
    }

    var reachedGoal: Bool { tiles.contains { $0 >= 2048 } }

    var isOver: Bool {
        guard !tiles.contains(0) else { return false }
        return !tiles.indices.contains { index in
            let value = tiles[index]
            return (index % 4 < 3 && value == tiles[index + 1])
                || (index < 12 && value == tiles[index + 4])
        }
    }

    mutating func move(_ direction: Direction) {
        var moved = tiles
        var points = 0

        for line in 0..<4 {
            let indices = direction.indices(for: line)
            let values = indices.map { tiles[$0] }.filter { $0 > 0 }
            var merged: [Int] = []
            var index = 0

            while index < values.count {
                let value = values[index]
                if index + 1 < values.count && values[index + 1] == value {
                    let combined = value * 2
                    merged.append(combined)
                    points += combined
                    index += 2
                } else {
                    merged.append(value)
                    index += 1
                }
            }

            for (offset, tileIndex) in indices.enumerated() {
                moved[tileIndex] = offset < merged.count ? merged[offset] : 0
            }
        }

        guard moved != tiles else { return }
        let empty = moved.indices.filter { moved[$0] == 0 }
        if let tile = empty.randomElement() {
            moved[tile] = Int.random(in: 0..<10) == 0 ? 4 : 2
        }
        tiles = moved
        score += points
    }
}

struct NumberMergeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("numberMergeBest") private var best = 0
    @State private var board = NumberMergeBoard()

    var body: some View {
        ScrollView {
            VStack(spacing: 19) {
                MiniGameScore(score: board.score, best: best)

                boardView

                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(ReadingPalette.muted)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    ForEach(NumberMergeBoard.Direction.allCases, id: \.self) { direction in
                        Button {
                            move(direction)
                        } label: {
                            Image(systemName: "arrow.\(direction.rawValue)")
                                .frame(width: 44, height: 36)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(direction.label)
                        .accessibilityIdentifier("numbers.move.\(direction.rawValue)")
                        .disabled(board.isOver)
                    }
                }

                Button("重开一局", systemImage: "arrow.counterclockwise") {
                    board = NumberMergeBoard()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("numbers.restart")
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .readingWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.selection, trigger: board.tiles)
    }

    private var status: String {
        if board.isOver { return "棋盘已满，可以重开一局。" }
        if board.reachedGoal { return "已叠到 2048，可以继续合并。" }
        return "滑动棋盘，或点下方箭头，合并相同数字。"
    }

    private var boardView: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 7
            let side = (proxy.size.width - 5 * spacing) / 4

            VStack(spacing: spacing) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<4, id: \.self) { column in
                            tile(board.tiles[row * 4 + column], side: side)
                        }
                    }
                }
            }
            .padding(spacing)
            .background(ReadingPalette.rule, in: .rect(cornerRadius: 20))
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 18).onEnded { gesture in
                let translation = gesture.translation
                if abs(translation.width) > abs(translation.height) {
                    move(translation.width > 0 ? .right : .left)
                } else {
                    move(translation.height > 0 ? .down : .up)
                }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("叠数棋盘")
            .accessibilityValue((0..<4).map { row in
                board.tiles[(row * 4)..<(row * 4 + 4)].map { $0 == 0 ? "空" : String($0) }.joined(separator: "，")
            }.joined(separator: "。"))
            .accessibilityIdentifier("numbers.board")
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func tile(_ value: Int, side: CGFloat) -> some View {
        let isDeep = value >= 16
        return RoundedRectangle(cornerRadius: 12)
            .fill(isDeep ? ReadingPalette.actionFill.opacity(value >= 128 ? 1 : 0.88)
                         : value == 0 ? ReadingPalette.paper.opacity(0.72) : value == 2 ? ReadingPalette.surface : ReadingPalette.quiet)
            .frame(width: side, height: side)
            .overlay {
                if value > 0 {
                    Text(value.formatted(.number.grouping(.never)))
                        .font(.system(size: side * 0.38, weight: .semibold, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .padding(.horizontal, 3)
                        .foregroundStyle(isDeep ? ReadingPalette.actionInk : ReadingPalette.ink)
                }
            }
    }

    private func move(_ direction: NumberMergeBoard.Direction) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            board.move(direction)
        }
        best = max(best, board.score)
    }
}
