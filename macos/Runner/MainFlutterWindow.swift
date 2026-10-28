import Cocoa
import FlutterMacOS
import Security
import WebKit
import UserNotifications

class MainFlutterWindow: NSWindow {
  private var nativeServices: NativeServices?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.minX, y: windowFrame.minY, width: 1360, height: 880), display: true)
    self.minSize = NSSize(width: 800, height: 600)
    self.title = "希悦 · Seiue Mac"
    self.isReleasedWhenClosed = false
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    nativeServices = NativeServices(controller: flutterViewController)

    super.awakeFromNib()
  }
}

final class NativeServices: NSObject, WKNavigationDelegate, NSWindowDelegate {
  private let service = "com.littleswift.seiue.session"
  private var channel: FlutterMethodChannel
  private var loginWindow: NSWindow?
  private var loginResult: FlutterResult?
  private var authorizing = false
  private var loginAttempt = UUID()
  private var approvalPortal: ApprovalPortal?
  private let notifications = CampusNotifications()

  init(controller: FlutterViewController) {
    channel = FlutterMethodChannel(name: "com.littleswift.seiue/native", binaryMessenger: controller.engine.binaryMessenger)
    super.init()
    notifications.onOpen = { [weak self] info in self?.channel.invokeMethod("notificationOpened", arguments: info) }
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }
  private var keyQuery: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
     kSecAttrAccount as String: "campus-session"]
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if notifications.handle(call, result: result) { return }
    switch call.method {
    case "applicationSupportPath":
      do {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent("SeiueMac", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        result(directory.path)
      } catch {
        result(FlutterError(code: "cache", message: "无法访问通知文字缓存目录", details: nil))
      }
    case "saveSession":
      guard let value = call.arguments as? String, let data = value.data(using: .utf8) else {
        result(FlutterError(code: "invalid", message: "会话格式无效", details: nil)); return
      }
      let updated = SecItemUpdate(keyQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      var status = updated
      if updated == errSecItemNotFound {
        var query = keyQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        status = SecItemAdd(query as CFDictionary, nil)
      }
      result(status == errSecSuccess ? nil : FlutterError(code: "keychain", message: "无法保存登录状态，请重新登录或取消保持登录", details: nil))
    case "readSession":
      var query = keyQuery
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      if status == errSecItemNotFound { result(nil); return }
      guard status == errSecSuccess, let data = item as? Data else {
        result(FlutterError(code: "keychain", message: "无法读取登录状态", details: nil)); return
      }
      result(String(data: data, encoding: .utf8))
    case "clearSession":
      approvalPortal?.close()
      approvalPortal = nil
      let status = SecItemDelete(keyQuery as CFDictionary)
      result(status == errSecSuccess || status == errSecItemNotFound ? nil : FlutterError(code: "keychain", message: "无法清除登录状态", details: nil))
    case "openUrl":
      guard let value = call.arguments as? String, let url = URL(string: value),
            ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
        result(FlutterError(code: "url", message: "链接无效", details: nil)); return
      }
      result(NSWorkspace.shared.open(url))
    case "openApprovalPortal":
      guard approvalPortal == nil else { approvalPortal?.activate(); result(FlutterError(code: "busy", message: "审批窗口已打开", details: nil)); return }
      guard let args = call.arguments as? [String: Any], let portal = ApprovalPortal(arguments: args, onClose: { [weak self] in
        self?.approvalPortal = nil
        result(nil)
      }) else { result(FlutterError(code: "invalid", message: "审批链接或登录会话无效", details: nil)); return }
      approvalPortal = portal
      portal.activate()
    case "webLogin": openLogin(result)
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func openLogin(_ result: @escaping FlutterResult) {
    guard loginResult == nil else { loginWindow?.makeKeyAndOrderFront(nil); result(FlutterError(code: "busy", message: "登录窗口已打开", details: nil)); return }
    loginResult = result
    loginAttempt = UUID()
    authorizing = false
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 820, height: 760), configuration: config)
    web.navigationDelegate = self
    let window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "希悦官方安全登录 · passport.seiue.com"
    window.contentView = web
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.center()
    loginWindow = window
    window.makeKeyAndOrderFront(nil)
    web.load(URLRequest(url: URL(string: "https://passport.seiue.com/login?school_id=3&type=account")!))
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = action.request.url, url.scheme == "https",
          let host = url.host, host == "seiue.com" || host.hasSuffix(".seiue.com") else {
      decisionHandler(.cancel); return
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard webView.url?.host == "chalk-c3.seiue.com", !authorizing else { return }
    authorizing = true
    let attempt = loginAttempt
    let script = """
    return await fetch('https://passport.seiue.com/authorize', {
      method:'POST', credentials:'include', headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:'response_type=token&client_id=GpxvnjhVKt56qTmnPWH1sA'
    }).then(r => r.json()).then(t => t.access_token ? JSON.stringify(t) : null);
    """
    webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] response in
      guard let self = self, self.loginAttempt == attempt else { return }
      switch response {
      case .success(let value):
        guard let token = value as? String else { self.authorizing = false; return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
          guard let self = self, self.loginAttempt == attempt, self.loginResult != nil,
                let data = token.data(using: .utf8), var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
          let dateFormat = ISO8601DateFormatter()
          payload["passport_cookies"] = cookies.compactMap { cookie -> [String: Any]? in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            guard ["passport.seiue.com", "seiue.com"].contains(domain), cookie.expiresDate == nil || cookie.expiresDate! > Date() else { return nil }
            var value: [String: Any] = ["name": cookie.name, "value": cookie.value, "domain": cookie.domain,
              "path": cookie.path, "secure": cookie.isSecure, "http_only": cookie.isHTTPOnly]
            if let expires = cookie.expiresDate { value["expires_at"] = dateFormat.string(from: expires) }
            return value
          }
          guard let combined = try? JSONSerialization.data(withJSONObject: payload), let result = String(data: combined, encoding: .utf8) else { return }
          let callback = self.loginResult
          self.loginResult = nil
          self.loginWindow?.close()
          self.loginWindow = nil
          callback?(result)
        }
      case .failure:
        self.authorizing = false
        let callback = self.loginResult
        self.loginResult = nil
        self.loginWindow?.close()
        self.loginWindow = nil
        callback?(FlutterError(code: "auth", message: "无法获取登录会话，请检查网络并重新登录", details: nil))
      }
    }
  }
  func windowWillClose(_ notification: Notification) {
    loginAttempt = UUID()
    if let callback = loginResult {
      loginResult = nil
      callback(FlutterError(code: "cancelled", message: "登录已取消", details: nil))
    }
    loginWindow = nil
  }
}

