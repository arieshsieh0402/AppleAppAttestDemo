# ApptestDemo - iOS App Attestation Demo

## 專案介紹

ApptestDemo 是一個 demo **App Attestation** 機制以及設備驗證的完整流程的 iOS App。

### 核心功能

此應用涉及以下概念：

- **設備註冊 (Device Registration)**: 使用 Apple 的 `DeviceCheck` framework 生成硬體綁定的密鑰
- **簽名驗證 (Signature Verification)**: 使用生成的密鑰對請求進行簽名和驗證
- **重放攻擊防護 (Replay Attack Prevention)**: 展示 App Attestation 如何防止攻擊者重複使用已驗證的請求

## 系統要求

App Attestation 只在實體設備上支援，模擬器不支援，故需執行於實體 iPhone 或 iPad（支援 App Attest 的設備）。

## 使用方式

### 1. 開啟專案

```bash
cd ApptestDemo
open ApptestDemo.xcodeproj
```

### 2. 設置伺服器 URL

編輯 [ViewController.swift](ApptestDemo/ViewController.swift) 中的以下行：

```swift
private let serverURL = "YOUR_SERVER_URL"
```

將 `YOUR_SERVER_URL` 替換為你的後端伺服器地址。

### 3. 在實體設備上運行

1. 選擇實體設備作為 build target
2. 按 ⌘+R 運行應用

### 4. 應用使用流程

#### 步驟 1: 註冊設備

- 點擊 **"1. 註冊設備 (Register)"** 按鈕
- 應用會生成硬體綁定的密鑰
- Key ID 會被保存在 UserDefaults（實務上應使用 Keychain）

#### 步驟 2: 執行轉帳

- 點擊 **"2. 執行轉帳 (Transfer)"** 按鈕
- 應用會：
  - 建立轉帳請求
  - 使用設備密鑰對請求簽名
  - 傳送到伺服器進行驗證

#### 步驟 3: 模擬重放攻擊

- 點擊 **"3. 😈 模擬重放攻擊 (Replay Attack)"** 按鈕
- 應用會嘗試重複使用之前合法的簽名請求
- 伺服器應該拒絕此請求，因為它已被使用過

#### 清除本地 Key ID

- 點擊 **"清除本地 Key ID"** 按鈕重新開始流程


## 📝 工作流程圖

```
┌─────────────┐
│  使用者啟動 │
└──────┬──────┘
       │
       ▼
┌──────────────────────┐
│ 1. 寄存器裝置        │
│  ✓ 生成硬體K        │
│  ✓ 保存 Key ID      │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ 2. 執行轉帳          │
│  ✓ 建立請求          │
│  ✓ 使用密鑰簽名      │
│  ✓ 發送到伺服器      │
│  ✓ 伺服器驗證簽名    │
└──────┬───────────────┘
       │
       ▼ (防止攻擊)
┌──────────────────────┐
│ 3. 重放攻擊防護      │
│  ✗ 拒絕重複請求      │
│  ✗ 驗證失敗          │
└──────────────────────┘
```

## 相關資源

- [Apple DeviceCheck Documentation](https://developer.apple.com/documentation/devicecheck)
- [App Attest API Reference](https://developer.apple.com/documentation/devicecheck/dcappattest)
- [CryptoKit Framework](https://developer.apple.com/documentation/cryptokit)
