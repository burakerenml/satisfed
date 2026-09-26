//
//  SnapCamera.swift
//  Shiphaton App
//
//  Camera plumbing for the snap-first log flow: a small session controller,
//  a SwiftUI preview surface, and image downscaling for storage.
//

import SwiftUI
import UIKit
import Combine
import AVFoundation

// MARK: - Session controller

/// Owns the capture session for the snap step. Publishes a simple phase so
/// the UI can show the viewfinder, a permission nudge, or the no-camera
/// fallback (simulator) without touching AVFoundation itself.
final class SnapCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum Phase {
        case loading
        case ready
        case denied
    }

    @Published var phase: Phase = .loading
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    /// Called on the main actor with the downscaled capture.
    var onCapture: ((UIImage) -> Void)?
    /// Called on the main actor when the shutter fired but no usable
    /// photo came back, so the screen can say so instead of sitting still.
    var onCaptureFailed: (() -> Void)?

    /// Whether this device has a camera to show at all. The simulator
    /// doesn't; the viewfinder stays dark there by design.
    private(set) var hasCamera = false

    func prepare() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                phase = .denied
                return
            }
        case .denied, .restricted:
            phase = .denied
            return
        default:
            break
        }

        // No camera (simulator): still show the viewfinder — it stays black,
        // and the library/type paths remain available.
        if session.inputs.isEmpty,
           let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device) {
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
        }
        hasCamera = !session.inputs.isEmpty
        phase = .ready
        start()
    }

    /// Opens this app's page in Settings, where camera access lives.
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func start() {
        guard phase == .ready, !session.isRunning else { return }
        let session = session
        Task.detached(priority: .userInitiated) {
            session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        let session = session
        Task.detached {
            session.stopRunning()
        }
    }

    func snap() {
        // The connection guard keeps the shutter a no-op where there's no
        // camera device (simulator) instead of raising.
        guard phase == .ready, photoOutput.connection(with: .video) != nil else { return }
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)?.scaledDown(to: 1200) else {
            Task { @MainActor in self.onCaptureFailed?() }
            return
        }
        Task { @MainActor in
            self.onCapture?(image)
        }
    }
}

// MARK: - Preview surface

/// The live viewfinder — an AVCaptureVideoPreviewLayer-backed UIView.
struct CameraViewfinder: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Downscaling

extension UIImage {
    /// Storage-friendly copy no larger than `maxDimension` on its long side.
    func scaledDown(to maxDimension: CGFloat) -> UIImage {
        let longSide = max(size.width, size.height)
        guard longSide > maxDimension else { return self }
        let scale = maxDimension / longSide
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
