import Foundation

final class LaunchAtLoginManager {
    private let label = "com.charlie.claudepulse"

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            disable()
        }
    }

    private func enable() throws {
        let launchAgents = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)

        let executablePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/ClaudePulse")
            .path

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private func disable() {
        _ = runLaunchctl(arguments: ["bootout", guiDomain, launchAgentURL.path])
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private var guiDomain: String {
        "gui/\(getuid())"
    }

    @discardableResult
    private func runLaunchctl(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
