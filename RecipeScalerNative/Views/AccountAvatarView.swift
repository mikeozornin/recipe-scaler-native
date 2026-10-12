import SwiftUI

/// The account avatar of «Моё всё» and the iPad sidebar footer (spec 081, T015): the
/// photo if there is one, otherwise `person.circle.fill`. No generated pattern
/// (spec.md Q6, FR-005).
struct AccountAvatarView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AuthAvatarImage(url: url)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
