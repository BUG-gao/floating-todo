import AppKit
import ToDoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TodoStore()
    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    private var clickThroughMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 作为状态栏小组件运行：不占用 Dock 和 ⌘Tab，只保留状态栏入口。
        NSApp.setActivationPolicy(.accessory)

        let controller = FloatingPanelController(store: store)
        panelController = controller
        controller.show()

        configureStatusItem()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Floating Todo")
            button.imagePosition = .imageLeading
            button.toolTip = "Floating Todo"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏小组件", action: #selector(toggleWidget), keyEquivalent: ""))
        let clickThroughItem = NSMenuItem(title: "开启 Option 操作小组件", action: #selector(toggleClickThrough), keyEquivalent: "t")
        clickThroughItem.keyEquivalentModifierMask = [.command, .option]
        clickThroughMenuItem = clickThroughItem
        menu.addItem(clickThroughItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }

    @objc private func toggleWidget() {
        panelController?.toggle()
    }

    @objc private func toggleClickThrough() {
        if store.settings.effectiveOptionClickInsideWidget {
            store.settings.clickThrough = false
            store.settings.autoClickThroughAtLowOpacity = false
        } else {
            store.settings.clickThrough = true
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateClickThroughMenuItem() {
        let isEnabled = store.settings.effectiveOptionClickInsideWidget
        clickThroughMenuItem?.title = isEnabled ? "关闭 Option 操作小组件" : "开启 Option 操作小组件"
        clickThroughMenuItem?.state = isEnabled ? .on : .off
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateClickThroughMenuItem()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
