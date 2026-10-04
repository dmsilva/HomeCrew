import SwiftUI

/// A member's initial on their colour: how the app shows "whose is this" without words.
struct MemberAvatar: View {
    @ObservedObject var member: Member
    var size: CGFloat = 56

    var body: some View {
        Text(member.initial)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(member.palette.foreground))
            .frame(width: size, height: size)
            .background(Color(member.palette.soft), in: Circle())
            .accessibilityHidden(true)
    }
}