// A separate ephemeral official form keeps the school's upload, validation and
// approver rules intact. The Flutter client never submits an application itself.
final class ApprovalPortal: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
  private let window: NSWindow
  private let web: WKWebView
  private let onClose: () -> Void
  private var closed = false
  private let expiry: Date
  private var observations: [NSKeyValueObservation] = []
  private let progress = NSProgressIndicator()

  init?(arguments: [String: Any], onClose: @escaping () -> Void) {
    guard let value = arguments["url"] as? String, let url = URL(string: value),
          url.scheme == "https", url.host == "chalk-c3.seiue.com",
          ["/workflows/center/all", "/workflows/center/initiated", "/workflows/center/to-approve", "/workflows/center/copied"].contains(url.path),
          let token = arguments["token"] as? String, !token.isEmpty,
          let tokenType = arguments["tokenType"] as? String,
          let reflection = arguments["reflectionId"] as? String,
          let milliseconds = arguments["expiresAt"] as? NSNumber else { return nil }
    expiry = Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
    guard expiry.timeIntervalSinceNow > 0 else { return nil }
    let bootstrap: [String: Any] = ["accessToken": token, "tokenType": tokenType,
      "expiresAt": milliseconds.doubleValue, "rid": reflection]
    guard let data = try? JSONSerialization.data(withJSONObject: bootstrap, options: [.fragmentsAllowed]),
          let json = String(data: data, encoding: .utf8) else { return nil }
    self.onClose = onClose
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    // The official site supports these bootstrap parameters and removes them
    // after authorization. Set them locally at document start: no request URL,
    // browser history database, clipboard or log receives the session token.
    let script = """
    (() => {
      if (location.origin !== 'https://chalk-c3.seiue.com') return;
      const auth = \(json);
      const seconds = Math.floor((auth.expiresAt - Date.now()) / 1000);
      if (seconds <= 0) return;
      const policy = () => {
        if (!document.head) return false;
        const meta = document.createElement('meta');
        meta.name = 'referrer'; meta.content = 'no-referrer';
        document.head.prepend(meta); return true;
      };
      if (!policy()) {
        const observer = new MutationObserver(() => { if (policy()) observer.disconnect(); });
        observer.observe(document, {childList: true, subtree: true});
      }
      const target = new URL(location.href);
      target.searchParams.set('accessToken', auth.accessToken);
      target.searchParams.set('tokenType', auth.tokenType);
      target.searchParams.set('expiresIn', String(seconds));
      target.searchParams.set('rid', auth.rid);
      history.replaceState(null, '', target);
    })();
    """
    config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1140, height: 780), configuration: config)
    window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    super.init()
    window.title = "审批中心 · 希悦官方表单"
    window.isRestorable = false
    window.minSize = NSSize(width: 800, height: 600)
    window.isReleasedWhenClosed = false
    window.delegate = self
    let root = NSView(frame: web.frame)
    window.contentView = root
    web.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(web)
    progress.translatesAutoresizingMaskIntoConstraints = false
    progress.style = .bar
    progress.isIndeterminate = false
    progress.minValue = 0; progress.maxValue = 1
    root.addSubview(progress)
    NSLayoutConstraint.activate([
      web.leadingAnchor.constraint(equalTo: root.leadingAnchor), web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      web.topAnchor.constraint(equalTo: root.topAnchor), web.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      progress.leadingAnchor.constraint(equalTo: root.leadingAnchor), progress.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      progress.topAnchor.constraint(equalTo: root.topAnchor), progress.heightAnchor.constraint(equalToConstant: 3)
    ])
    web.navigationDelegate = self; web.uiDelegate = self
    observations = [web.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
      self?.progress.doubleValue = view.estimatedProgress
    }, web.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
      self?.progress.isHidden = !view.isLoading
    }]
    window.center()
    web.load(URLRequest(url: url))
  }
  func activate() { window.makeKeyAndOrderFront(nil) }
  func close() { window.close() }
  func windowWillClose(_ notification: Notification) {
    guard !closed else { return }
    closed = true
    web.stopLoading()
    web.configuration.userContentController.removeAllUserScripts()
    web.navigationDelegate = nil; web.uiDelegate = nil
    observations.removeAll()
    onClose()
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = action.request.url else { decisionHandler(.cancel); return }
    if url.scheme == "about" { decisionHandler(.allow); return }
    let host = url.host ?? ""
    if url.scheme == "https" && (host == "seiue.com" || host.hasSuffix(".seiue.com")) {
      decisionHandler(.allow); return
    }
    // External resources only open following an explicit link click; no token
    // is appended to a resource URL or carried into another site.
    if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
    decisionHandler(.cancel)
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if action.targetFrame == nil, let url = action.request.url {
      let host = url.host ?? ""
      if url.scheme == "https" && (host == "seiue.com" || host.hasSuffix(".seiue.com")) { webView.load(action.request) }
      else if ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
    }
    return nil
  }
  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
    let alert = NSAlert(); alert.messageText = "希悦官方表单"; alert.informativeText = message
    alert.addButton(withTitle: "确定")
    alert.beginSheetModal(for: window) { _ in completionHandler() }
  }
  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    let alert = NSAlert(); alert.messageText = "希悦官方表单"; alert.informativeText = message
    alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
    alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
  }
  func webViewDidClose(_ webView: WKWebView) { close() }
  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
    let picker = NSOpenPanel()
    picker.canChooseDirectories = false; picker.canChooseFiles = true
    picker.allowsMultipleSelection = parameters.allowsMultipleSelection
    picker.beginSheetModal(for: window) { response in completionHandler(response == .OK ? picker.urls : nil) }
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    // Also remove bootstrap parameters if the site's startup failed partway.
    guard webView.url?.host == "chalk-c3.seiue.com" else { return }
    webView.evaluateJavaScript("(() => { const u = new URL(location.href); ['accessToken','tokenType','expiresIn','refreshToken'].forEach(k => u.searchParams.delete(k)); history.replaceState(null, '', u); })()", completionHandler: nil)
  }
}

