#if os(macOS)
import SwiftUI

/// Everything the floating overlay displays, as one value.
///
/// Passing a snapshot rather than loose parameters means the controller can
/// diff presentations and skip redundant window updates.
struct OverlayPresentation: Equatable, Sendable {
    var state: DictationState
    /// Live mic bands while capturing; ignored for other states.
    var voiceMeter: VoiceMeterReading
    /// Set after a shortcut-triggered dictation is delivered, e.g. "Inserted".
    var footnote: String?
    /// The words so far: live while listening (rough), then the corrected text
    /// once the rewrite finishes.
    var text: String?

    init(
        state: DictationState,
        voiceMeter: VoiceMeterReading = .silent,
        footnote: String? = nil,
        text: String? = nil
    ) {
        self.state = state
        self.voiceMeter = voiceMeter
        self.footnote = footnote
        self.text = text
    }
}

/// Holds what the overlay shows. The panel and its hosting view are created
/// once and this model is updated, so SwiftUI can animate from one state to the
/// next instead of the window being rebuilt on every change.
@MainActor
@Observable
final class OverlayModel {
    var presentation: OverlayPresentation

    init(presentation: OverlayPresentation) {
        self.presentation = presentation
    }
}

/// Floating indicator. There is no panel or pill behind anything: the bars, the
/// words and the status float directly over the desktop, with a soft shadow to
/// keep them legible on any wallpaper.
///
/// While you speak, your words appear live. When the rewrite finishes they
/// change in place to the corrected text, so you see Dictora fix itself.
struct DictationOverlayView: View {
    let model: OverlayModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: OverlayPresentation { model.presentation }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            WordsView(text: presentation.text, isFinal: presentation.state == .completed)

            ZStack {
                switch presentation.state {
                case .listening:
                    VoiceBarsView(meter: presentation.voiceMeter, isActive: true)
                        .frame(width: 104, height: 40)
                        .transition(transition)
                case .requestingPermission, .transcribing, .processing:
                    WorkingContent(title: workingTitle, detail: presentation.state == .requestingPermission ? presentation.footnote : nil)
                        .transition(transition)
                case .completed, .failed, .idle:
                    StatusContent(presentation: presentation)
                        .transition(transition)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.74),
            value: presentation.state
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: 6))
    }

    private var workingTitle: String {
        switch presentation.state {
        case .requestingPermission: "Getting ready…"
        case .transcribing: "Transcribing…"
        case .processing: "Polishing…"
        default: presentation.state.statusText
        }
    }

    private var accessibilityLabel: String {
        var parts = [presentation.state.statusText]
        if let text = presentation.text, !text.isEmpty { parts.append(text) }
        if let footnote = presentation.footnote, !footnote.isEmpty { parts.append(footnote) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Words

/// The dictated words, newest at the end. Long dictations show only the tail,
/// so the line you're speaking is always the one you can see.
private struct WordsView: View {
    let text: String?
    let isFinal: Bool

    private static let tailLength = 170

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayed: String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if isFinal || text.count <= Self.tailLength { return text }
        let tail = text.suffix(Self.tailLength)
        // Start at a word boundary rather than mid-word.
        let trimmed = tail.drop { !$0.isWhitespace }.dropFirst()
        return "…" + (trimmed.isEmpty ? String(tail) : String(trimmed))
    }

    var body: some View {
        Group {
            if let displayed {
                Text(displayed)
                    .font(.system(size: 15, weight: isFinal ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isFinal ? 1 : 0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
                    // The same slot changes in place: rough words become the
                    // corrected sentence with a soft cross-fade.
                    .id(isFinal)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isFinal)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: displayed)
    }
}

// MARK: - Working

private struct WorkingContent: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            ThinkingDots()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: title)
        }
    }
}

/// Three dots that rise and fall in sequence, in place of a generic spinner.
private struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = reduceMotion ? 0.5 : (sin(time * 5.2 - Double(index) * 0.9) + 1) / 2
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.65 + 0.5 * phase)
                        .opacity(0.5 + 0.5 * phase)
                        .offset(y: -3 * phase)
                }
            }
            .frame(width: 30, height: 16)
        }
    }
}

// MARK: - Result

private struct StatusContent: View {
    let presentation: OverlayPresentation

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 8) {
            icon
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .onAppear { appeared = true }
    }

    private var message: String {
        if let footnote = presentation.footnote, !footnote.isEmpty { return footnote }
        return presentation.state.statusText
    }

    @ViewBuilder
    private var icon: some View {
        switch presentation.state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.wiggle, value: appeared)
        default:
            Image(systemName: "mic")
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Bars

/// Vertical bars driven by live mic loudness and frequency bands. They move
/// only when there is real speech: in silence they rest flat.
struct VoiceBarsView: View {
    var meter: VoiceMeterReading
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barWidth: CGFloat = 4.5
    private let spacing: CGFloat = 4
    private let minHeight: CGFloat = 5
    private let maxHeight: CGFloat = 38

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<VoiceMeterReading.bandCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(barFill)
                    .frame(width: barWidth, height: height(for: index))
            }
        }
        .frame(height: maxHeight)
        // Smooths the 30 Hz meter into fluid motion.
        .animation(reduceMotion ? nil : .smooth(duration: 0.12), value: meter)
    }

    private var barFill: some ShapeStyle {
        LinearGradient(
            colors: [Color.white.opacity(0.95), Color.accentColor],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func height(for index: Int) -> CGFloat {
        guard isActive else { return minHeight }
        let band = index < meter.bands.count ? meter.bands[index] : meter.level
        return minHeight + (maxHeight - minHeight) * CGFloat(min(1, max(0, band)))
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.55)
        VStack(spacing: 16) {
            DictationOverlayView(model: OverlayModel(presentation: OverlayPresentation(
                state: .listening,
                voiceMeter: VoiceMeterReading(level: 0.6, bands: [0.2, 0.45, 0.8, 0.95, 0.7, 0.4, 0.25]),
                text: "So I want to remove the background, sorry, not that, this"
            )))
            DictationOverlayView(model: OverlayModel(presentation: OverlayPresentation(state: .processing, text: "so I want to remove")))
            DictationOverlayView(model: OverlayModel(presentation: OverlayPresentation(state: .completed, footnote: "Inserted", text: "I want to remove this.")))
        }
    }
    .frame(width: 440, height: 520)
}
#endif
