//
//  ViewController.swift
//  ApptestDemo
//
//  Created by Aries Hsieh on 2026/2/15.
//

import UIKit
import DeviceCheck
import CryptoKit

class ViewController: UIViewController {
    
    private let serverURL = "YOUR_SERVER_URL"
    private let keyIdStorageKey = "AppAttestKeyId"
    
    // 😈 用來儲存被攔截的合法請求
    private var interceptedRequestBody: [String: Any]?
    
    private let logTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.backgroundColor = .systemGray6
        tv.font = .systemFont(ofSize: 12)
        return tv
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        let registerBtn = UIButton(type: .system)
        registerBtn.setTitle("1. 註冊設備 (Register)", for: .normal)
        registerBtn.addAction(UIAction { [weak self] _ in
            Task { await self?.registerDevice() }
        }, for: .touchUpInside)
        
        let transferBtn = UIButton(type: .system)
        transferBtn.setTitle("2. 執行轉帳 (Transfer)", for: .normal)
        transferBtn.addAction(UIAction { [weak self] _ in
            Task { await self?.performTransfer() }
        }, for: .touchUpInside)
        
        let clearBtn = UIButton(type: .system)
        clearBtn.setTitle("清除本地 Key ID", for: .normal)
        clearBtn.setTitleColor(.systemRed, for: .normal)
        clearBtn.addAction(UIAction { [weak self] _ in
            UserDefaults.standard.removeObject(forKey: self?.keyIdStorageKey ?? "")
            self?.log("已清除本地 Key ID")
        }, for: .touchUpInside)
        
        let replayBtn = UIButton(type: .system)
        replayBtn.setTitle("3. 😈 模擬重放攻擊 (Replay Attack)", for: .normal)
        replayBtn.setTitleColor(.systemPurple, for: .normal)
        replayBtn.addAction(UIAction { [weak self] _ in
            Task { await self?.performReplayAttack() }
        }, for: .touchUpInside)
        
