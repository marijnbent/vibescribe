import AppKit
import Combine

struct MenuBarLanguageItem: Equatable {
    let language: DeepgramLanguage
    let isSelected: Bool
}

enum MenuBarLanguageModel {
    static func title(for currentLanguage: DeepgramLanguage) -> String {
        "Language: \(currentLanguage.displayName)"
    }

    static func submenuItems(
        currentLanguage: DeepgramLanguage,
        starredLanguages: [DeepgramLanguage]
    ) -> [MenuBarLanguageItem] {
        DeepgramLanguage.sortedForMenuBar(
            DeepgramLanguage.normalizedStarredLanguages(starredLanguages)
        ).map { language in
            MenuBarLanguageItem(
                language: language,
                isSelected: language == currentLanguage
            )
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    private let settingsStore: SettingsStore
    private let statusItem: NSStatusItem

    private let openMainAction: () -> Void
    private let openHistoryAction: () -> Void
    private let quitAction: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore,
        onOpenMain: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.openMainAction = onOpenMain
        self.openHistoryAction = onOpenHistory
        self.quitAction = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Talkie")
        }

        bindSettings()
        rebuildMenu()
    }

    private func bindSettings() {
        settingsStore.$deepgramLanguage
            .combineLatest(settingsStore.$starredDeepgramLanguages)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Settings", action: #selector(openMainWindow), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        let historyItem = NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let languageItem = NSMenuItem(
            title: MenuBarLanguageModel.title(for: settingsStore.deepgramLanguage),
            action: nil,
            keyEquivalent: ""
        )
        languageItem.submenu = makeLanguageSubmenu()
        menu.addItem(languageItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeLanguageSubmenu() -> NSMenu {
        let submenu = NSMenu(title: "Language")

        for item in MenuBarLanguageModel.submenuItems(
            currentLanguage: settingsStore.deepgramLanguage,
            starredLanguages: settingsStore.starredDeepgramLanguages
        ) {
            let menuItem = NSMenuItem(
                title: item.language.displayName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.state = item.isSelected ? .on : .off
            menuItem.representedObject = item.language.rawValue
            submenu.addItem(menuItem)
        }

        return submenu
    }

    @objc private func openMainWindow() {
        DispatchQueue.main.async { [openMainAction] in
            openMainAction()
        }
    }

    @objc private func openHistory() {
        DispatchQueue.main.async { [openHistoryAction] in
            openHistoryAction()
        }
    }

    @objc private func quitApp() {
        quitAction()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = DeepgramLanguage(rawValue: rawValue) else {
            return
        }

        settingsStore.deepgramLanguage = language
    }
}
