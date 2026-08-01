import CommonCrypto
import Foundation
import Security

public final class ClaudeCookieUsageClient: @unchecked Sendable {
    private enum Constants {
        static let cookieService = "Claude Safe Storage"
        static let cookieDBRelativePath = "Cookies"
        static let hostSuffix = "claude.ai"
        static let requiredOrgCookie = "lastActiveOrg"
        static let keySalt = Data("saltysalt".utf8)
        static let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        static let pbkdfRounds: UInt32 = 1003
    }

    public let supportPath: String
    public let apiBaseURL: URL
    public let timeoutSeconds: TimeInterval
    public let planCacheSeconds: TimeInterval

    private let planCache = PlanNameCache()

    public init(
        supportPath: String = "\(NSHomeDirectory())/Library/Application Support/Claude",
        apiBaseURL: URL = URL(string: "https://claude.ai")!,
        timeoutSeconds: TimeInterval = 20,
        planCacheSeconds: TimeInterval = 3_600
    ) {
        self.supportPath = supportPath
        self.apiBaseURL = apiBaseURL
        self.timeoutSeconds = timeoutSeconds
        self.planCacheSeconds = planCacheSeconds
    }

    public func fetch() throws -> UsageData {
        let cookieStore = try loadCookieStore()
        guard let orgID = cookieStore.cookies[Constants.requiredOrgCookie], !orgID.isEmpty else {
            throw ClaudeUsageError.missingClaudeCookie(Constants.requiredOrgCookie)
        }
        guard cookieStore.cookies["sessionKey"] != nil || cookieStore.cookies["sessionKeyLC"] != nil else {
            throw ClaudeUsageError.missingClaudeCookie("sessionKey")
        }

        let url = apiBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("organizations")
            .appendingPathComponent(orgID)
            .appendingPathComponent("usage")

        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "GET"
        request.setValue(cookieStore.header, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudePulse/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response, error) = perform(request)
        if let error {
            throw ClaudeUsageError.networkRequestFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageError.networkRequestFailed("Claude usage endpoint returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeUsageError.networkRequestFailed("Claude usage endpoint returned HTTP \(http.statusCode).")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.malformedResponse
        }

        let usageData = try ClaudeUsagePayloadParser.parse(
            result: object,
            source: .claudeAPI,
            sourcePath: "https://claude.ai/api/organizations/<organization>/usage"
        )

        // The usage endpoint carries windows only, so the plan comes from the
        // organization record. Never fail a refresh over it — usage is the point.
        guard usageData.snapshot.planType == nil else {
            return usageData
        }
        guard let planName = planName(organizationID: orgID, cookieHeader: cookieStore.header) else {
            return usageData
        }
        return usageData.withPlanType(planName)
    }

    /// Fetches the plan name from `/api/organizations`, cached for `planCacheSeconds`
    /// so a 30-second refresh interval does not re-request it every tick.
    private func planName(organizationID: String, cookieHeader: String) -> String? {
        if let cached = planCache.value(for: organizationID, maxAge: planCacheSeconds) {
            return cached
        }

        var request = URLRequest(
            url: apiBaseURL.appendingPathComponent("api").appendingPathComponent("organizations"),
            timeoutInterval: timeoutSeconds
        )
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudePulse/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response, error) = perform(request)
        guard error == nil,
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data),
              let name = ClaudePlanResolver.planName(inOrganizationsPayload: object, organizationID: organizationID) else {
            return nil
        }

        planCache.store(name, for: organizationID)
        return name
    }

    private func perform(_ request: URLRequest) -> (Data, URLResponse?, Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var data = Data()
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()

        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data ?? Data()
            box.response = response
            box.error = error
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return (box.data, box.response, box.error)
    }

    private func loadCookieStore() throws -> ClaudeCookieStore {
        let cookieDB = URL(fileURLWithPath: supportPath)
            .appendingPathComponent(Constants.cookieDBRelativePath)
        let rows = try queryCookies(at: cookieDB.path)
        let encryptionKey = try loadEncryptionKey()

        var cookies: [String: String] = [:]
        for row in rows where row.host.hasSuffix(Constants.hostSuffix) {
            if !row.value.isEmpty {
                cookies[row.name] = row.value
                continue
            }
            guard let encrypted = Data(hexString: row.encryptedHex), !encrypted.isEmpty else {
                continue
            }
            if let decrypted = try? decryptCookie(encrypted, host: row.host, key: encryptionKey), !decrypted.isEmpty {
                cookies[row.name] = decrypted
            }
        }

        return ClaudeCookieStore(cookies: cookies)
    }

    private func queryCookies(at path: String) throws -> [ClaudeCookieRow] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ClaudeUsageError.cookieDatabaseMissing(path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-separator",
            "\t",
            path,
            """
            SELECT host_key, name, value, hex(encrypted_value)
            FROM cookies
            WHERE host_key LIKE '%claude.ai'
            ORDER BY name;
            """
        ]

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "sqlite3 failed"
            throw ClaudeUsageError.cookieDatabaseReadFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 4 else {
                    return nil
                }
                return ClaudeCookieRow(host: parts[0], name: parts[1], value: parts[2], encryptedHex: parts[3])
            }
    }

    private func loadEncryptionKey() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.cookieService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let password = item as? Data else {
            throw ClaudeUsageError.keychainPasswordMissing(Constants.cookieService)
        }

        let keyLength = kCCKeySizeAES128
        var key = Data(repeating: 0, count: keyLength)
        let result = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                Constants.keySalt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        Constants.keySalt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        Constants.pbkdfRounds,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw ClaudeUsageError.cookieDecryptionFailed
        }
        return key
    }

    private func decryptCookie(_ encrypted: Data, host: String, key: Data) throws -> String {
        guard encrypted.starts(with: Data("v10".utf8)) else {
            throw ClaudeUsageError.cookieDecryptionFailed
        }

        let cipherText = encrypted.dropFirst(3)
        let outputCapacity = cipherText.count + kCCBlockSizeAES128
        var output = Data(repeating: 0, count: outputCapacity)
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            cipherText.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    Constants.iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            cipherText.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw ClaudeUsageError.cookieDecryptionFailed
        }

        output.removeSubrange(outputLength..<output.count)
        let expectedHostHash = SHA256.hash(host)
        if output.starts(with: expectedHostHash) {
            output.removeFirst(expectedHostHash.count)
        }

        guard let value = String(data: output, encoding: .utf8) else {
            throw ClaudeUsageError.cookieDecryptionFailed
        }
        return value
    }
}

private final class PlanNameCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (name: String, storedAt: Date)] = [:]

    func value(for organizationID: String, maxAge: TimeInterval) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[organizationID],
              Date().timeIntervalSince(entry.storedAt) < maxAge else {
            return nil
        }
        return entry.name
    }

    func store(_ name: String, for organizationID: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[organizationID] = (name, Date())
    }
}

private struct ClaudeCookieRow {
    let host: String
    let name: String
    let value: String
    let encryptedHex: String
}

private struct ClaudeCookieStore {
    let cookies: [String: String]

    var header: String {
        cookies
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }
}

private enum SHA256 {
    static func hash(_ text: String) -> Data {
        var digest = Data(repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        Data(text.utf8).withUnsafeBytes { input in
            digest.withUnsafeMutableBytes { output in
                _ = CC_SHA256(input.baseAddress, CC_LONG(input.count), output.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return digest
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else {
            return nil
        }
        var data = Data()
        data.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        self = data
    }
}
