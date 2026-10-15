import AVFoundation
import SwiftUI
import UIKit

/// The camera, looking for the QR code the Mac shows. It reads codes and nothing else: no photos, no video.
struct QRScannerView: UIViewRepresentable {
  var active: Bool
  var onCode: (String) -> Void
  var onDenied: () -> Void

  final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
  }

  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.backgroundColor = .black
    view.previewLayer.videoGravity = .resizeAspectFill
    context.coordinator.attach(to: view)
    return view
  }

  func updateUIView(_ view: PreviewView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.setRunning(active)
  }

  static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
    coordinator.setRunning(false)
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var parent: QRScannerView
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "brb.scan")
    private var configured = false
    private var wanted = false
    private var lastCode = ""
    private var lastAt = Date.distantPast

    init(_ parent: QRScannerView) { self.parent = parent }

    func attach(to view: PreviewView) {
      view.previewLayer.session = session
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
        configure()
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
          DispatchQueue.main.async {
            if granted { self.configure() } else { self.parent.onDenied() }
          }
        }
      default:
        DispatchQueue.main.async { self.parent.onDenied() }
      }
    }

    private func configure() {
      queue.async { [self] in
        guard !configured, let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
        else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        configured = true
        if wanted { session.startRunning() }
      }
    }

    func setRunning(_ on: Bool) {
      wanted = on
      queue.async { [self] in
        guard configured else { return }
        if on && !session.isRunning {
          session.startRunning()
        } else if !on && session.isRunning {
          session.stopRunning()
        }
      }
    }

    func metadataOutput(
      _ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection
    ) {
      guard let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
      // The same code is seen many times a second; pass it on once, again only after a pause.
      if code == lastCode && Date().timeIntervalSince(lastAt) < 3 { return }
      lastCode = code
      lastAt = Date()
      parent.onCode(code)
    }
  }
}
