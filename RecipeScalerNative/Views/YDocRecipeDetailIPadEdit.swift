import SwiftUI

/// Where the user was typing in an iPad recipe edit (spec 081, T043).
enum IPadRecipeEditFocus: Equatable {
    case none
    case title
    /// The steps editor; the Tiptap selection when the editor reported one.
    case steps(from: Int?, to: Int?)

    enum Field {
        case title
        case steps
    }

    var field: Field? {
        switch self {
        case .none: nil
        case .title: .title
        case .steps: .steps
        }
    }
}

/// Spec 081 (T041, T043, FR-018) — a recipe edit on the iPad that outlives its view.
///
/// A size class change, or a resize between the split and the phone stack, rebuilds the
/// recipe view in another container. The new view adopts the session and stays in edit
/// with the same drafts (servings and color, written on «Готово») and the same focus:
/// the title with its unsaved text, or the steps editor with its caret. The text of the
/// steps and ingredients is in the Y.Doc already. Owned by `AppShellCoordinator`
/// (`recipeEdit`); `nil` on the iPhone. Not observed: focus notes redraw nothing.
@MainActor
final class IPadRecipeEditSession {
    let recipeId: String
    let viewModel: RecipeEditViewModel
    private(set) var focus: IPadRecipeEditFocus = .none
    /// The title as typed so far; the title is saved only when the field loses focus.
    private(set) var titleDraft: String?
    /// The recipe views in the edit, the one editing now last. A rebuild can bring up
    /// several views of the recipe in turn; when the last one leaves, the edit goes back to
    /// the one before it that is still there.
    private var owners: [UUID]

    /// The recipe view editing now. Its notes are heard; a view that has left is not: its
    /// fields lose focus as they are torn down, which is not the user's blur.
    var owner: UUID? { owners.last }

    init(recipeId: String, viewModel: RecipeEditViewModel, owner: UUID) {
        self.recipeId = recipeId
        self.viewModel = viewModel
        owners = [owner]
    }

    func adopt(owner: UUID) {
        owners.removeAll { $0 == owner }
        owners.append(owner)
    }

    /// The view left the screen while the edit goes on (it is being rebuilt elsewhere,
    /// or the user switched tabs).
    func release(owner: UUID) {
        owners.removeAll { $0 == owner }
    }

    /// A field gained focus. The focus is where the user types, so a view still in the
    /// edit that gains it is the one editing now, even if a view that came up after it
    /// in a rebuild took the edit for a moment.
    func noteFocus(_ focus: IPadRecipeEditFocus, owner: UUID) {
        guard owners.contains(owner) else { return }
        adopt(owner: owner)
        self.focus = focus
    }

    /// Called a moment after the field lost focus (`IPadRecipeEditFocusTiming`), so a view
    /// torn down in between no longer owns the session and its blur is ignored. The title
    /// is saved on blur, so its draft is no longer needed.
    func noteBlur(_ field: IPadRecipeEditFocus.Field, owner: UUID) {
        guard self.owner == owner else { return }
        if field == .title {
            titleDraft = nil
        }
        guard focus.field == field else { return }
        focus = .none
    }

    func noteTitleText(_ text: String, owner: UUID) {
        guard self.owner == owner else { return }
        titleDraft = text
    }
}

enum IPadRecipeEditFocusTiming {
    /// A real blur outlasts this; a rebuild replaces the view well within it.
    static let blurSettle: Duration = .milliseconds(300)
}

/// Notes the steps editor's focus and caret into the iPad edit session and puts the caret
/// back in a rebuilt view (T043). A view of its own, so caret moves redraw only this probe
/// and not the recipe. Exists only on the iPad, in edit, once the editor is bound.
struct IPadRecipeEditStepsProbe: View {
    let session: IPadRecipeEditSession
    let owner: UUID
    let bridge: DescriptionEditorBridge
    /// The caret of the view this one replaced; `nil` once restored or when there is none.
    let pendingCaret: IPadRecipeEditFocus?
    let onCaretRestored: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: bridge.isFocused) { _, focused in
                if focused {
                    noteCaret()
                } else {
                    let session = session
                    let owner = owner
                    Task { @MainActor in
                        try? await Task.sleep(for: IPadRecipeEditFocusTiming.blurSettle)
                        session.noteBlur(.steps, owner: owner)
                    }
                }
            }
            .onChange(of: bridge.selectionState) { _, _ in
                guard bridge.isFocused else { return }
                noteCaret()
            }
            .onChange(of: bridge.phase == .ready, initial: true) { _, ready in
                guard ready else { return }
                restoreCaretIfNeeded()
            }
    }

    private func noteCaret() {
        let selection = bridge.selectionState
        session.noteFocus(.steps(from: selection.from, to: selection.to), owner: owner)
    }

    private func restoreCaretIfNeeded() {
        guard case let .steps(from, to) = pendingCaret else { return }
        onCaretRestored()
        let bridge = bridge
        // As the start-in-edit focus: let the editor finish its first layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let from {
                bridge.sendCommand(name: "focusAt", args: ["from": from, "to": to ?? from])
            } else {
                bridge.sendCommand(name: "focusEnd")
            }
        }
    }
}

