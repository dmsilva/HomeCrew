import SwiftUI

/// Shown while this account has no family: create one, or wait for an invitation to arrive.
struct FirstRunView: View {
    let onCreate: (String) -> Void
    let onWaitForInvite: () -> Void

    @State private var name = String(localized: "A nossa família")

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Image(systemName: "house.fill")
                .font(Theme.Typography.heroIcon)
                .foregroundStyle(Color.hcAccent)
                .accessibilityHidden(true)
            TextField("Nome da família", text: $name)
                .font(Theme.Typography.screenTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.hcInk)
            Spacer()
            Button {
                onCreate(name)
            } label: {
                Text("Criar família")
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Tenho um convite", action: onWaitForInvite)
                .frame(minHeight: Theme.minimumTapTarget)
        }
        .padding(Theme.Spacing.xl)
        .background(Color.hcBackground.ignoresSafeArea())
        .tint(.hcAccent)
    }
}

#Preview {
    FirstRunView(onCreate: { _ in }, onWaitForInvite: {})
}
