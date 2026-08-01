import AppKit
import ClaudePulseCore
import Foundation

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = UsageStore()
    private let settingsStore = SettingsStore()
    private let notificationManager = NotificationManager()
    private let launchAtLogin = LaunchAtLoginManager()
    private var preferencesWindowController: PreferencesWindowController?
    private let aboutWindowController = AboutWindowController()
    private var timer: Timer?

    override init() {
        super.init()
        configureStatusButton()
        store.onChange = { [weak self] in
            self?.updateStatusTitle()
            self?.rebuildMenu()
            self?.processNotifications()
        }
        settingsStore.onChange = { [weak self] in
            self?.updateStatusTitle()
            self?.rebuildMenu()
            self?.rescheduleTimer()
            self?.processNotifications()
        }
        rebuildMenu()
        updateStatusTitle()
    }

    func start() {
        store.refresh()
        rescheduleTimer()
    }

    private func updateStatusTitle() {
        let settings = settingsStore.settings
        let title = LocalizedDisplayFormatter.statusTitle(
            for: store.data,
            mode: settings.displayMode,
            percentDisplay: settings.percentDisplay,
            staleAfterMinutes: settings.staleAfterMinutes
        )
        statusItem.button?.title = "  \(title)"
        let tooltip = L10n.format("status.tooltip", title)
        statusItem.button?.toolTip = tooltip
        statusItem.button?.setAccessibilityLabel(tooltip)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.toolTip = L10n.text("app.name")
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown

        if let image = Self.loadMenuBarIcon() {
            image.isTemplate = true
            image.size = NSSize(width: 26, height: 18)
            button.image = image
        }
    }

    private static func loadMenuBarIcon() -> NSImage? {
        let fileName = "ClaudePulseMenuTemplate"

        if let url = Bundle.main.url(forResource: fileName, withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: fileName, withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        #endif

        return nil
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        if let data = store.data {
            menu.addItem(disabled(LocalizedDisplayFormatter.detailLine(label: L10n.text("window.fiveHour"), window: data.snapshot.primary)))
            menu.addItem(disabled(LocalizedDisplayFormatter.detailLine(label: L10n.text("window.weekly"), window: data.snapshot.secondary)))
            for limit in data.additionalLimitsForDisplay {
                menu.addItem(disabled(LocalizedDisplayFormatter.detailLine(
                    label: L10n.limitLabel(limit),
                    window: limit.window
                )))
            }
            if let planType = data.snapshot.planType {
                menu.addItem(disabled(L10n.format("menu.plan", planType)))
            }
            menu.addItem(disabled(L10n.format("menu.sourceUpdated", data.source.rawValue, LocalizedDisplayFormatter.relativeAge(data.fetchedAt))))
            if let sourcePath = data.sourcePath {
                menu.addItem(disabled(L10n.format("menu.sourcePath", sourcePath)))
            }
            if let message = data.errorMessage {
                menu.addItem(disabled(L10n.format("menu.fallbackReason", message)))
            }
        } else {
            menu.addItem(disabled(L10n.text("menu.usageUnavailable")))
        }

        if store.emptyState != .available {
            menu.addItem(disabled(L10n.emptyStateMessage(store.emptyState)))
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: L10n.text("menu.refreshNow"), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let openClaude = NSMenuItem(title: L10n.text("menu.openClaudeUsage"), action: #selector(openClaudeUsage), keyEquivalent: "")
        openClaude.target = self
        menu.addItem(openClaude)

        let preferences = NSMenuItem(title: L10n.text("menu.preferences"), action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let launch = NSMenuItem(title: L10n.text("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = launchAtLogin.isEnabled ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())
        let updates = NSMenuItem(title: L10n.text("menu.checkForUpdates"), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let about = NSMenuItem(title: L10n.text("menu.about"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.text("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func refreshNow() {
        store.refresh()
    }

    @objc private func openClaudeUsage() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Claude.app"))
    }

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                settingsStore: settingsStore,
                usageStore: store,
                notificationManager: notificationManager
            )
        }
        preferencesWindowController?.show()
    }

    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(AppLinks.latestRelease)
    }

    @objc private func showAbout() {
        aboutWindowController.show()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
        } catch {
            showError(L10n.format("menu.launchAtLoginError", error.localizedDescription))
        }
        rebuildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("app.name")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settingsStore.settings.refreshInterval.seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.refresh()
            }
        }
    }

    private func processNotifications() {
        notificationManager.process(data: store.data, settings: settingsStore.settings)
    }
}
