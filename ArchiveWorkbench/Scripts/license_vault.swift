// license_vault.swift — Mac解霸 Pro 激活码本地库工具（离线、零网络）
//
// 明文激活码与 Ed25519 私钥仅存于 ~/.macunzip/license_vault.json（chmod 600），
// 永不进入 git 仓库与安装包。安装包内只嵌：公钥 + 码集的 SHA-256 哈希白名单
// （非明文，可下期轮换吊销）。
//
// 用法：
//   swift Scripts/license_vault.swift init            生成密钥对 + 空库（已存在则拒绝覆盖）
//   swift Scripts/license_vault.swift gen <n>         签发 n 个激活码并打印明文（仅此一次可见）
//   swift Scripts/license_vault.swift list            列出全部明文码（本地取码用）
//   swift Scripts/license_vault.swift embed [--out P] 生成 EmbeddedLicenseCodes.swift（公钥+哈希集）
//   swift Scripts/license_vault.swift verify <key>    本地验证某码（签名/哈希双路径）
//
// 激活码格式（与 LicenseManager 一致）：MACUNZIP-XXXX-XXXX-XXXX-<base64url(Ed25519签名)>
// 签名 payload = "MACUNZIP-XXXX-XXXX-XXXX"（前四段）。

import CryptoKit
import Foundation

// MARK: - Paths & IO

let vaultDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".macunzip", isDirectory: true)
let vaultPath = vaultDir.appendingPathComponent("license_vault.json")
let defaultEmbedOut = "App/Sources/EmbeddedLicenseCodes.swift"

struct VaultCode: Codable {
    let code: String
    let sha256: String
    let issuedAt: String
    var note: String
}

struct Vault: Codable {
    var version: Int
    var createdAt: String
    var privateKeyBase64: String
    var publicKeyBase64: String
    var codes: [VaultCode]
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("[license_vault] 错误: \(msg)\n".utf8))
    exit(1)
}

func nowISO() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: Date())
}

func loadVault() -> Vault {
    guard FileManager.default.fileExists(atPath: vaultPath.path) else {
        fail("库不存在，先运行 init")
    }
    do {
        let data = try Data(contentsOf: vaultPath)
        return try JSONDecoder().decode(Vault.self, from: data)
    } catch {
        fail("读取库失败: \(error)")
    }
}

func saveVault(_ vault: Vault) {
    do {
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: vaultDir.path)
        let data = try JSONEncoder().encode(vault)
        try data.write(to: vaultPath, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultPath.path)
    } catch {
        fail("写库失败: \(error)")
    }
}

// MARK: - Crypto helpers（与 LicenseManager 完全同构）

func base64urlEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func base64urlDecode(_ input: String) -> Data? {
    var b64 = input.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let rem = b64.count % 4
    if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
    return Data(base64Encoded: b64)
}

func sha256Hex(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// 与 LicenseManager.normalizeKey 同构：去空白/空格，前四段大写，签名段保大小写。
func normalizeKey(_ input: String) -> String {
    let trimmed = input
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: " ", with: "")
    let parts = trimmed.split(separator: "-", maxSplits: 4, omittingEmptySubsequences: true)
    guard parts.count == 5 else { return trimmed.uppercased() }
    let prefix = parts[0...3].joined(separator: "-").uppercased()
    return prefix + "-" + parts[4]
}

// MARK: - 码生成

let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // 去 0/O/1/I 防误读

func randomSegment(_ rng: inout SystemRandomNumberGenerator) -> String {
    String((0..<4).map { _ in alphabet.randomElement(using: &rng)! })
}

func makeCode(privateKey: Curve25519.Signing.PrivateKey, existing: Set<String>) -> String {
    var rng = SystemRandomNumberGenerator()
    while true {
        let prefix = "MACUNZIP-\(randomSegment(&rng))-\(randomSegment(&rng))-\(randomSegment(&rng))"
        guard !existing.contains(prefix) else { continue }
        guard let payload = prefix.data(using: .utf8),
              let sig = try? privateKey.signature(for: payload) else { continue }
        return prefix + "-" + base64urlEncode(sig)
    }
}

// MARK: - 验证（双路径，与 app 同构）

