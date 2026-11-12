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
    private let metadataOutput = AVCaptureMetadataOutput()
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private var didScan = false
    private var cameraDevice: AVCaptureDevice?
    private var focusGeneration = 0
    // Même gabarit que le cadre blanc dessiné en SwiftUI (RoundedRectangle
    // 290x140 centré). La zone réellement scannée doit coller à ce repère.
    private static let scanFrameSize = CGSize(width: 290, height: 140)

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
        updateRectOfInterest()
    }

    // Limite la détection au cadre affiché au lieu de toute l'image : le
    // détecteur ne traite plus que ~15 % de la surface, ce qui accélère
    // nettement l'accrochage du code-barres. metadataOutput.rectOfInterest
    // est en coordonnées normalisées orientées capteur ; on le dérive du
    // rectangle du cadre via le previewLayer, qui doit déjà avoir sa taille
    // finale (d'où l'appel depuis viewDidLayoutSubviews).
    private func updateRectOfInterest() {
        let size = Self.scanFrameSize
        let frameRect = CGRect(
            x: view.bounds.midX - size.width / 2,
            y: view.bounds.midY - size.height / 2,
            width: size.width, height: size.height
        )
        guard frameRect.width > 0, frameRect.height > 0,
              previewLayer.bounds.width > 0, previewLayer.bounds.height > 0 else { return }
        let rect = previewLayer.metadataOutputRectConverted(fromLayerRect: frameRect)
        sessionQueue.async { [metadataOutput] in metadataOutput.rectOfInterest = rect }
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
        let output = metadataOutput
        cameraDevice = device
        do {
            try device.lockForConfiguration()
            if device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera,
               let wideZoom = device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue {
                // On se cale juste AU-DESSUS du seuil de bascule ultrawide
                // (x1.05) au lieu de pile dessus : iOS reste verrouillé sur le
                // grand-angle pour un code proche, sans hésiter entre deux
                // objectifs — l'hésitation faisait partie de la lenteur
                // ressentie. Le champ reste quasi identique à l'ancien.
                let stableZoom = CGFloat(wideZoom) * 1.05
                device.videoZoomFactor = min(max(stableZoom, device.minAvailableVideoZoomFactor),
                                             device.maxAvailableVideoZoomFactor)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            // Un code-barres est toujours lu de près : restreindre la plage
            // d'autofocus au proche fait converger la mise au point beaucoup
            // plus vite (l'objectif n'explore plus toute la course jusqu'à
            // l'infini).
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            device.unlockForConfiguration()
        } catch {
            // The scanner can still run with the camera's current focus mode.
        }
        session.beginConfiguration()
        // 720p suffit largement pour un EAN-13 et allège fortement le travail
        // du détecteur par rapport au .high par défaut (souvent 1080p/4K) :
        // moins de pixels à analyser par image → détection plus réactive.
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
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
        // Le cadre a déjà pu être mis en page avant la fin de cette config
        // asynchrone : on (re)pose la zone d'intérêt une fois la session prête.
        DispatchQueue.main.async { [weak self] in self?.updateRectOfInterest() }
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
                // On conserve la restriction au proche posée à la config : le
                // tap ne doit pas relancer un balayage de focus jusqu'à l'infini.
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near
                }
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
