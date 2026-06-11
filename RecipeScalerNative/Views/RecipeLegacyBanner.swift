import SwiftUI

struct RecipeLegacyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppSymbol.image("info.circle.fill")
                .foregroundStyle(.secondary)
            Text("edit.legacy.banner")
                .appBody()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}