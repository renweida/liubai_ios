import AVFoundation
import SwiftUI

struct PianoRound {
    enum Phase { case ready, playing, paused, ended }

    struct Note: Identifiable {
        let id: Int
        let lane: Int
        let beat: TimeInterval
    }

    static let window: TimeInterval = 0.23
    static let fallTime: TimeInterval = 1.35
    private(set) var phase = Phase.ready
    private(set) var notes: [Note] = []
    private(set) var elapsed: TimeInterval = 0
    private(set) var score = 0

    mutating func start() {
        self = PianoRound()
        phase = .playing
        notes = [Note(id: 0, lane: 0, beat: 1.65)]
        for _ in 0..<3 { queueNote() }
    }

    mutating func pause() {
        if phase == .playing { phase = .paused }
    }

    mutating func resume() {
        if phase == .paused { phase = .playing }
    }

    mutating func advance(by delta: TimeInterval) {
        guard phase == .playing else { return }
        elapsed += delta
        if let note = notes.first, elapsed > note.beat + Self.window { phase = .ended }
    }

    mutating func play(lane: Int) -> Bool {
        guard phase == .playing, let note = notes.first else { return false }
        guard lane == note.lane, abs(note.beat - elapsed) <= Self.window else {
            phase = .ended
            return false
        }
        notes.removeFirst()
        score += 1
        queueNote()
        return true
    }

    private mutating func queueNote() {
        guard let previous = notes.last else { return }
        let id = previous.id + 1
        let lane = (previous.lane + Int.random(in: 1...3)) % 4
        let interval = max(0.54, 0.88 - Double(id) * 0.009)
        notes.append(Note(id: id, lane: lane, beat: previous.beat + interval))
    }
}

struct PianoRhythmView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pianoRhythmBest") private var best = 0
    @State private var round = PianoRound()
    @State private var sound = PianoTones()

    private let pitchNames = ["C", "E", "G", "C′"]

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    MiniGameScore(score: round.score, best: best)

                    instrument(height: min(460, max(195, proxy.size.height * 0.52)))

                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(ReadingPalette.muted)
                        .multilineTextAlignment(.center)

                    Button(action: changePhase) {
                        Label(control.title, systemImage: control.symbol)
                            .frame(minHeight: 34)
                            .foregroundStyle(ReadingPalette.actionInk)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(ReadingPalette.actionFill)
                    .accessibilityIdentifier("piano.control")
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .readingWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task(id: round.phase) {
            guard round.phase == .playing else { return }
            var previous = ProcessInfo.processInfo.systemUptime
            while round.phase == .playing {
                do {
                    try await Task.sleep(for: .milliseconds(17))
                } catch { return }
                guard !Task.isCancelled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                round.advance(by: now - previous)
                previous = now
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { round.pause() }
        }
    }

    private var status: String {
        switch round.phase {
        case .ready, .playing: "音块经过拍线时，点按对应琴键。"
        case .paused: "已暂停"
        case .ended: "这一轮结束了。"
        }
    }

    private var control: (title: String, symbol: String) {
        switch round.phase {
        case .ready: ("开始", "play.fill")
        case .playing: ("暂停", "pause.fill")
        case .paused: ("继续", "play.fill")
        case .ended: ("再玩一次", "arrow.counterclockwise")
        }
    }

    private func changePhase() {
        switch round.phase {
        case .ready, .ended: round.start()
        case .playing: round.pause()
        case .paused: round.resume()
        }
    }

    private func instrument(height: CGFloat) -> some View {
        let gap: CGFloat = 6
        return HStack(spacing: gap) {
            ForEach(0..<4, id: \.self) { lane in
                Button {
                    guard round.play(lane: lane) else { return }
                    best = max(best, round.score)
                    sound.play(lane)
                } label: {
                    VStack(spacing: gap) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ReadingPalette.quiet)
                            .frame(height: height)
                        Text(pitchNames[lane])
                            .font(.system(.body, design: .serif).weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(ReadingPalette.surface, in: .rect(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(ReadingPalette.rule, lineWidth: 1)
                            }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(round.phase != .playing)
                .accessibilityLabel("第 \(lane + 1) 键，\(pitchNames[lane])")
                .accessibilityIdentifier("piano.lane.\(lane)")
            }
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                let width = (proxy.size.width - 3 * gap) / 4
                let targetY = height * 0.77
                let hitHeight = targetY * 2 * PianoRound.window / PianoRound.fallTime

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(ReadingPalette.accent.opacity(0.14))
                        .frame(height: hitHeight)
                        .position(x: proxy.size.width / 2, y: targetY)
                    Rectangle()
                        .fill(ReadingPalette.accent.opacity(0.65))
                        .frame(height: 1)
                        .position(x: proxy.size.width / 2, y: targetY)
                    ForEach(round.notes) { note in
                        let progress = 1 + (round.elapsed - note.beat) / PianoRound.fallTime
                        let y = targetY * progress
                        if y > -22, y < height + 22 {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ReadingPalette.actionFill)
                                .frame(width: width - 12, height: 38)
                                .overlay {
                                    Image(systemName: "music.note")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ReadingPalette.actionInk)
                                }
                                .position(x: CGFloat(note.lane) * (width + gap) + width / 2, y: y)
                        }
                    }
                }
            }
            .frame(height: height)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private final class PianoTones {
    private lazy var players = [261.63, 329.63, 392.00, 523.25].map { frequency in
        try? AVAudioPlayer(data: Self.tone(frequency: frequency))
    }

    func play(_ lane: Int) {
        guard let player = players[lane] else { return }
        player.currentTime = 0
        player.play()
    }

    private static func tone(frequency: Double) -> Data {
        let rate: UInt32 = 22_050
        let frames = Int(Double(rate) * 0.23)
        var data = Data()

        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        func tag(_ string: String) { data.append(contentsOf: string.utf8) }

        tag("RIFF")
        append(UInt32(36 + frames * 2))
        tag("WAVE")
        tag("fmt ")
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(rate)
        append(rate * 2)
        append(UInt16(2))
        append(UInt16(16))
        tag("data")
        append(UInt32(frames * 2))

        for frame in 0..<frames {
            let time = Double(frame) / Double(rate)
            let phase = 2 * Double.pi * frequency * time
            let envelope = min(1, time * 250) * exp(-17 * time) * min(1, (0.23 - time) * 65)
            let note = (sin(phase) + 0.22 * sin(2 * phase)) * envelope
            append(Int16(note * 9000))
        }

        return data
    }
}
