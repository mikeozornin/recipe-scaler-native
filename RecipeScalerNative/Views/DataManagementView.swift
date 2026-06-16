import SwiftUI
import RecipeScalerCore
import UniformTypeIdentifiers

struct DataManagementView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var isExporting = false
    @State private var exportProgress: (completed: Int, total: Int)?
    @State private var exportedFileURL: URL?
    @State private var exportError: String?

    @State private var isImporting = false
    @State private var importProgress: (completed: Int, total: Int)?
    @State private var importResult: NativeImportResult?
    @State private var importError: String?
    @State private var importTask: Task<Void, Never>?
    @State private var importStopRequested = false

    @State private var isShowingFileImporter = false

    private var isOnline: Bool {
        syncService.connectionState == .connected
    }

    private var showsImportStatus: Bool {
        isImporting || importResult != nil
    }

    var body: some View {
        Form {
            Section {
                exportRow
            }
            .appListSectionHeaderStyle()

            Section {
                importButtonRow
                if showsImportStatus {
                    importStatusContent
                }
            } header: {
                if showsImportStatus {
                    AppSectionHeader("account.data.import.section")
                }
            }
            .appListSectionHeaderStyle()
        }
        .listStyle(.insetGrouped)
        .appListBodyTypography()
        .localizedNavigationTitle("account.data.management")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [
                .json, .zip, .data
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileImportResult(result)
        }
        .onDisappear {
            importStopRequested = true
            importTask?.cancel()
        }
        .alert(
            "account.data.export.nothing",
            isPresented: Binding(
                get: { exportError == "empty" },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        }
        .alert(
            "account.data.import.error.title",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var exportRow: some View {
        if let (completed, total) = exportProgress, isExporting {
            VStack(alignment: .leading, spacing: 8) {
                Text("account.data.export.title")
                    .appBody()
                FractionProgressView(
                    completed: completed,
                    total: total,
                    messageKey: "account.data.export.progress %d %d"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let fileURL = exportedFileURL {
            ShareLink(item: fileURL) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("account.data.export.share")
                        .appBody()
                    Text(fileURL.lastPathComponent)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            Button {
                exportRecipes()
            } label: {
                Text("account.data.export.title")
                    .appBody()
            }
            .disabled(isExporting || isImporting)
        }
    }

    @ViewBuilder
    private var importButtonRow: some View {
        Button {
            isShowingFileImporter = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("account.data.import.title")
                    .appBody()
                Text("account.data.import.formats")
                    .appFootnote()
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isExporting || isImporting)
    }

    @ViewBuilder
    private var importStatusContent: some View {
        if let (completed, total) = importProgress, isImporting {
            VStack(alignment: .leading, spacing: 12) {
                FractionProgressView(
                    completed: completed,
                    total: total,
                    messageKey: "account.data.import.progress %d %d"
                )

                Button(role: .destructive) {
                    stopImport()
                } label: {
                    Text("account.data.import.stop")
                        .appBody()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let result = importResult {
            VStack(alignment: .leading, spacing: 8) {
                if result.wasStopped {
                    Text("account.data.import.stopped")
                        .appBody()
                        .foregroundStyle(.secondary)
                }
                if result.importedCount > 0 {
                    Text(verbatim: formattedMessage(key: "account.data.import.success %d", count: result.importedCount))
                        .appBody()
                }
                if result.foldersImported > 0 {
                    Text(verbatim: formattedMessage(key: "account.data.import.folders %d", count: result.foldersImported))
                        .appFootnote()
                        .foregroundStyle(.secondary)
                }
                if !result.warnings.isEmpty {
                    ForEach(result.warnings, id: \.self) { warning in
                        Text(warning)
                            .appFootnote()
                            .foregroundStyle(.orange)
                    }
                }
                if !result.errors.isEmpty {
                    ForEach(result.errors, id: \.self) { error in
                        Text(error)
                            .appFootnote()
                            .foregroundStyle(.red)
                    }
                }
                Button {
                    importResult = nil
                } label: {
                    Text("common.close")
                        .appBody()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func exportRecipes() {
        isExporting = true
        exportedFileURL = nil
        exportError = nil
        exportProgress = nil

        let service = NativeExportImportService(syncService: syncService)

        Task { @MainActor in
            do {
                let url = try await service.exportAll { completed, total in
                    exportProgress = (completed, total)
                }
                exportedFileURL = url
            } catch NativeImportError.emptyArchive {
                exportError = "empty"
            } catch {
                exportError = error.localizedDescription
            }
            isExporting = false
            exportProgress = nil
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            startImport(from: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func startImport(from url: URL) {
        importTask?.cancel()
        importStopRequested = false

        isImporting = true
        importResult = nil
        importError = nil
        importProgress = nil

        let accessed = url.startAccessingSecurityScopedResource()
        let service = NativeExportImportService(syncService: syncService)

        importTask = Task { @MainActor in
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
                importTask = nil
            }

            do {
                let result = try await service.importFile(
                    url: url,
                    isOnline: isOnline,
                    shouldStop: { importStopRequested }
                ) { completed, total in
                    importProgress = (completed, total)
                }
                importResult = result
            } catch let error as NativeImportError {
                importError = error.localizedDescription
            } catch {
                if !importStopRequested {
                    importError = error.localizedDescription
                }
            }

            isImporting = false
            importProgress = nil
        }
    }

    private func stopImport() {
        importStopRequested = true
    }

    private func formattedMessage(key: String, count: Int) -> String {
        String(
            format: Bundle.currentLocalizedString(key),
            locale: AppLanguagePreference.current.locale,
            count
        )
    }
}
