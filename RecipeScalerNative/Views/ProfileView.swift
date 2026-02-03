//
//  ProfileView.swift
//  RecipeScalerNative
//
//

import SwiftUI

struct ProfileView: View {
    @StateObject private var authService = AuthService.shared
    @State private var showingLogoutConfirmation = false

    var body: some View {
        List {
            Section("Account") {
                if let userId = authService.userId {
                    HStack {
                        Text("User ID")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(truncatedUserId(userId))
                            .font(.custom(AppFonts.mono, size: 17))
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showingLogoutConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Logout")
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Are you sure you want to logout?",
            isPresented: $showingLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Logout", role: .destructive) {
                do {
                    try authService.logout()
                } catch {
                    print("Error logging out: \(error)")
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func truncatedUserId(_ id: String) -> String {
        guard id.count > 10 else { return id }
        let start = id.prefix(6)
        let end = id.suffix(4)
        return "\(start)···\(end)"
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
