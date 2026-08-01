import Foundation

enum AppLinks {
    static let latestRelease = URL(string: "https://github.com/xorica27/ClaudePulse/releases/latest")!
}

enum AppInfo {
    /// Read from the bundle, never hardcoded — a literal fallback here goes stale
    /// silently and then misreports the running build.
    static var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
