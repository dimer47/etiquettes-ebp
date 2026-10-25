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
                Text("Placez le code-barres dans le cadre. Touchez l’image pour refaire la mise au point.")
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
    private let sessionQueue = DispatchQueue(label: "ProductLabels.camera")
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private var didScan = false
    private var cameraDevice: AVCaptureDevice?
    private var focusGeneration = 0

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
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusAtTap(_:))))
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
        // A virtual rear camera lets iOS switch between its physical lenses
        // as focus distance and light change. Prefer a device with ultrawide
        // support for close barcode scans, then fall back to a single lens.
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera,
            .builtInDualCamera, .builtInWideAngleCamera
        ]
        guard let device = deviceTypes.compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) }).first,
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            DispatchQueue.main.async { [onError] in onError(NSLocalizedString("Caméra indisponible sur cet appareil.", comment: "Scanner error")) }
            return
        }
        let output = AVCaptureMetadataOutput()
        cameraDevice = device
        do {
            try device.lockForConfiguration()
            if device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera,
               let wideZoom = device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue {
                // Start with the wide-angle field of view used by the old
                // scanner. At this threshold the ultrawide is also eligible
                // when its shorter focus distance helps with a close code.
                device.videoZoomFactor = min(max(CGFloat(wideZoom), device.minAvailableVideoZoomFactor),
                                             device.maxAvailableVideoZoomFactor)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            // The scanner can still run with the camera's current focus mode.
        }
        session.beginConfiguration()
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [onError] in onError(NSLocalizedString("La lecture des codes-barres est indisponible.", comment: "Scanner error")) }
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean13]
        session.commitConfiguration()
        session.startRunning()
    }

    @objc private func focusAtTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: view)
        let point = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
        let ring = UIView(frame: CGRect(x: location.x - 30, y: location.y - 30, width: 60, height: 60))
        ring.layer.cornerRadius = 30
        ring.layer.borderWidth = 2
        ring.layer.borderColor = UIColor.systemYellow.cgColor
        ring.isUserInteractionEnabled = false
        view.addSubview(ring)
        UIView.animate(withDuration: 0.55, delay: 0.2, options: [], animations: { ring.alpha = 0 }) { _ in
            ring.removeFromSuperview()
        }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            self.focusGeneration += 1
            let generation = self.focusGeneration
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { return }
            // A one-shot focus reacts to the tap; then keep tracking as the
            // user moves the phone nearer or farther from the barcode.
            self.sessionQueue.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.focusGeneration == generation,
                      device.isFocusModeSupported(.continuousAutoFocus) else { return }
                do {
                    try device.lockForConfiguration()
                    device.focusMode = .continuousAutoFocus
                    device.unlockForConfiguration()
                } catch { return }
            }
        }
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
