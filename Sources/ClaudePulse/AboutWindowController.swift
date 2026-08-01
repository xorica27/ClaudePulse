import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("about.title")
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct AboutView: View {
    private var version: String {
        AppInfo.version ?? L10n.text("generic.unknown")
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .cornerRadius(16)

            Text(L10n.text("app.name"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.format("about.version", version))
                .foregroundStyle(.secondary)

            Text(L10n.text("about.privacyNote"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(L10n.text("about.viewReleases"), destination: AppLinks.latestRelease)
        }
        .padding(24)
        .frame(width: 420, height: 260)
    }
}
