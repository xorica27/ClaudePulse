import Foundation

public enum ClaudeUsageError: Error, LocalizedError, Equatable {
    case claudeAppMissing(String)
    case cookieDatabaseMissing(String)
    case cookieDatabaseReadFailed(String)
    case keychainPasswordMissing(String)
    case missingClaudeCookie(String)
    case cookieDecryptionFailed
    case networkRequestFailed(String)
    case noExactUsageData(scannedPaths: [String])
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .claudeAppMissing(let path):
            return "Claude app was not found at \(path)."
        case .cookieDatabaseMissing(let path):
            return "Claude cookie database was not found at \(path)."
        case .cookieDatabaseReadFailed(let message):
            return "Could not read Claude cookie database: \(message)"
        case .keychainPasswordMissing(let service):
            return "Could not read \(service) from Keychain."
        case .missingClaudeCookie(let name):
            return "Claude cookie \(name) was not found."
        case .cookieDecryptionFailed:
            return "Could not decrypt Claude cookies."
        case .networkRequestFailed(let message):
            return "Could not fetch Claude usage: \(message)"
        case .noExactUsageData(let scannedPaths):
            if scannedPaths.isEmpty {
                return "No Claude local storage files were found to scan."
            }
            return "No exact Claude usage payload was found in local app data. Scanned \(scannedPaths.count) paths."
        case .malformedResponse:
            return "Claude usage data was present but unreadable."
        }
    }
}

public final class ClaudeUsageClient: @unchecked Sendable {
    public let appPath: String
    public let supportPath: String
    public let logsPath: String
    public let maxFileBytes: Int
    public let maxFilesPerLocation: Int

    private let fileManager: FileManager
    private let cookieUsageClient: ClaudeCookieUsageClient

    public init(
        appPath: String = "/Applications/Claude.app",
        supportPath: String = "\(NSHomeDirectory())/Library/Application Support/Claude",
        logsPath: String = "\(NSHomeDirectory())/Library/Logs/Claude",
        maxFileBytes: Int = 8 * 1_024 * 1_024,
        maxFilesPerLocation: Int = 400,
        fileManager: FileManager = .default,
        cookieUsageClient: ClaudeCookieUsageClient? = nil
    ) {
        self.appPath = appPath
        self.supportPath = supportPath
        self.logsPath = logsPath
        self.maxFileBytes = maxFileBytes
        self.maxFilesPerLocation = maxFilesPerLocation
        self.fileManager = fileManager
        self.cookieUsageClient = cookieUsageClient ?? ClaudeCookieUsageClient(supportPath: supportPath)
    }

    public func fetch() throws -> UsageData {
        guard fileManager.fileExists(atPath: appPath) else {
            throw ClaudeUsageError.claudeAppMissing(appPath)
        }

        do {
            return try cookieUsageClient.fetch()
        } catch {
            let localStorageData = try? fetchFromLocalStorage()
            if let localStorageData {
                return localStorageData.replacingSource(localStorageData.source, errorMessage: error.localizedDescription)
            }
            throw error
        }
    }

    private func fetchFromLocalStorage() throws -> UsageData {
        var scannedPaths: [String] = []
        for location in probeLocations {
            for file in candidateFiles(in: location.path).prefix(maxFilesPerLocation) {
                scannedPaths.append(file.path)
                guard let text = readSearchableText(from: file) else {
                    continue
                }

                for candidate in JSONCandidateExtractor.extract(from: text) {
                    guard let payload = candidate.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                          let data = try? ClaudeUsagePayloadParser.parse(
                            result: object,
                            source: location.source,
                            sourcePath: file.path
                          ),
                          data.snapshot.primary != nil || data.snapshot.secondary != nil else {
                        continue
                    }
                    return data
                }
            }
        }

        throw ClaudeUsageError.noExactUsageData(scannedPaths: scannedPaths)
    }

    public var claudeAppVersion: String? {
        let infoPlist = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return object["CFBundleShortVersionString"] as? String
            ?? object["CFBundleVersion"] as? String
    }

    private var probeLocations: [ClaudeUsageProbeLocation] {
        [
            ClaudeUsageProbeLocation(source: .localStorage, path: URL(fileURLWithPath: supportPath).appendingPathComponent("Local Storage/leveldb").path),
            ClaudeUsageProbeLocation(source: .indexedDB, path: URL(fileURLWithPath: supportPath).appendingPathComponent("IndexedDB").path),
            ClaudeUsageProbeLocation(source: .sessionStorage, path: URL(fileURLWithPath: supportPath).appendingPathComponent("Session Storage").path),
            ClaudeUsageProbeLocation(source: .log, path: logsPath)
        ]
    }

    private func candidateFiles(in path: String) -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return []
        }

        let root = URL(fileURLWithPath: path)
        if !isDirectory.boolValue {
            return [root]
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, date: Date)] = []
        for case let file as URL in enumerator {
            guard isSupportedStorageFile(file),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= maxFileBytes else {
                continue
            }
            files.append((file, values.contentModificationDate ?? .distantPast))
        }

        return files.sorted { $0.date > $1.date }.map(\.url)
    }

    private func isSupportedStorageFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "log", "ldb", "json", "sqlite", "txt":
            true
        default:
            false
        }
    }

    private func readSearchableText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), !data.isEmpty else {
            return nil
        }
        if let utf8 = String(data: data, encoding: .utf8), utf8.contains("{") {
            return utf8
        }
        return PrintableStringExtractor.extract(from: data)
    }
}

private struct ClaudeUsageProbeLocation {
    let source: UsageSource
    let path: String
}

private enum PrintableStringExtractor {
    static func extract(from data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(data.count)
        for byte in data {
            switch byte {
            case 0x09, 0x0A, 0x0D, 0x20...0x7E:
                scalars.append(UnicodeScalar(Int(byte))!)
            default:
                scalars.append(" ")
            }
        }
        return String(scalars)
    }
}

private enum JSONCandidateExtractor {
    private static let markers = [
        "usage", "Usage", "usedPercent", "used_percent", "resetsAt",
        "resets_at", "reset_at", "weekly", "Weekly", "limit"
    ]

    static func extract(from text: String) -> [String] {
        let characters = Array(text)
        var candidates: [String] = []
        var seen: Set<String> = []

        for marker in markers {
            var searchStart = text.startIndex
            while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
                let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                if let objectRange = balancedObjectRange(near: offset, in: characters) {
                    let candidate = String(characters[objectRange])
                    if seen.insert(candidate).inserted {
                        candidates.append(candidate)
                    }
                }
                searchStart = range.upperBound
            }
        }

        return candidates
    }

    private static func balancedObjectRange(near offset: Int, in characters: [Character]) -> Range<Int>? {
        guard !characters.isEmpty else {
            return nil
        }

        let lowerBound = max(0, offset - 20_000)
        var start = offset
        while start >= lowerBound {
            if characters[start] == "{" {
                break
            }
            start -= 1
        }
        guard start >= lowerBound, characters[start] == "{" else {
            return nil
        }

        var depth = 0
        var isInString = false
        var isEscaped = false
        let upperBound = min(characters.count, start + 80_000)

        for index in start..<upperBound {
            let character = characters[index]
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }

            if character == "\"" {
                isInString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return start..<(index + 1)
                }
            }
        }

        return nil
    }
}
