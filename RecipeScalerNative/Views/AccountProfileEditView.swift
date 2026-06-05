//
//  AccountProfileEditView.swift
//  RecipeScalerNative
//

import PhotosUI
import SwiftUI

struct AccountProfileEditView: View {
    @ObservedObject var viewModel: AccountSettingsViewModel
    @EnvironmentObject private var syncService: YjsSyncService

    @State private var avatarItem: PhotosPickerItem?
    @State private var usernameDraft: String
    @State private var avatarVersion = UUID()

    private static let avatarSize: CGFloat = 80

    init(viewModel: AccountSettingsViewModel) {
        self.viewModel = viewModel
        _usernameDraft = State(initialValue: viewModel.username ?? "")
    }

    var body: some View {
        List {
            avatarSection
            fieldsSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        .appListBodyTypography()
        .localizedNavigationTitle("account.profile.edit")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: avatarItem) { _, item in
            Task { @MainActor in
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self) else { return }
                await viewModel.uploadAvatar(data: data, syncService: syncService)
                avatarVersion = UUID()
                avatarItem = nil
            }
        }
        .onChange(of: viewModel.username) { _, new in
            usernameDraft = new ?? ""
        }
    }

    // MARK: - Аватар

    @ViewBuilder
    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                ZStack(alignment: .topTrailing) {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        avatarCircle
                            .id(avatarVersion)
                    }
                    .buttonStyle(.plain)

                    if viewModel.avatarURL != nil {
                        Button {
                            Task { @MainActor in
                                await viewModel.deleteAvatar(syncService: syncService)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.iconSize(22))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color(.systemBackground), Color(.secondaryLabel))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel(String(localized: "account.avatar.delete"))
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)

            PhotosPicker(selection: $avatarItem, matching: .images) {
                Text("account.profile.set-photo")
                    .appBody()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var avatarCircle: some View {
        Group {
            if let url = viewModel.avatarURL {
                AuthAvatarImage(url: url)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
    }

    // MARK: - Имя и никнейм

    @ViewBuilder
    private var fieldsSection: some View {
        Section {
            HStack {
                Text("account.profile.name")
                    .appBody()
                TextField("", text: $viewModel.displayName)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .onSubmit { viewModel.scheduleNameSave() }
            }

            if viewModel.canChangeUsername {
                HStack {
                    Text("account.username.placeholder")
                        .appBody()
                    TextField("", text: $usernameDraft)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { @MainActor in await viewModel.saveUsername(usernameDraft) }
                        }
                }
            } else if let username = viewModel.username {
                HStack {
                    Text("account.username.placeholder")
                        .appBody()
                    Spacer()
                    Text("@\(username)")
                        .appBody()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AccountProfileEditView(viewModel: AccountSettingsViewModel())
    }
}
#endif
