import SwiftUI
import RecipeScalerCore

/// macOS renderer for the shared recipe-description markup.
///
/// The iOS renderer uses a UITextView for precise inline layout and tap
/// anchors. macOS keeps the same parser and timer URL contract, but renders
/// the resulting attributed text with SwiftUI so the native target does not
/// display the source HTML or pull UIKit-only views into the Mac target.
struct MacRecipeDescriptionView: View {
    let htmlContent: String
    let recipeId: String
    let recipeDisplayName: String?

    @Environment(TimerManager.self) private var timerManager
    @State private var document = RecipeDescriptionDocument(blocks: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(document.blocks) { block in
                blockView(block)
                    .padding(.bottom, blockBottomPadding(block))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(
            \.openURL,
            OpenURLAction { url in
                handleOpenURL(url)
            }
        )
        .task(id: htmlContent) {
            document = RecipeDescriptionParser.parse(htmlContent)
        }
    }

    @ViewBuilder
    private func blockView(_ block: RecipeDescriptionBlock) -> some View {
        switch block {
        case .paragraph(_, let runs):
            inlineText(runs)
        case .orderedStep(_, let number, let runs):
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(AppTypography.sansMedium(AppTypography.compactSize))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background {
                        Circle()
                            .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.75)
                            .background(Circle().fill(Color.accentColor.opacity(0.12)))
                    }
                inlineText(runs)
            }
        case .bullet(_, let runs):
            HStack(alignment: .top, spacing: 8) {
                Text("–")
                    .appBody()
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 12, alignment: .leading)
                inlineText(runs)
            }
        case .heading(_, let level, let runs):
            inlineText(runs, font: AppTypography.display(AppTypography.bodySize * 1.1))
                .padding(.top, level > 1 ? 4 : 0)
        }
    }

    private func inlineText(
        _ runs: [RecipeDescriptionInlineRun],
        font: Font = AppTypography.body
    ) -> some View {
        Text(attributedString(for: runs, font: font))
            .foregroundStyle(.primary)
            .lineSpacing(AppTypography.bodyLineSpacing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributedString(
        for runs: [RecipeDescriptionInlineRun],
        font: Font
    ) -> AttributedString {
        var result = AttributedString()

        for run in runs {
            switch run {
            case .plain(let value):
                result.append(segment(value, font: font))
            case .strong(let value):
                result.append(segment(value, font: AppTypography.bodySemibold))
            case .em(let value):
                result.append(segment(value, font: font.italic()))
            case .link(let url, let text):
                var value = segment(text, font: font, color: .accentColor)
                value.underlineStyle = .single
                if let linkURL = URL(string: url), !url.isEmpty {
                    value.link = linkURL
                }
                result.append(value)
            case .timer(let reference):
                var value = segment(reference.displayText, font: font, color: .accentColor)
                if let linkURL = reference.linkURL() {
                    value.link = linkURL
                }
                result.append(value)
            case .ingredient(_, _, _, let text):
                result.append(segment(text, font: font, color: .accentColor))
            case .lineBreak:
                result.append(segment("\n", font: font))
            }
        }

        return result
    }

    private func segment(
        _ text: String,
        font: Font,
        color: Color = .primary
    ) -> AttributedString {
        var value = AttributedString(text)
        value.font = font
        value.foregroundColor = color
        return value
    }

    private func blockBottomPadding(_ block: RecipeDescriptionBlock) -> CGFloat {
        switch block {
        case .paragraph, .heading:
            return AppTypography.bodySize * 0.25
        case .orderedStep:
            return 6
        case .bullet:
            return 4
        }
    }

    private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == RecipeDescriptionTimerReference.linkScheme else {
            return .systemAction
        }
        guard let reference = RecipeDescriptionTimerReference.from(link: url),
              reference.isStartable
        else {
            return .handled
        }

        _ = timerManager.createAndStartTimer(
            name: reference.resolvedName,
            duration: TimeInterval(reference.durationSeconds),
            type: reference.type,
            recipeId: recipeId,
            recipeDisplayName: recipeDisplayName
        )
        return .handled
    }
}
