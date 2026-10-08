//
//  ImportCamera.swift
//  RecipeScalerNative
//
//  Spec 080 — live camera cell and photo capture for the Photo tab grid of
//  `ImportRecipeSheet`. Ported from scrapp's `CameraPreview` / `CameraCapture`.
//

import AVFoundation
import SwiftUI
import UIKit

/// The back camera's live feed for the first grid cell, as in Telegram. Runs only when camera
/// access was already given: the Photo tab must not ask for the camera just by opening.
@MainActor
@Observable
final class ImportCameraPreview {
    /// True once the session runs, so the cell doesn't flash black before the first frame.
    private(set) var isLive = false
    @ObservationIgnored private let session = AVCaptureSession()
    /// One preview for the sheet's lifetime, tied to the session before it starts: attaching a layer
    /// to a running session blocked the main thread for ~9 s on an iPhone.
    @ObservationIgnored let previewView = ImportPreviewLayerView()
    @ObservationIgnored private let queue = DispatchQueue(label: "app.recipe-scaler.import-camera-preview")
    @ObservationIgnored private var configured = false
    /// Stop can come before the session finishes starting; then the feed must not show.
    @ObservationIgnored private var wanted = false

    init() {
        previewView.previewLayer.session = session
        previewView.previewLayer.videoGravity = .resizeAspectFill
    }

    func start() {
        wanted = true
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        let session = session
        let configure = !configured
        configured = true
        queue.async {
            if configure, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.beginConfiguration()
                session.sessionPreset = .medium
                session.addInput(input)
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
            let running = session.isRunning
            DispatchQueue.main.async {
                guard self.wanted, running else { return }
                withAnimation(.easeOut(duration: 0.25)) { self.isLive = true }
            }
        }
    }

    func stop() {
        wanted = false
        isLive = false
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }
}

final class ImportPreviewLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    // swiftlint:disable:next force_cast
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// Puts the model's preview view in the cell, so the cell can be rebuilt without touching the session.
struct ImportCameraPreviewView: UIViewRepresentable {
    let preview: UIView

    func makeUIView(context: Context) -> Slot {
        Slot(preview: preview)
    }

    func updateUIView(_ slot: Slot, context: Context) {}

    /// The slot that comes on screen takes the preview: while rebuilding a cell, SwiftUI can briefly
    /// keep the old copy around, and claiming on creation let that copy walk away with the feed.
    final class Slot: UIView {
        private let preview: UIView

        init(preview: UIView) {
            self.preview = preview
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, preview.superview !== self else { return }
            addSubview(preview)
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if preview.superview === self { preview.frame = bounds }
        }
    }
}

/// The system camera over the import sheet. Hands back JPEG data of the shot.
@MainActor
final class ImportCameraCapture: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private var onCapture: ((Data) -> Void)?
    private var onCancel: (() -> Void)?
    private weak var picker: UIImagePickerController?

    func present(onCancel: @escaping () -> Void, onCapture: @escaping (Data) -> Void) {
        guard picker == nil, let top = UIApplication.topViewController() else { return }
        let picker = UIImagePickerController()
        // The simulator has no camera; the library stands in so the flow can be tried there.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = self
        // Over, not full screen: `.fullScreen` takes the sheet out of the window, and its `onAppear`
        // (which resets the import state) ran again on the way back, dropping the shot.
        picker.modalPresentationStyle = .overFullScreen
        self.onCapture = onCapture
        self.onCancel = onCancel
        self.picker = picker
        top.present(picker, animated: true)
    }

    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = info[.originalImage] as? UIImage
        MainActor.assumeIsolated {
            let onCapture = onCapture
            let onCancel = onCancel
            finish(picker) {
                guard let image else {
                    onCancel?()
                    return
                }
                Task {
                    let jpeg = await Task.detached(priority: .userInitiated) {
                        image.jpegData(compressionQuality: 0.9)
                    }.value
                    if let jpeg { onCapture?(jpeg) } else { onCancel?() }
                }
            }
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        MainActor.assumeIsolated {
            finish(picker, then: onCancel)
        }
    }

    private func finish(_ picker: UIImagePickerController, then completion: (() -> Void)? = nil) {
        onCapture = nil
        onCancel = nil
        picker.dismiss(animated: true, completion: completion)
    }
}

extension UIApplication {
    /// The controller on top of the key window, for UIKit presentations from SwiftUI.
    static func topViewController() -> UIViewController? {
        let window = shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
