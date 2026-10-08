//
//  ImportShareHintCard.swift
//  RecipeScalerNative
//
//  Spec 080 — Text tab card that teaches the faster path: Share in Safari →
//  Recipe Scaler (Share Extension, spec 025). The mini share sheet is decorative.
//  Closing it hides it for good on this device.
//

import SwiftUI

enum ImportShareHintPreferences {
    static let dismissedKey = "import-share-hint-dismissed"
}

struct ImportShareHintCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("import.share-hint.title")
                        .appHeadline()
                    Text(Self.body)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button(action: onDismiss) {
                    AppSymbol.image("xmark")
                        .font(AppTypography.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Bundle.currentLocalizedString("common.close"))
                .accessibilityIdentifier(AccessibilityIdentifiers.importShareHintDismiss)
            }
            miniShareSheet
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier(AccessibilityIdentifiers.importShareHint)
    }

    /// «Share» is set in `**…**` in the string; it gets the project's medium weight, not Martian Bold.
    private static var body: AttributedString {
        let raw = Bundle.currentLocalizedString("import.share-hint.body")
        var text = (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].inlinePresentationIntent = nil
            text[run.range].font = AppTypography.footnoteSemibold
        }
        return text
    }

    private var miniShareSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppSymbol.sizedImage("fork.knife", pointSize: 13, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                Text("import.share-hint.page")
                    .appFootnote()
                    .lineLimit(1)
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ShareTile(labelKey: "import.share-hint.airdrop") {
                    symbolIcon("dot.radiowaves.left.and.right", foreground: .blue, background: Color(.systemBackground))
                }
                ShareTile(labelKey: "import.share-hint.messages") {
                    symbolIcon("message.fill", foreground: .white, background: .green)
                }
                ShareTile(labelKey: "import.share-hint.app", isHighlighted: true) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFill()
                }
                ShareTile(labelKey: "import.share-hint.notes") {
                    symbolIcon("note.text", foreground: .white, background: .yellow)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGroupedBackground))
        )
    }

    private func symbolIcon(_ name: String, foreground: Color, background: Color) -> some View {
        background.overlay {
            AppSymbol.sizedImage(name, pointSize: 22, weight: .semibold)
                .foregroundStyle(foreground)
        }
    }
}

private struct ShareTile<Icon: View>: View {
    let labelKey: LocalizedStringKey
    var isHighlighted = false
    @ViewBuilder let icon: () -> Icon

    private static var side: CGFloat { 50 }
    private static var radius: CGFloat { 12 }

    var body: some View {
        VStack(spacing: 6) {
            icon()
                .frame(width: Self.side, height: Self.side)
                .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                // The other apps step back, so ours stands out.
                .grayscale(isHighlighted ? 0 : 1)
                .overlay {
                    if isHighlighted {
                        ImportShareHintRing(radius: Self.radius)
                    }
                }
            Text(labelKey)
                .font(isHighlighted ? AppTypography.sansMedium(11) : AppTypography.sans(11))
                .foregroundStyle(isHighlighted ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The link-blue ring around the app tile; a soft pulse spreads from it unless Reduce Motion is on.
/// TimelineView instead of `repeatForever`: inside a List row the latter also animated the row's frame.
private struct ImportShareHintRing: View {
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: TimeInterval = 1.6

    var body: some View {
        ZStack {
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Self.period) / Self.period
                    ring(lineWidth: 3)
                        .scaleEffect(1 + 0.22 * phase)
                        .opacity(0.6 * (1 - phase))
                }
            }
            ring(lineWidth: 3)
        }
        .padding(-5)
        .allowsHitTesting(false)
    }

    private func ring(lineWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius + 5, style: .continuous)
            .strokeBorder(RecipeDescriptionStyle.linkColor, lineWidth: lineWidth)
    }
}
