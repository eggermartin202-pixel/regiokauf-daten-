import SwiftUI

extension Color {
    /// Polnisches Rot.
    static let brand = Color(red: 0.86, green: 0.08, blue: 0.24)
    static let success = Color(red: 0.16, green: 0.65, blue: 0.38)
    static let warning = Color(red: 0.95, green: 0.6, blue: 0.1)
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .brand
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isEnabled ? color : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct OptionButtonStyle: ButtonStyle {
    var state: OptionState = .normal

    enum OptionState { case normal, selected, correct, wrong }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.medium))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 12)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(border, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }

    private var background: Color {
        switch state {
        case .normal: return Color(.secondarySystemBackground)
        case .selected: return Color.brand.opacity(0.12)
        case .correct: return Color.success.opacity(0.18)
        case .wrong: return Color.brand.opacity(0.18)
        }
    }

    private var border: Color {
        switch state {
        case .normal: return Color(.separator)
        case .selected: return .brand
        case .correct: return .success
        case .wrong: return .brand
        }
    }
}

struct Card<Inner: View>: View {
    @ViewBuilder var content: Inner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct LevelBadge: View {
    let level: Level
    var large = false

    var body: some View {
        Text(level.code)
            .font(large ? .system(size: 56, weight: .heavy, design: .rounded) : .headline.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 28 : 10)
            .padding(.vertical, large ? 14 : 4)
            .background(Color.brand)
            .clipShape(RoundedRectangle(cornerRadius: large ? 24 : 8, style: .continuous))
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = .brand
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
    }
}

struct SpeakButton: View {
    let text: String
    var size: CGFloat = 22
    @EnvironmentObject var store: AppStore

    var body: some View {
        Button {
            Speaker.shared.speak(text, slow: store.state.slowAudio)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: size))
                .padding(10)
                .background(Color.brand.opacity(0.12))
                .clipShape(Circle())
        }
        .accessibilityLabel("Vorlesen")
    }
}