func verifySignature(key: String, publicKeyBase64: String) -> Bool {
    let segs = key.split(separator: "-", maxSplits: 4, omittingEmptySubsequences: true).map(String.init)
    guard segs.count == 5,
          let payload = segs[0...3].joined(separator: "-").data(using: .utf8),
          let sigData = base64urlDecode(segs[4]),
          let pubData = Data(base64Encoded: publicKeyBase64), pubData.count == 32,
          let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData)
    else { return false }
    return pub.isValidSignature(sigData, for: payload)
}

// MARK: - Commands

let args = CommandLine.arguments
guard args.count >= 2 else { fail("用法: license_vault.swift <init|gen|list|embed|verify> ...") }
let cmd = args[1]

switch cmd {
case "init":
    if FileManager.default.fileExists(atPath: vaultPath.path) {
        fail("库已存在（\(vaultPath.path)），拒绝覆盖；如需重建请先手动删除")
    }
    let privateKey = Curve25519.Signing.PrivateKey()
    let vault = Vault(
        version: 1,
        createdAt: nowISO(),
        privateKeyBase64: privateKey.rawRepresentation.base64EncodedString(),
        publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString(),
        codes: []
    )
    saveVault(vault)
    print("密钥对已生成，库已创建于 \(vaultPath.path)（chmod 600）")
    print("公钥(base64): \(vault.publicKeyBase64)")
    print("下一步: gen <n> 签发激活码；embed 生成嵌入式白名单")

case "gen":
    let n = args.count >= 3 ? Int(args[2]) ?? 0 : 0
    guard n > 0, n <= 10000 else { fail("gen <n>，1<=n<=10000") }
    var vault = loadVault()
    guard let privData = Data(base64Encoded: vault.privateKeyBase64),
          let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData)
    else { fail("私钥损坏") }
    var existing = Set(vault.codes.map { $0.code })
    var issued: [VaultCode] = []
    for _ in 0..<n {
        let code = makeCode(privateKey: privateKey, existing: existing)
        existing.insert(code)
        issued.append(VaultCode(code: code, sha256: sha256Hex(normalizeKey(code)), issuedAt: nowISO(), note: ""))
    }
    vault.codes.append(contentsOf: issued)
    saveVault(vault)
    print("已签发 \(n) 个激活码（库内共 \(vault.codes.count)）：")
    for c in issued { print("  \(c.code)") }
    print("提示: 运行 embed 将哈希白名单写入安装包；明文仅存本地库。")

case "list":
    let vault = loadVault()
    print("库内共 \(vault.codes.count) 个激活码：")
    for c in vault.codes {
        print("  \(c.code)\(c.note.isEmpty ? "" : "  # \(c.note)")")
    }

case "embed":
    var outPath = defaultEmbedOut
    if let i = args.firstIndex(of: "--out"), i + 1 < args.count { outPath = args[i + 1] }
    let vault = loadVault()
    let hashes = vault.codes.map(\.sha256).sorted()
    var swift = """
    // 由 Scripts/license_vault.swift embed 自动生成 —— 勿手改。
    // 仅含公钥与激活码 SHA-256 哈希白名单（非明文）；明文码与私钥仅在
    // 发行者本地 ~/.macunzip/license_vault.json（chmod 600），永不入库/入包。
    // 轮换：重新 gen/embed 后发新版，旧码集随旧版本自然失效。
    enum EmbeddedLicenseCodes {
        static let publicKeyBase64 = "\(vault.publicKeyBase64)"
        static let sha256HexHashes: Set<String> = [

    """
    for h in hashes {
        swift += "        \"\(h)\",\n"
    }
    swift += """
        ]
    }

    """
    do {
        try swift.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("已生成 \(outPath)（\(hashes.count) 个哈希，公钥 \(vault.publicKeyBase64.prefix(12))…）")
    } catch {
        fail("写 \(outPath) 失败: \(error)")
    }

case "verify":
    guard args.count >= 3 else { fail("verify <key>") }
    let vault = loadVault()
    let key = normalizeKey(args[2])
    let sigOK = verifySignature(key: key, publicKeyBase64: vault.publicKeyBase64)
    let hashOK = vault.codes.contains { $0.sha256 == sha256Hex(key) }
    print("签名路径: \(sigOK ? "通过" : "不通过")；哈希白名单路径: \(hashOK ? "在库" : "不在库")")
    exit(sigOK || hashOK ? 0 : 1)

default:
    fail("未知命令: \(cmd)")
}
