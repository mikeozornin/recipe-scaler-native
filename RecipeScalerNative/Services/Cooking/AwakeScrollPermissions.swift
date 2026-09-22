import AVFoundation
import Foundation
import Speech

enum AwakeScrollPermissions {
    static func currentSnapshot() -> AwakeScrollPermissionSnapshot {
        let mic = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        return AwakeScrollPermissionSnapshot(
            micGranted: mic == .granted,
            speechGranted: speech == .authorized,
            cameraGranted: camera == .authorized,
            micDenied: mic == .denied,
            speechDenied: speech == .denied,
            cameraDenied: camera == .denied,
            speechRestricted: speech == .restricted,
            cameraRestricted: camera == .restricted
        )
    }

    static func request(voice: Bool, camera: Bool) async -> AwakeScrollPermissionSnapshot {
        if voice {
            await requestMic()
            await requestSpeech()
        }
        if camera {
            await requestCamera()
        }
        return currentSnapshot()
    }

    private static func requestMic() async {
        guard AVAudioApplication.shared.recordPermission == .undetermined else { return }
        _ = await AVAudioApplication.requestRecordPermission()
    }

    private static func requestSpeech() async {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                cont.resume()
            }
        }
    }

    private static func requestCamera() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }
}