final class CampusNotifications: NSObject, UNUserNotificationCenterDelegate {
  private let center = UNUserNotificationCenter.current()
  private let defaults = UserDefaults.standard
  private var account: String?
  private var generation = 0
  private var reminderGeneration = 0
  private var pendingOpen: [String: Any]?
  private var ready = false
  var onOpen: (([String: Any]) -> Void)?

  override init() {
    super.init()
    account = defaults.string(forKey: "notifications.account")
    center.delegate = self
  }
  private var classes: Bool { defaults.object(forKey: "notifications.classes") as? Bool ?? true }
  private var messages: Bool { defaults.object(forKey: "notifications.messages") as? Bool ?? true }
  private func settings(_ result: @escaping FlutterResult) {
    center.getNotificationSettings { settings in
      let permission: String
      switch settings.authorizationStatus {
      case .authorized: permission = "authorized"
      case .denied: permission = "denied"
      case .provisional: permission = "provisional"
      default: permission = "notDetermined"
      }
      self.center.getPendingNotificationRequests { requests in
        let count = requests.filter { $0.identifier.hasPrefix("class:") }.count
        self.center.getDeliveredNotifications { delivered in
          DispatchQueue.main.async {
            let testId = "test:" + (self.account ?? "")
            let testDelivered = delivered.contains { $0.request.identifier == testId }
            result(["permission": permission, "classes": self.classes, "messages": self.messages, "scheduledClasses": count, "testDelivered": testDelivered])
          }
        }
      }
    }
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "notificationPreferences":
      if arguments["request"] as? Bool == true {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
          if let error = error { DispatchQueue.main.async { result(FlutterError(code: "notifications", message: error.localizedDescription, details: nil)) }; return }
          self.settings(result)
        }
      } else { settings(result) }
    case "setNotificationPreferences":
      defaults.set(arguments["classes"] as? Bool ?? true, forKey: "notifications.classes")
      defaults.set(arguments["messages"] as? Bool ?? true, forKey: "notifications.messages")
      reminderGeneration += 1
      if !classes {
        let version = reminderGeneration
        center.getPendingNotificationRequests { requests in
          DispatchQueue.main.async {
            guard version == self.reminderGeneration, !self.classes else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("class:") }.map(\.identifier))
          }
        }
      }
      settings(result)
    case "activateNotifications":
      let scope = arguments["account"] as? String
      generation += 1
      if scope != account { center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications() }
      account = scope
      defaults.set(scope, forKey: "notifications.account")
      result(nil)
    case "clearNotifications":
      generation += 1; account = nil
      defaults.removeObject(forKey: "notifications.account")
      center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
      result(nil)
    case "notificationsReady":
      ready = true
      if let pending = pendingOpen { pendingOpen = nil; onOpen?(pending) }
      result(nil)
    case "replaceCourseReminders", "deliverNotifications":
      guard let scope = arguments["account"] as? String, scope == account else { result(nil); return true }
      let rows = arguments["requests"] as? [[String: Any]] ?? []
      let scheduled = call.method == "replaceCourseReminders"
      let isTest = rows.count == 1 && (rows.first?["id"] as? String ?? "").hasPrefix("test:")
      if (scheduled && !classes) || (!scheduled && !messages && !isTest) { result(nil); return true }
      let version = generation, reminderVersion = reminderGeneration
      let deliver = {
        guard version == self.generation, scope == self.account, !scheduled || reminderVersion == self.reminderGeneration else { result(nil); return }
        let group = DispatchGroup()
        var firstError: Error?
        for row in rows {
          guard let id = row["id"] as? String, let title = row["title"] as? String else { continue }
          let content = UNMutableNotificationContent()
          content.title = title
          content.body = row["body"] as? String ?? ""
          content.sound = .default
          content.userInfo = ["account": scope, "destination": row["destination"] as? String ?? "schedule", "messageId": row["messageId"] as? String ?? ""]
          var trigger: UNNotificationTrigger?
          if scheduled {
            guard let milliseconds = row["fireAt"] as? NSNumber else { continue }
            let interval = milliseconds.doubleValue / 1000 - Date().timeIntervalSince1970
            guard interval > 1 else { continue }
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
          }
          group.enter()
          self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
            DispatchQueue.main.async { if firstError == nil { firstError = error }; group.leave() }
          }
        }
        group.notify(queue: .main) {
          if let error = firstError { result(FlutterError(code: "notifications", message: error.localizedDescription, details: nil)) }
          else { result(nil) }
        }
      }
      if scheduled {
        center.getPendingNotificationRequests { requests in
          DispatchQueue.main.async {
            guard version == self.generation, scope == self.account, !scheduled || reminderVersion == self.reminderGeneration else { result(nil); return }
            let wanted = Set(rows.compactMap { $0["id"] as? String })
            self.center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("class:") && !wanted.contains($0.identifier) }.map(\.identifier))
            deliver()
          }
        }
      } else { deliver() }
    default: return false
    }
    return true
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound])
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo.reduce(into: [String: Any]()) { result, item in if let key = item.key as? String { result[key] = item.value } }
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      (NSApp.delegate as? AppDelegate)?.mainFlutterWindow?.makeKeyAndOrderFront(nil)
      if self.ready { self.onOpen?(info) } else { self.pendingOpen = info }
      completionHandler()
    }
  }
}
