import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem?
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(systemSymbolName: "graduationcap", accessibilityDescription: "希悦")
    item.button?.toolTip = "希悦 · 关闭窗口后继续同步消息"
    let menu = NSMenu()
    menu.addItem(withTitle: "打开希悦", action: #selector(showMainWindow), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "退出希悦", action: #selector(quitApp), keyEquivalent: "q").target = self
    item.menu = menu
    statusItem = item
  }
  @objc private func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
  }
  @objc private func quitApp() { NSApp.terminate(nil) }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showMainWindow(); return true
  }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
