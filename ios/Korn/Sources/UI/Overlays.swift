import SwiftUI

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3, y = geo.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

struct LevelOverlay: View {
    let degrees: Double

    var body: some View {
        let level = abs(degrees) < 1
        // Nur nahe der Waagerechten einblenden, sonst stört die Linie.
        if abs(degrees) < 25 {
            ZStack {
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 150, height: 1)
                Rectangle().fill(level ? Color.green : Color.orange)
                    .frame(width: 90, height: level ? 2 : 1.5)
                    .rotationEffect(.degrees(-degrees))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// AR-Führung: zeigt Motivpunkt, Zielpunkt und eine Handlungsanweisung.
struct GuideOverlay: View {
    let guide: CompositionGuide?
    let message: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let g = guide {
                    let s = CGPoint(x: g.subject.x * geo.size.width, y: g.subject.y * geo.size.height)
                    let t = CGPoint(x: g.target.x * geo.size.width, y: g.target.y * geo.size.height)
                    let color = g.aligned ? Color.green : Color.orange
                    Path { p in p.move(to: s); p.addLine(to: t) }
                        .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    Circle().stroke(color, lineWidth: 2).frame(width: 44, height: 44).position(t)
                    Circle().fill(color).frame(width: 6, height: 6).position(t)
                    Circle().fill(Color.white).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                        .position(s)
                }
                VStack(spacing: 4) {
                    Spacer()
                    if let g = guide {
                        Text(g.rule).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        Text(g.hint).font(.subheadline.weight(.semibold))
                            .foregroundStyle(g.aligned ? Color.green : Color.white)
                    } else if let message {
                        Text(message).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct LookPicker: View {
    @ObservedObject var model: CameraModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.look.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(model.look.detail).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Slider(value: $model.strength, in: 0...1).tint(.orange).frame(width: 110)
                    .accessibilityLabel("Stärke des Looks")
                Button { model.recommendLook() } label: {
                    Label("AI", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10).frame(minHeight: 32)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                }
                .accessibilityLabel("Look per AI vorschlagen")
            }
            .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FilmLook.all) { look in
                            let active = look.id == model.look.id
                            Button { model.look = look } label: {
                                Text(look.name)
                                    .font(.footnote.weight(active ? .bold : .medium))
                                    .foregroundStyle(active ? Color.black : Color.white)
                                    .padding(.horizontal, 14).frame(minHeight: 36)
                                    .background(active ? Color.orange : Color.white.opacity(0.12),
                                                in: Capsule())
                            }
                            .id(look.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: model.look.id) { _, id in
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}
