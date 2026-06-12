//
//  LocalizedNavigationTitle.swift
//  RecipeScalerNative
//
//  Navigation title that refreshes when the in-app language is switched at runtime.
//

import SwiftUI
import UIKit

extension View {
    /// A navigation title that updates when `AppLanguagePreference` switches the language.
    ///
    /// `.navigationTitle(Text("key"))` stores the *localization key*, so after a language
    /// flip the new title compares equal to the old one and SwiftUI never pushes the
    /// re-resolved string to UIKit — the bar keeps the previous title until the view is
    /// rebuilt. Here we resolve the string eagerly from the selected language bundle
    /// (`Bundle.currentLocalizedString` — `String(localized:)` does NOT reliably honor the
    /// runtime override and falls back to the development language) and pass it as a
    /// verbatim `Text`, so the value genuinely changes. Reading `\.locale` forces this
    /// modifier to re-evaluate when the language switches.
    ///
    /// Also sets `UINavigationItem.backBarButtonItem` so pushed screens (e.g. recipe detail
    /// with an empty title) show this title on the back button instead of UIKit's English
    /// fallback "Back".
    ///
    /// - Parameter key: the `Localizable.xcstrings` key for the title.
    func localizedNavigationTitle(_ key: String) -> some View {
        modifier(LocalizedNavigationTitleModifier(key: key))
    }

    /// Sets the back-button label that child screens show when pushed from this view.
    ///
    /// Use when the navigation title is resolved at runtime (folder name, server string)
    /// rather than from a localization key.
    func localizedNavigationBackTitle(verbatim title: String) -> some View {
        modifier(LocalizedNavigationBackTitleModifier(title: title))
    }
}

private struct LocalizedNavigationTitleModifier: ViewModifier {
    let key: String
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        // Reading `locale` is the dependency that re-runs this body on a language switch.
        _ = locale
        let title = Bundle.currentLocalizedString(key)
        return content
            .navigationTitle(Text(verbatim: title))
            .background(NavigationBackTitleSetter(title: title))
    }
}

private struct LocalizedNavigationBackTitleModifier: ViewModifier {
    let title: String
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        _ = locale
        return content.background(NavigationBackTitleSetter(title: title))
    }
}

/// UIKit bridge: SwiftUI does not expose `backBarButtonItem`, which controls the label on
/// pushed screens when the destination uses an empty inline title.
private struct NavigationBackTitleSetter: UIViewControllerRepresentable {
    let title: String

    func makeUIViewController(context: Context) -> NavigationBackTitleViewController {
        NavigationBackTitleViewController(title: title)
    }

    func updateUIViewController(_ uiViewController: NavigationBackTitleViewController, context: Context) {
        uiViewController.backTitle = title
        uiViewController.applyBackTitleIfNeeded()
    }
}

private final class NavigationBackTitleViewController: UIViewController {
    var backTitle: String

    init(title: String) {
        backTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        applyBackTitleIfNeeded(on: parent)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        applyBackTitleIfNeeded(on: parent)
    }

    func applyBackTitleIfNeeded(on parent: UIViewController? = nil) {
        let host = parent ?? self.parent
        let item = host?.navigationItem ?? navigationItem
        item.backBarButtonItem = UIBarButtonItem(
            title: backTitle,
            style: .plain,
            target: nil,
            action: nil
        )
    }
}