// MARK: - The recipe view in the iPad edit session

extension YDocRecipeDetailView {
    private var iPadEditSession: IPadRecipeEditSession? {
        guard let session = iPadEditHost?.recipeEdit, session.recipeId == recipeId else { return nil }
        return session
    }

    /// The view picks up an edit of its recipe that a view it replaced had going (T043):
    /// same view model (servings and color drafts), the title with its unsaved text or the
    /// steps caret. `true` when this view is in that edit.
    @discardableResult
    func adoptIPadEditSessionIfNeeded() -> Bool {
        guard let session = iPadEditSession else { return false }
        if isEditing {
            guard editViewModel === session.viewModel else { return false }
            // Back from another tab: the same view.
            session.adopt(owner: editOwnerToken)
            return true
        }
        guard canEnterEditMode, recipe != nil else { return false }
        didApplyStartInEditMode = true
        session.adopt(owner: editOwnerToken)
        editViewModel = session.viewModel
        pickerColor = RecipeAccentColor.color(from: session.viewModel.draftColor)
        adoptedTitleDraft = session.titleDraft
        switch session.focus {
        case .title:
            shouldAutoFocusRecipeTitle = true
        case .steps:
            adoptedStepsCaret = session.focus
        case .none:
            break
        }
        isEditing = true
        return true
    }

    /// A recipe created on the iPad opens in edit once: a later rebuild of the view (the
    /// route still says `openInEditMode`) does not enter edit again after «Готово».
    var iPadStartInEditAlreadyApplied: Bool {
        iPadEditHost?.recipeIdsStartedInEdit.contains(recipeId) ?? false
    }

    func noteIPadStartInEditApplied() {
        iPadEditHost?.noteRecipeStartedInEdit(recipeId)
    }

    /// `isEditing` changed: entering edit starts the session (the split hides the list and
    /// expands the recipe), «Готово» ends it.
    func syncIPadEditSession(editing: Bool) {
        guard let host = iPadEditHost else { return }
        if editing {
            guard let editViewModel else { return }
            if let session = iPadEditSession, session.viewModel === editViewModel {
                session.adopt(owner: editOwnerToken)
                return
            }
            host.beginRecipeEdit(IPadRecipeEditSession(
                recipeId: recipeId,
                viewModel: editViewModel,
                owner: editOwnerToken
            ))
        } else {
            guard let session = iPadEditSession,
                  session.owner == editOwnerToken || session.viewModel === editViewModel
            else { return }
            adoptedTitleDraft = nil
            adoptedStepsCaret = nil
            host.endRecipeEdit(recipeId: recipeId, isPadRegular: layoutMode == .padRegular)
        }
    }

    /// `onDisappear`. The edit goes on while its recipe stays open (another tab, or a
    /// rebuild in another container) and ends when the recipe is closed. `true` while
    /// another view of the recipe is still in the edit: the timers capsule stays hidden for it.
    func leaveIPadEditSession() -> Bool {
        guard isEditing, let host = iPadEditHost, let session = iPadEditSession,
              session.viewModel === editViewModel
        else { return false }
        let wasEditingNow = session.owner == editOwnerToken
        session.release(owner: editOwnerToken)
        if wasEditingNow, RecipesSelection.selection(from: host.recipesPath).recipeId != recipeId {
            host.endRecipeEdit(recipeId: recipeId, isPadRegular: layoutMode == .padRegular)
            return false
        }
        return session.owner != nil
    }

    /// The title field gained or lost focus (`RecipeEditHeaderBindable.onEditingActiveChanged`).
    func noteIPadTitleEditing(_ active: Bool) {
        guard let session = iPadEditSession else { return }
        let owner = editOwnerToken
        if active {
            session.noteFocus(.title, owner: owner)
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: IPadRecipeEditFocusTiming.blurSettle)
                session.noteBlur(.title, owner: owner)
            }
        }
    }

    /// The title as typed; `nil` on the iPhone, where nothing has to outlive the view.
    var iPadTitleTextObserver: ((String) -> Void)? {
        guard iPadEditHost != nil else { return nil }
        let owner = editOwnerToken
        let host = iPadEditHost
        let recipeId = recipeId
        return { text in
            guard let session = host?.recipeEdit, session.recipeId == recipeId else { return }
            session.noteTitleText(text, owner: owner)
        }
    }

    /// Notes the steps caret and puts back the adopted one (`IPadRecipeEditStepsProbe`).
    @ViewBuilder
    var iPadEditStepsProbe: some View {
        if isEditing,
           let session = iPadEditSession,
           session.viewModel === editViewModel,
           let bridge = descriptionChrome.bridge {
            IPadRecipeEditStepsProbe(
                session: session,
                owner: editOwnerToken,
                bridge: bridge,
                pendingCaret: adoptedStepsCaret,
                onCaretRestored: { adoptedStepsCaret = nil }
            )
        }
    }
}
