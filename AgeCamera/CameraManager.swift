import AppKit
import AVFoundation
import CoreImage

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var capturedImage: NSImage?
    @Published private(set) var processedImage: NSImage?
    @Published private(set) var devices: [CameraDeviceInfo] = []
    @Published var selectedDeviceID: String = ""
    @Published private(set) var faceCount = 0
    @Published private(set) var statusText = "正在準備相機…"
    @Published private(set) var isRunning = false
    @Published private(set) var isReviewing = false
    @Published private(set) var lastError: String?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.agecamera.capture.session")
    private let videoQueue = DispatchQueue(label: "com.agecamera.capture.video", qos: .userInitiated)
    private let frameLock = NSLock()
    private var activeInput: AVCaptureDeviceInput?
    private var latestFrame: CIImage?
    private var latestFaces: [CGRect] = []
    private var capturedFrame: CIImage?
    private var capturedFaces: [CGRect] = []
    private var lastAnalysisTime = CFAbsoluteTimeGetCurrent()
    private var cachedFaces: [CGRect] = []

    override init() {
        super.init()
        refreshDevices()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndStart()
                } else {
                    self.publishError("未取得相機權限。請到「系統設定 → 隱私權與安全性 → 相機」允許 AgeCamera。")
                }
            }
        default:
            publishError("相機權限已關閉。請到「系統設定 → 隱私權與安全性 → 相機」允許 AgeCamera。")
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                self.statusText = "相機已停止"
            }
        }
    }

    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let found = discovery.devices.map { CameraDeviceInfo(id: $0.uniqueID, name: $0.localizedName) }

        DispatchQueue.main.async {
            self.devices = found
            if self.selectedDeviceID.isEmpty || !found.contains(where: { $0.id == self.selectedDeviceID }) {
                self.selectedDeviceID = found.first?.id ?? ""
            }
            if found.isEmpty {
                self.statusText = "找不到相機，請接上 USB Camera"
            }
        }
    }

    func selectCamera(id: String) {
        guard !id.isEmpty else { return }
        selectedDeviceID = id
        configureAndStart(deviceID: id)
    }

    func takePhoto() {
        frameLock.lock()
        let frame = latestFrame
        let faces = latestFaces
        frameLock.unlock()

        guard let frame else {
            publishError("目前還沒有可拍攝的畫面。")
            return
        }

        capturedFrame = frame
        capturedFaces = faces
        let image = AgeEffectProcessor.nsImage(from: frame)
        DispatchQueue.main.async {
            self.capturedImage = image
            self.processedImage = image
            self.isReviewing = true
            self.faceCount = faces.count
            self.statusText = faces.isEmpty ? "已拍照，但未偵測到人臉" : "已偵測到 \(faces.count) 張人臉"
        }
    }

    func applyAgeAdjustment(_ adjustment: Double) {
        guard let frame = capturedFrame else { return }
        let faces = capturedFaces

        videoQueue.async { [weak self] in
            let result = AgeEffectProcessor.apply(to: frame, faces: faces, adjustment: adjustment)
            let image = AgeEffectProcessor.nsImage(from: result)
            DispatchQueue.main.async {
                self?.processedImage = image
            }
        }
    }

    func retake() {
        capturedFrame = nil
        capturedFaces = []
        capturedImage = nil
        processedImage = nil
        isReviewing = false
        statusText = "相機已就緒"
    }

    func savePhoto() {
        guard let image = processedImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            publishError("無法產生照片檔案。")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "AgeCamera-\(Self.fileTimestamp()).png"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try pngData.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    self?.statusText = "照片已儲存：\(url.lastPathComponent)"
                }
            } catch {
                self?.publishError("儲存照片失敗：\(error.localizedDescription)")
            }
        }
    }

    func clearError() {
        lastError = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isReviewing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastAnalysisTime > 0.16 {
            cachedFaces = AgeEffectProcessor.detectFaces(in: frame)
            lastAnalysisTime = now
        }

        frameLock.lock()
        latestFrame = frame
        latestFaces = cachedFaces
        frameLock.unlock()

        let display = AgeEffectProcessor.previewWithFaceFrames(frame, faces: cachedFaces)
        guard let image = AgeEffectProcessor.nsImage(from: display) else { return }
        let count = cachedFaces.count

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isReviewing else { return }
            self.previewImage = image
            self.faceCount = count
            self.statusText = count == 0 ? "請將臉部置於畫面中央" : "偵測到 \(count) 張人臉"
        }
    }

    private func configureAndStart(deviceID: String? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let requestedID = deviceID ?? self.selectedDeviceID
            let device = AVCaptureDevice(uniqueID: requestedID)
                ?? AVCaptureDevice.default(for: .video)

            guard let device else {
                self.publishError("找不到可用的相機，請確認 USB Camera 已連接。")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                self.session.sessionPreset = .high

                if let oldInput = self.activeInput {
                    self.session.removeInput(oldInput)
                }
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.publishError("無法使用所選的相機。")
                    return
                }
                self.session.addInput(input)
                self.activeInput = input

                if self.session.outputs.isEmpty {
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    output.setSampleBufferDelegate(self, queue: self.videoQueue)
                    if self.session.canAddOutput(output) {
                        self.session.addOutput(output)
                    }
                }

                self.session.commitConfiguration()
                if !self.session.isRunning {
                    self.session.startRunning()
                }

                DispatchQueue.main.async {
                    self.selectedDeviceID = device.uniqueID
                    self.isRunning = true
                    self.lastError = nil
                    self.statusText = "相機已就緒"
                }
            } catch {
                self.publishError("啟動相機失敗：\(error.localizedDescription)")
            }
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.lastError = message
            self.statusText = message
            self.isRunning = false
        }
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
