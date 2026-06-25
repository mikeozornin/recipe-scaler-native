//
//  QRScannerView.swift
//  RecipeScalerNative
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Scanner Error

enum QRScannerError: Error {
    case permissionDenied
    case noCamera
    case notReadable
    case unknown
}

// MARK: - QR Scanner View (SwiftUI)

struct QRScannerView: View {
    let onResult: (String) -> Void
    let onClose: () -> Void

    @State private var setupError: QRScannerError?
    @State private var retryCount = 0
    @State private var isScanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let error = setupError {
                    errorView(error)
                } else {
                    CameraRepresentable(
                        onResult: { text in
                            guard !isScanned else { return }
                            isScanned = true
                            onResult(text)
                            onClose()
                        },
                        onSetupFailure: { error in
                            setupError = error
                        }
                    )
                    .ignoresSafeArea()
                }
            }
            .localizedNavigationTitle("qr-scanner.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("qr-scanner.cancel") {
                        onClose()
                    }
                    .foregroundColor(.white)
                    .accessibilityIdentifier(AccessibilityIdentifiers.qrScannerCancel)
                }
            }
        }
        .appOpaqueSheetPresentation(background: .black)
        .onAppear {
            setupError = nil
        }
    }

    @ViewBuilder
    private func errorView(_ error: QRScannerError) -> some View {
        VStack(spacing: 16) {
            Text(errorTitle(error))
                .appHeadline()
                .foregroundColor(.red)
                .multilineTextAlignment(.center)

            Text(errorDescription(error))
                .appFootnote()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if error == .permissionDenied || error == .unknown {
                Button("qr-scanner.try-again") {
                    setupError = nil
                    retryCount += 1
                }
                .appBodyFieldTypography()
                .padding(.top, 8)
            }
        }
        .padding(24)
    }

    private func errorTitle(_ error: QRScannerError) -> String {
        switch error {
        case .permissionDenied:
            return Bundle.currentLocalizedString("qr-scanner.error.permission-denied.title")
        case .noCamera:
            return Bundle.currentLocalizedString("qr-scanner.error.no-camera.title")
        case .notReadable:
            return Bundle.currentLocalizedString("qr-scanner.error.not-readable.title")
        case .unknown:
            return Bundle.currentLocalizedString("qr-scanner.error.unknown.title")
        }
    }

    private func errorDescription(_ error: QRScannerError) -> String {
        switch error {
        case .permissionDenied:
            return String(localized: "qr-scanner.error.permission-denied")
        case .noCamera:
            return String(localized: "qr-scanner.error.no-camera")
        case .notReadable:
            return String(localized: "qr-scanner.error.not-readable")
        case .unknown:
            return String(localized: "qr-scanner.error.unknown")
        }
    }
}

// MARK: - Camera View Controller

private final class QRScannerViewController: UIViewController {
    private let onResult: (String) -> Void
    private let onSetupFailure: (QRScannerError) -> Void
    private let sessionQueue = DispatchQueue(label: "qr-scanner.session")
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(onResult: @escaping (String) -> Void, onSetupFailure: @escaping (QRScannerError) -> Void) {
        self.onResult = onResult
        self.onSetupFailure = onSetupFailure
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessAndSetup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func requestAccessAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupSession()
                    } else {
                        self?.onSetupFailure(.permissionDenied)
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.onSetupFailure(.permissionDenied)
            }
        @unknown default:
            DispatchQueue.main.async { [weak self] in
                self?.onSetupFailure(.unknown)
            }
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async { self.onSetupFailure(.noCamera) }
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let session = AVCaptureSession()
                session.sessionPreset = .high
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    DispatchQueue.main.async { self.onSetupFailure(.notReadable) }
                    return
                }
                let output = AVCaptureMetadataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.metadataObjectTypes = [.qr]
                    output.setMetadataObjectsDelegate(self, queue: sessionQueue)
                } else {
                    DispatchQueue.main.async { self.onSetupFailure(.notReadable) }
                    return
                }
                self.captureSession = session
                DispatchQueue.main.async {
                    self.addPreviewLayer(session: session)
                }
            } catch {
                DispatchQueue.main.async { self.onSetupFailure(.unknown) }
            }
        }
    }

    private func addPreviewLayer(session: AVCaptureSession) {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }
}

extension QRScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let string = object.stringValue else { return }
        captureSession?.stopRunning()
        DispatchQueue.main.async { [weak self] in
            self?.onResult(string)
        }
    }
}

// MARK: - UIViewControllerRepresentable

private struct CameraRepresentable: UIViewControllerRepresentable {
    let onResult: (String) -> Void
    let onSetupFailure: (QRScannerError) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        QRScannerViewController(onResult: onResult, onSetupFailure: onSetupFailure)
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    QRScannerView(onResult: { _ in }, onClose: {})
}