        let stackView = UIStackView(arrangedSubviews: [registerBtn, transferBtn, replayBtn, clearBtn, logTextView])
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.logTextView.text += "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n\n"
            let bottom = NSMakeRange(self.logTextView.text.count - 1, 1)
            self.logTextView.scrollRangeToVisible(bottom)
            print(message)
        }
    }
    
    // MARK: - Part 1: Initial Registration (Attestation)
    private func registerDevice() async {
        log("--- 開始註冊 Device ---")
        guard DCAppAttestService.shared.isSupported else {
            log("❌ 此設備不支援 App Attest (請確認是否為實體機)")
            return
        }
        
        do {
            // 1. 生成硬體綁定的 Key
            let keyId = try await DCAppAttestService.shared.generateKey()
            // 1.1 儲存 Key ID (實務上建議存在 Keychain，此處為簡化 Demo，故存於 UserDefaults)
            UserDefaults.standard.set(keyId, forKey: keyIdStorageKey)
            log("✅ Key 生成成功: \(keyId.prefix(8))...")
            
            // 2. 取得 Challenge
            let challengeHex = try await fetchChallenge()
            log("✅ 取得 Challenge: \(challengeHex.prefix(8))...")
            
            // 3. 準備 Client Data Hash
            let challengeData = Data(challengeHex.utf8)
            let clientDataHash = Data(SHA256.hash(data: challengeData))
            
            // 4. 要求 iOS 進行 Attestation
            log("⏳ 正在向 Apple 請求 Attestation...")
            let attestationObject = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
            let attestationBase64 = attestationObject.base64EncodedString()
            log("✅ 取得 Attestation Object")
            
            // 5. 傳送至後端
            let body: [String: Any] = [
                "key_id": keyId,
                "attestation_object_b64": attestationBase64,
                "challenge": challengeHex
            ]
            
            let response = try await postRequest(endpoint: "/register", body: body)
            log("🎉 註冊成功之後端回應: \(response)")
            
        } catch {
            log("❌ 註冊失敗: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Part 2: Sensitive API Request (Assertion)
    private func performTransfer() async {
        log("--- 開始執行轉帳 (Assertion) ---")
        
        guard let keyId = UserDefaults.standard.string(forKey: keyIdStorageKey) else {
            log("❌ 找不到本地 Key ID，請先註冊 device")
            return
        }
        
        do {
            // 1. 取得新的 Challenge
            let challengeHex = try await fetchChallenge()
            log("✅ 取得新 Challenge: \(challengeHex.prefix(8))...")
            
            // 2. 建立 Payload 並計算 Hash
            let payloadObj = TransferPayload(amount: 100, to: "Bob")
            let payloadEncoder = JSONEncoder()
            payloadEncoder.outputFormatting = .sortedKeys
            let payloadData = try payloadEncoder.encode(payloadObj)
            
            let payloadHash = SHA256.hash(data: payloadData)
            let payloadHashHex = payloadHash.compactMap { String(format: "%02x", $0) }.joined()
            
            // 3. 建立 Client Data 並計算 Hash
            let clientDataObj = ClientData(challenge: challengeHex, payload_hash: payloadHashHex)
            let clientDataEncoder = JSONEncoder()
            clientDataEncoder.outputFormatting = .sortedKeys
            let clientDataBytes = try clientDataEncoder.encode(clientDataObj)
            let clientDataHash = Data(SHA256.hash(data: clientDataBytes))
            
            guard let exactClientDataString = String(data: clientDataBytes, encoding: .utf8) else {
                throw NSError(domain: "AppAttest", code: 3, userInfo: [NSLocalizedDescriptionKey: "ClientData 轉字串失敗"])
            }
            
            // 4. 產生 Assertion 簽名
            log("⏳ 正在產生 Assertion 簽名...")
            let assertionObject = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
            let assertionBase64 = assertionObject.base64EncodedString()
            log("✅ 取得 Assertion Object")
            
            // 5. 組合最終請求傳送至後端
            let requestBody: [String: Any] = [
                "key_id": keyId,
                "payload": try JSONSerialization.jsonObject(with: payloadData) as! [String: Any],
                "assertion_object_b64": assertionBase64,
                "client_data_raw": exactClientDataString
            ]
            
            // 😈 模擬駭客攔截並記錄了這個封包
            self.interceptedRequestBody = requestBody
            
            let response = try await postRequest(endpoint: "/transfer", body: requestBody)
            log("🎉 轉帳成功之後端回應: \(response)")
            
        } catch {
            log("❌ 轉帳失敗: \(error.localizedDescription)")
        }
    }
    
    // 😈 駭客發動攻擊的邏輯
    private func performReplayAttack() async {
        log("--- 😈 發動重放攻擊 ---")
        
        guard let stolenBody = interceptedRequestBody else {
            log("❌ 沒有可用的攔截封包，請先執行一次正常的轉帳！")
            return
        }
        
        log("⏳ 駭客正在將剛剛攔截到的合法封包原封不動重新送出...")
        
        do {
            // 直接拿剛才一模一樣的 Body 再次打給 Server
            let response = try await postRequest(endpoint: "/transfer", body: stolenBody)
            log("😱 攻擊成功！？伺服器回應: \(response)")
        } catch {
            log("🛡️ 攻擊被擋下！伺服器拒絕: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Network Helpers
    private func fetchChallenge() async throws -> String {
        guard let url = URL(string: "\(serverURL)/challenge") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challenge = json["challenge"] as? String else {
            throw NSError(domain: "Network", code: 1, userInfo: [NSLocalizedDescriptionKey: "解析 Challenge 失敗"])
        }
        return challenge
    }
    
    private func postRequest(endpoint: String, body: [String: Any]) async throws -> String {
        guard let url = URL(string: "\(serverURL)\(endpoint)") else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知錯誤"
            throw NSError(domain: "Network", code: 2, userInfo: [NSLocalizedDescriptionKey: "HTTP 錯誤: \(errorMsg)"])
        }
        
        return String(data: data, encoding: .utf8) ?? "Success"
    }
}

struct ClientData: Codable {
    let challenge: String
    let payload_hash: String
}

struct TransferPayload: Codable {
    let amount: Int
    let to: String
}
