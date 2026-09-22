import SwiftUI

/// The app's primary action: a large microphone control whose appearance is
/// driven entirely by ``DictationState``.
struct DictationButton: View {
    let state: DictationState
    let action: () -> Void

    var diameter: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillStyle)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)

                if state.isCapturing {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 6)
                        .frame(width: diameter + 22, height: diameter + 22)
                        .scaleEffect(pulse ? 1.06 : 0.96)
                        .opacity(pulse ? 0.25 : 0.8)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                            value: pulse
                        )
                        .allowsHitTesting(false)
                }

                Image(systemName: symbolName)
                    .font(.system(size: diameter * 0.36, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!state.canStart && !state.isCapturing)
        .onAppear { pulse = state.isCapturing }
        .onChange(of: state.isCapturing) { _, isCapturing in pulse = isCapturing }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Converts your speech into polished text.")
    }

    @State private var pulse = false

    private var symbolName: String {
        switch state {
        case .listening: "stop.fill"
        case .transcribing, .processing, .requestingPermission: "ellipsis"
        case .idle, .completed, .failed: "mic.fill"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .listening: "Stop dictation"
        case .transcribing, .processing, .requestingPermission: "Dictora is working"
        case .idle, .completed, .failed: "Start dictation"
        }
    }

    private var fillStyle: AnyShapeStyle {
        switch state {
        case .listening: AnyShapeStyle(Color.red.gradient)
        case .requestingPermission, .transcribing, .processing: AnyShapeStyle(Color.secondary.gradient)
        case .idle, .completed, .failed: AnyShapeStyle(Color.accentColor.gradient)
        }
    }
}

#Preview {
    HStack(spacing: 32) {
        DictationButton(state: .idle) {}
        DictationButton(state: .listening) {}
        DictationButton(state: .processing) {}
    }
    .padding(48)
}
