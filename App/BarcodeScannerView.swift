import AVFoundation
import SwiftUI

struct BarcodeScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed: Bool?
    @State private var cameraError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if cameraAllowed == true, cameraError == nil {
                    BarcodeCameraView(onScan: onScan, onError: { cameraError = $0 })
                        .ignoresSafeArea(edges: .bottom)
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 290, height: 140)
                        .allowsHitTesting(false)
                } else if let cameraError {
                    Text(cameraError).foregroundStyle(.white).padding()
                } else if cameraAllowed == false {
                    VStack(spacing: 12) {
                        Text("Autorisez la caméra pour scanner un EAN-13.")
                            .multilineTextAlignment(.center)
                        Button("Ouvrir les réglages iPhone") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle("Scanner un EAN-13")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fermer") { dismiss() } }
            .safeAreaInset(edge: .bottom) {
                Text("Placez le code-barres dans le cadre. Le numéro sera rempli automatiquement.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.8))
            }
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: cameraAllowed = true
                case .notDetermined: cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
                default: cameraAllowed = false
                }
            }
        }
    }
}

private struct BarcodeCameraView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCameraController {
        BarcodeCameraController(onScan: onScan, onError: onError)
    }

    func updateUIViewController(_ controller: BarcodeCameraController, context: Context) {}
}

private final class BarcodeCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ProductLabel5890.camera")
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private var didScan = false

    init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onScan = onScan
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
        view.layer.addSublayer(previewLayer)
        sessionQueue.async { [weak self] in self?.configureAndStart() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    private func configureAndStart() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            DispatchQueue.main.async { [onError] in onError("Caméra indisponible sur cet appareil.") }
            return
        }
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [onError] in onError("La lecture des codes-barres est indisponible.") }
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean13]
        session.commitConfiguration()
        session.startRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didScan,
              let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first,
              (try? EAN13.completed(code)) == code else { return }
        didScan = true
        onScan(code)
    }
}
