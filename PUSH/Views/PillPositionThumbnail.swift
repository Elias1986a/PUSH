import SwiftUI
import PUSHCore

/// A little screen showing where the pill sits. Cheaper to understand than the
/// paragraph it replaced, and it is the one place the brand's pulse colour
/// appears outside the pill itself.
///
/// Shared by the Pill settings pane and the welcome wizard, which is why it
/// lives in its own file rather than inside `SettingsView`: the wizard asks the
/// same question, and asking it with a different picture would make the two
/// read as different settings.
struct PillPositionThumbnail: View {
    let position: AppState.PillPosition
    let isSelected: Bool

    private static let pulse = Color(red: 0.69, green: 1.0, blue: 0.0)
    private static let desktop = Color(red: 0.43, green: 0.49, blue: 0.55)

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Rectangle().fill(Self.desktop)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 12)
                    Spacer(minLength: 0)
                }

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 132, height: 60)
            }
            .frame(width: 176, height: 112)
            .overlay(alignment: position == .top ? .top : .bottom) {
                pill
                    .padding(.bottom, position == .top ? 0 : 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.12),
                                  lineWidth: isSelected ? 2.5 : 0.5)
            }

            Text(position.displayName)
                .font(.caption)
                .fontWeight(isSelected ? .medium : .regular)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var pill: some View {
        if position == .top {
            waveform
                .frame(width: 96, height: 20)
                .background(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 8
                    )
                    .fill(Color(white: 0.11))
                )
        } else {
            waveform
                .frame(width: 84, height: 22)
                .background(Capsule().fill(Color(white: 0.11).opacity(0.92)))
        }
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach([CGFloat(6), 10, 7, 11, 5], id: \.self) { height in
                Capsule()
                    .fill(Self.pulse)
                    .frame(width: 2.5, height: height)
            }
        }
    }
}
