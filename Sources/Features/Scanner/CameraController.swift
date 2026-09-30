import AVFoundation
import SwiftUI
import Vision

/// Runs the capture session and reports the nine averaged colours inside
/// the on-screen guide, refined by Vision's rectangle detection.
@Observable
@MainActor
final class CameraController {

    enum Status { case unknown, unavailable, denied, running }

    private(set) var status: Status = .unknown
    /// Latest colours of the 3×3 grid, row by row as seen on screen.
    private(set) var samples: [RGB] = []
    /// Whether Vision found the cube face inside the guide.
    private(set) var locked = false

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let sampler = FrameSampler()
    @ObservationIgnored private let queue = DispatchQueue(label: "dev.ividi.irubikcube.camera")

    func start() async {
        guard status != .running else { return }
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            status = .unavailable
            return
        }
        var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard authorized else {
            status = .denied
            return
        }
        configure()
        sampler.onSamples = { [weak self] samples, locked in
            Task { @MainActor in
                self?.samples = samples
                self?.locked = locked
            }
        }
        // AVCaptureSession is documented as safe to start from a background queue.
        nonisolated(unsafe) let session = self.session
        queue.async { session.startRunning() }
        status = .running
    }

    func stop() {
        nonisolated(unsafe) let session = self.session
        queue.async { session.stopRunning() }
    }

    private func configure() {
        guard session.inputs.isEmpty,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(sampler, queue: DispatchQueue(label: "dev.ividi.irubikcube.frames"))
        if session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
    }
}

/// Averages the guide cells of each frame, off the main thread.
private final class FrameSampler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onSamples: (@Sendable ([RGB], Bool) -> Void)?
    private var frameCount = 0

    /// The guide: a centred square covering 70% of the frame's width.
    static let guideFraction = 0.7

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount % 3 == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = Double(CVPixelBufferGetWidth(buffer))
        let height = Double(CVPixelBufferGetHeight(buffer))
        let side = width * Self.guideFraction
        let guide = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)

        // Vision works in normalised coordinates with the origin at the bottom left.
        var corners = (tl: CGPoint(x: guide.minX, y: guide.minY), tr: CGPoint(x: guide.maxX, y: guide.minY),
                       bl: CGPoint(x: guide.minX, y: guide.maxY), br: CGPoint(x: guide.maxX, y: guide.maxY))
        var locked = false
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.75
        request.maximumAspectRatio = 1
        request.minimumSize = 0.35
        request.maximumObservations = 1
        request.regionOfInterest = CGRect(x: guide.minX / width - 0.05, y: 1 - guide.maxY / height - 0.05,
                                          width: guide.width / width + 0.1, height: guide.height / height + 0.1)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        if (try? handler.perform([request])) != nil, let quad = request.results?.first, quad.confidence > 0.6 {
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * width, y: (1 - p.y) * height) }
            corners = (point(quad.topLeft), point(quad.topRight), point(quad.bottomLeft), point(quad.bottomRight))
            locked = true
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        var samples: [RGB] = []
        for row in 0..<3 {
            for col in 0..<3 {
                let u = (Double(col) + 0.5) / 3
                let v = (Double(row) + 0.5) / 3
                let top = CGPoint(x: corners.tl.x + (corners.tr.x - corners.tl.x) * u, y: corners.tl.y + (corners.tr.y - corners.tl.y) * u)
                let bottom = CGPoint(x: corners.bl.x + (corners.br.x - corners.bl.x) * u, y: corners.bl.y + (corners.br.y - corners.bl.y) * u)
                let center = CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
                let radius = Int(side / 3 * 0.18)
                var sum = (r: 0.0, g: 0.0, b: 0.0)
                var count = 0.0
                for dy in stride(from: -radius, through: radius, by: 2) {
                    for dx in stride(from: -radius, through: radius, by: 2) {
                        let x = Int(center.x) + dx
                        let y = Int(center.y) + dy
                        guard x >= 0, y >= 0, x < Int(width), y < Int(height) else { continue }
                        let offset = y * bytesPerRow + x * 4
                        sum.b += Double(pixels[offset])
                        sum.g += Double(pixels[offset + 1])
                        sum.r += Double(pixels[offset + 2])
                        count += 1
                    }
                }
                let n = max(count, 1) * 255
                samples.append(RGB(r: sum.r / n, g: sum.g / n, b: sum.b / n))
            }
        }
        onSamples?(samples, locked)
    }
}

/// Live camera picture.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer?.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}
