# AgeCamera

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-111827)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![Xcode](https://img.shields.io/badge/Xcode-27-blue)

AgeCamera 是一套以 SwiftUI 開發的原生 macOS 拍照應用程式。它能使用 Mac 內建相機或 AVFoundation 可辨識的 USB／UVC Camera，即時偵測人臉、拍攝照片，並針對臉部套用年輕或年老的視覺風格。

所有人臉偵測與影像處理都在使用者的 Mac 上完成，不需要網路連線，也不會上傳照片。

## 功能

- 列出並切換 Mac 內建相機與外接 USB Camera
- 即時相機預覽
- 使用 Vision 即時偵測一張或多張人臉
- 在預覽畫面標示偵測到的人臉
- 擷取目前相機畫面
- 以滑桿調整年輕／年老視覺效果
- 僅在人臉區域套用 Core Image 效果，保留背景內容
- 將處理後的照片儲存為 PNG
- 使用 App Sandbox 與使用者選擇的儲存位置

## 系統需求

- macOS 14.0 或更新版本
- Xcode 16 或更新版本；目前專案已使用 Xcode 27 驗證
- 支援 macOS 的內建相機或 USB／UVC Camera
- Apple Silicon 或 Intel Mac

## 快速開始

```bash
git clone https://github.com/jameskkk/age_camera.git
cd age_camera
open AgeCamera.xcodeproj
```

在 Xcode 中：

1. 選擇 `AgeCamera` scheme。
2. 將執行目標設為 `My Mac`。
3. 按下 Run，或使用快捷鍵 `Command + R`。
4. 第一次執行時，允許 AgeCamera 使用相機。

若曾拒絕相機權限，可至「系統設定 → 隱私權與安全性 → 相機」重新開啟。

## 使用方式

1. 在右側「相機來源」選擇內建或 USB Camera。
2. 將臉部完整置於畫面中；綠色方框代表人臉已被偵測。
3. 按下「拍照」。
4. 將年齡滑桿向左移動以套用年輕風格，或向右移動以套用年老風格。
5. 按下「儲存照片」，選擇位置並輸出 PNG。
6. 按下「重新拍照」即可回到相機預覽。

若外接相機沒有出現在選單中，請確認相機已連接且未被其他程式獨占，然後按下「重新掃描 USB 相機」。

## 技術架構

| 元件 | 用途 |
| --- | --- |
| SwiftUI | macOS 使用者介面與狀態呈現 |
| AVFoundation | 相機搜尋、切換與即時影像擷取 |
| Vision | `VNDetectFaceRectanglesRequest` 人臉偵測 |
| Core Image | 臉部遮罩、膚質、色彩、銳利度與光影效果 |
| AppKit | macOS 圖像轉換與儲存面板 |

主要程式檔案：

- `CameraManager.swift`：相機權限、裝置管理、影格擷取與拍照流程。
- `AgeEffectProcessor.swift`：人臉偵測、臉部遮罩和年齡風格處理。
- `ContentView.swift`：相機畫面、控制面板與儲存操作。
- `AgeCamera.entitlements`：相機與使用者選擇檔案的 Sandbox 權限。

## 命令列建置

```bash
xcodebuild \
  -project AgeCamera.xcodeproj \
  -scheme AgeCamera \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

如果系統的 active developer directory 指向 Command Line Tools，可先指定完整 Xcode：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## 權限與隱私

專案包含以下設定：

- `NSCameraUsageDescription`：說明相機用途。
- `com.apple.security.device.camera`：允許 Sandbox App 使用相機。
- `com.apple.security.files.user-selected.read-write`：只允許寫入使用者在儲存面板選擇的位置。

AgeCamera 不包含分析服務、廣告 SDK 或網路上傳程式碼。

## 目前限制

目前的年齡調整是完全離線的非生成式影像效果，會調整臉部膚質、色彩、對比、銳利度與光影，但不會生成新的五官結構。若需要更寫實的皺紋、髮色或臉部輪廓變化，可在 `AgeEffectProcessor` 後方接入專用的 Core ML 年齡轉換模型。

相機可用解析度、幀率與色彩表現取決於相機硬體及其 macOS 驅動支援。

## 後續規劃

- Core ML 寫實年齡轉換模型
- 前後對照與分割預覽
- JPEG／HEIC 輸出格式
- 倒數拍照與鍵盤快捷鍵
- 多人臉個別年齡調整

## 開發與貢獻

歡迎透過 Issue 回報問題或提出功能建議。提交 Pull Request 前，請先確認專案能在 `My Mac` 目標成功建置，且不會將測試照片或個人影像加入版本控制。
