//
//  AuthView.swift
//  RecipeScalerNative
//
//

import SwiftUI

struct AuthView: View {
    @Environment(\.locale) private var locale
    @State private var authService = AuthService.shared
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSeedInput = false
    @State private var seedPhrase = ""
    @State private var showQRScanner = false

    private let gradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.60, blue: 0.43),
            Color(red: 1.00, green: 0.25, blue: 0.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        let _ = locale
        return ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 20) {
                    if !showSeedInput {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color(red: 0.88, green: 0.22, blue: 0.00, opacity: 0.30), radius: 40, x: 0, y: 10)
                                .frame(width: 96, height: 96)

                            Image("AppLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                    }

                    if showSeedInput {
                        VStack(alignment: .leading, spacing: 16) {
                            Button {
                                showSeedInput = false
                            } label: {
                                HStack(spacing: 4) {
                                    AppSymbol.image("chevron.left")
                                        .font(AppTypography.iconSize(AppTypography.compactSize))
                                    Text(verbatim: authString("Back"))
                                        .appBody()
                                }
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(AccessibilityIdentifiers.authBackButton)

                            Text(verbatim: authString("auth.login"))
                                .font(AppTypography.display(AppTypography.authTitleSize))
                                .padding(.top, 8)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: authString("auth.step1-open-account"))
                                    .appBody()
                                Text(verbatim: authString("auth.step2-press-login"))
                                    .appBody()
                                Text(verbatim: authString("auth.step3-enter-seed"))
                                    .appBody()
                            }
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 8) {
                            Text(verbatim: authString("auth.welcome-title"))
                                .font(AppTypography.display(AppTypography.authTitleSize))

                            Text(verbatim: authString("auth.welcome-subtitle"))
                                .appBody()
                        }
                        .multilineTextAlignment(.center)
                    }

                    if showError {
                        Text(errorMessage)
                            .appFootnote()
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
                            )
                    }

                    if showSeedInput {
                        VStack(spacing: 12) {
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $seedPhrase)
                                    .appBodyFieldTypography()
                                    .frame(height: 120)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .padding(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )
                                    .accessibilityIdentifier(AccessibilityIdentifiers.authSeedTextEditor)

                                if seedPhrase.isEmpty {
                                    Text(verbatim: authString("auth.seed-placeholder"))
                                        .appBody()
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 17)
                                        .padding(.top, 20)
                                        .allowsHitTesting(false)
                                }

                                VStack {
                                    HStack {
                                        Spacer()
                                        Button {
                                            showQRScanner = true
                                        } label: {
                                            AppSymbol.image("qrcode.viewfinder")
                                                .font(AppTypography.iconSize(AppTypography.title3Size))
                                                .foregroundColor(.primary)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(8)
                                        .accessibilityLabel(Bundle.currentLocalizedString("Scan QR code"))
                                        .accessibilityIdentifier(AccessibilityIdentifiers.authQRCodeButton)
                                    }
                                    Spacer()
                                }
                            }

                            Button {
                                Task { await loginUser() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text(verbatim: authString("auth.login"))
                                            .font(AppTypography.sansMedium(18))
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                }
                            }
                            .frame(height: 48)
                            .background(
                                seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                                    ? Color(.systemGray5)
                                    : Color(.darkGray)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .disabled(seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                            .accessibilityIdentifier(AccessibilityIdentifiers.authLoginButton)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Button {
                                Task { await registerUser() }
                            } label: {
                                Text(verbatim: authString("auth.new-user"))
                                    .font(AppTypography.sansMedium(18))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 15)
                                    .frame(maxWidth: .infinity)
                                    .background(gradient)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .disabled(isLoading)
                            .accessibilityIdentifier(AccessibilityIdentifiers.authNewUserButton)

                            Button {
                                showSeedInput = true
                            } label: {
                                Text(verbatim: authString("auth.used-before"))
                                    .font(AppTypography.sansMedium(18))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 15)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color(.systemGray4), lineWidth: 2)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                            .accessibilityIdentifier(AccessibilityIdentifiers.authExistingUserButton)
                        }
                    }
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if showSeedInput && value.translation.width > 100 {
                                withAnimation {
                                    showSeedInput = false
                                }
                            }
                        }
                )

                Spacer()
            }
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView(
                onResult: { text in
                    let normalized = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        .split(separator: " ")
                        .joined(separator: " ")
                    seedPhrase = normalized
                    showQRScanner = false
                    let wordCount = normalized.split(separator: " ").count
                    if wordCount == 12 {
                        Task { await loginUser(seed: normalized) }
                    }
                },
                onClose: { showQRScanner = false }
            )
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.authRoot)
    }

    private func authString(_ key: String) -> String {
        Bundle.currentLocalizedString(key)
    }

    private func registerUser() async {
        isLoading = true
        showError = false
        defer { isLoading = false }

        do {
            _ = try await authService.registerAuto()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func loginUser(seed: String? = nil) async {
        let phrase = seed ?? seedPhrase
        isLoading = true
        showError = false
        defer { isLoading = false }

        do {
            _ = try await authService.loginWithSeed(phrase)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    AuthView()
}
