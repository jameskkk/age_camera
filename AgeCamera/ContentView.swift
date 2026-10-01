import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var ageAdjustment = 0.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.055, green: 0.071, blue: 0.11), Color(red: 0.10, green: 0.12, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                cameraStage
                controlPanel
                    .frame(width: 320)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .alert("AgeCamera", isPresented: Binding(
            get: { camera.lastError != nil },
            set: { if !$0 { camera.clearError() } }
        )) {
            Button("好", role: .cancel) { camera.clearError() }
        } message: {
            Text(camera.lastError ?? "")
        }
    }

    private var cameraStage: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AgeCamera")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("USB 相機 · 人臉偵測 · 年齡風格")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPill
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.72))

                if let image = camera.isReviewing ? camera.processedImage : camera.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(2)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 58, weight: .thin))
                            .foregroundStyle(.secondary)
                        Text(camera.statusText)
                            .foregroundStyle(.secondary)
                    }
                }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .shadow(color: .black.opacity(0.35), radius: 28, y: 16)

            Text(camera.isReviewing ? "拖動右側滑桿調整臉部年齡風格" : "綠色方框表示已偵測到人臉")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("控制台", systemImage: "slider.horizontal.3")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                Text("相機來源")
                    .font(.headline)

                Picker("相機來源", selection: Binding(
                    get: { camera.selectedDeviceID },
                    set: { camera.selectCamera(id: $0) }
                )) {
                    if camera.devices.isEmpty {
                        Text("找不到相機").tag("")
                    }
                    ForEach(camera.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Button("重新掃描 USB 相機") {
                    camera.refreshDevices()
                }
                .buttonStyle(.link)
            }

            Divider()

            if camera.isReviewing {
                ageControls
            } else {
                liveControls
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("隱私優先", systemImage: "lock.shield")
                    .font(.subheadline.bold())
                Text("人臉偵測與影像處理都在這台 Mac 上完成，不會上傳照片。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(26)
        .background(.ultraThinMaterial)
    }

    private var liveControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("準備拍攝")
                    .font(.headline)
                Text("讓臉部完整出現在畫面中，偵測框出現後即可拍照。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                ageAdjustment = 0
                camera.takePhoto()
            } label: {
                Label("拍照", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.26, green: 0.80, blue: 0.58))
            .disabled(!camera.isRunning || camera.previewImage == nil)
        }
    }

    private var ageControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("年齡調整")
                    .font(.headline)
                Text(ageLabel)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(ageAdjustment < 0 ? .cyan : ageAdjustment > 0 ? .orange : .white)
            }

            HStack {
                Label("年輕", systemImage: "sparkles")
                Spacer()
                Label("年老", systemImage: "hourglass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Slider(value: $ageAdjustment, in: -50...50, step: 1)
                .onChange(of: ageAdjustment) { _, newValue in
                    camera.applyAgeAdjustment(newValue)
                }

            Button("回到原始年齡") {
                ageAdjustment = 0
                camera.applyAgeAdjustment(0)
            }
            .buttonStyle(.link)

            Divider()

            Button {
                camera.savePhoto()
            } label: {
                Label("儲存照片", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                ageAdjustment = 0
                camera.retake()
            } label: {
                Label("重新拍照", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(camera.faceCount > 0 ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(camera.statusText)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private var ageLabel: String {
        if ageAdjustment < -1 { return "年輕 \(Int(abs(ageAdjustment)))" }
        if ageAdjustment > 1 { return "年老 +\(Int(ageAdjustment))" }
        return "原始"
    }
}

#Preview {
    ContentView()
        .frame(width: 1180, height: 760)
}
