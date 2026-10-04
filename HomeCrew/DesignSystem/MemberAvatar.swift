import SwiftUI

/// A member's initial on their colour: how the app shows "whose is this" without words.
/// A coral thermometer badge marks someone with an open illness episode.
struct MemberAvatar: View {
    @ObservedObject var member: Member
    var size: CGFloat = 56
    /// Draws a ring in the background colour, so overlapping avatars read as separate circles.
    var outlined = false

    var body: some View {
        Text(member.initial)
            .font(Theme.Typography.text(size * 0.42, weight: .heavy))
            .foregroundStyle(Color(member.palette.foreground))
            .frame(width: size, height: size)
            .background(Color(member.palette.soft), in: Circle())
            .overlay {
                if outlined {
                    Circle().strokeBorder(Color.hcBackground, lineWidth: max(size * 0.075, 2))
                }
            }
            .overlay(alignment: .topTrailing) {
                if member.activeEpisode != nil {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: max(size * 0.26, 9), weight: .bold))
                        .foregroundStyle(Color.hcNight)
                        .frame(width: max(size * 0.55, 16), height: max(size * 0.55, 16))
                        .background(Color.hcWarning, in: Circle())
                        .offset(x: size * 0.15, y: -size * 0.15)
                }
            }
            .accessibilityHidden(true)
    }
}
