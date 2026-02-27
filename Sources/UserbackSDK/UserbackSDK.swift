import Foundation

#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
public final class UserbackSDK: NSObject {
    public static let shared = UserbackSDK()

    public static let sdkVersion = "1.0.0"
    public static func version() -> String { sdkVersion }

    public struct Configuration {
        public let accessToken: String
        public let widgetJSURL: String
        public let userData: [String: Any]
        public let widgetCSS: String?
        public let surveyURL: String?
        public let requestURL: String?
        public let trackURL: String?

        public init(
            accessToken: String,
            widgetJSURL: String,
            userData: [String: Any] = [:],
            widgetCSS: String? = nil,
            surveyURL: String? = nil,
            requestURL: String? = nil,
            trackURL: String? = nil
        ) {
            self.accessToken = accessToken
            self.widgetJSURL = widgetJSURL
            self.userData = userData
            self.widgetCSS = widgetCSS
            self.surveyURL = surveyURL
            self.requestURL = requestURL
            self.trackURL = trackURL
        }
    }

    private enum State {
        case idle
        case loading
        case ready
    }

    private let defaultWidgetJSURL = "https://static.userback.io/widget/v1.js"
    private let flushInterval: TimeInterval = 1.0
    private let bufferLimit = 50

    private var configuration: Configuration?
    private var state: State = .idle
    private var webView: WKWebView?
    private var eventBuffer: [[String: Any]] = []
    private var flushTimer: Timer?
    private var messageHandlerProxy: WeakScriptMessageHandler?
    private var activationObservers: [NSObjectProtocol] = []
    private var pendingWindowAttachment = false
    private var latestWidgetConfig: [String: Any]?

    public var onWidgetConfigLoaded: (([String: Any]) -> Void)?

    private override init() {
        super.init()
    }

    public func configure(
        accessToken: String,
        widgetJSURL: String,
        userData: [String: Any]? = nil,
        widgetCSS: String? = nil,
        surveyURL: String? = nil,
        requestURL: String? = nil,
        trackURL: String? = nil
    ) {
        configuration = Configuration(
            accessToken: accessToken,
            widgetJSURL: widgetJSURL,
            userData: userData ?? [:],
            widgetCSS: widgetCSS,
            surveyURL: surveyURL,
            requestURL: requestURL,
            trackURL: trackURL
        )
    }

    public func start(
        accessToken: String,
        userData: [String: Any] = [:],
        widgetCSS: String? = nil,
        surveyURL: String? = nil,
        requestURL: String? = nil,
        trackURL: String? = nil,
        widgetJSURL: String? = nil
    ) {
        let config = Configuration(
            accessToken: accessToken,
            widgetJSURL: widgetJSURL ?? defaultWidgetJSURL,
            userData: userData,
            widgetCSS: widgetCSS,
            surveyURL: surveyURL,
            requestURL: requestURL,
            trackURL: trackURL
        )
        start(with: config)
    }

    public func start(with configuration: Configuration) {
        self.configuration = configuration

        if webView != nil {
            reloadWidget()
            return
        }

        guard activeWindow() != nil else {
            pendingWindowAttachment = true
            scheduleWindowAttachRetry()
            return
        }

        let webView = createWebView()
        self.webView = webView
        state = .loading
        startFlushTimerIfNeeded()

        if !attachToWindow(webView) {
            scheduleWindowAttachRetry()
        }
    }

    public func stop() {
        flushTimer?.invalidate()
        flushTimer = nil
        eventBuffer.removeAll()
        state = .idle
        webView?.removeFromSuperview()
        webView = nil
        pendingWindowAttachment = false
        latestWidgetConfig = nil
        removeActivationObservers()
    }

    public func widgetConfig() -> [String: Any]? {
        latestWidgetConfig
    }

    public func widgetConfigValue<T>(forKey key: String) -> T? {
        latestWidgetConfig?[key] as? T
    }

    public func portalTarget() -> String? {
        latestWidgetConfig?["portal_target"] as? String
    }

    public func roadmapTarget() -> String? {
        return latestWidgetConfig?["roadmap_target"] as? String
    }

    public func portalURL() -> URL? {
        guard let raw = latestWidgetConfig?["portal_url"] as? String,
              !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    public func startNativeRecording() {
        log("Native recording hook called. Plug in your native recorder integration here.")
    }

    public func sendNativeEvent(_ event: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(event) else {
            log("Dropping invalid native event payload.")
            return
        }

        if eventBuffer.count >= bufferLimit {
            eventBuffer.removeFirst(eventBuffer.count - bufferLimit + 1)
        }
        eventBuffer.append(event)
        flushBufferedEvents()
    }

    public func isLoaded(completion: @escaping (Bool) -> Void) {
        evaluateJavaScript("window.Userback && typeof window.Userback.isLoaded === 'function' ? !!window.Userback.isLoaded() : false") { result, _ in
            completion(result as? Bool ?? false)
        }
    }

    public func initWidget(options: [String: Any] = [:]) {
        guard let config = configuration else { return }
        let token = jsValueLiteral(config.accessToken)
        let optionsLiteral = jsValueLiteral(options)
        evaluateJavaScript("window.Userback && typeof window.Userback.init === 'function' && window.Userback.init(\(token), \(optionsLiteral));")
    }

    public func startWidget() {
        callUserback(function: "start")
    }

    public func refresh(refreshFeedback: Bool = true, refreshSurvey: Bool = true) {
        callUserback(function: "refresh", arguments: [refreshFeedback, refreshSurvey])
    }

    public func destroy(keepInstance: Bool = false, keepRecorder: Bool = false) {
        callUserback(function: "destroy", arguments: [keepInstance, keepRecorder])
    }

    public func openForm(mode: String = "general", directTo: String? = nil) {
        if webView == nil {
            guard activeWindow() != nil else {
                pendingWindowAttachment = true
                scheduleWindowAttachRetry()
                return
            }

            let createdWebView = createWebView()
            self.webView = createdWebView
            state = .loading
            startFlushTimerIfNeeded()

            if !attachToWindow(createdWebView) {
                scheduleWindowAttachRetry()
                return
            }
        }

        if shouldLoadAsWidgetScript(configuration?.widgetJSURL) {
            callUserback(function: "openForm", arguments: [mode, directTo])
        }

        guard let webView, let window = activeWindow() else { return }
        let containerView = presentationContainerView(for: window)
        if webView.superview !== containerView {
            webView.removeFromSuperview()
            containerView.addSubview(webView)
        }
        containerView.bringSubviewToFront(webView)
        webView.frame = containerView.bounds
        webView.isHidden = false
        webView.alpha = 1
        webView.transform = .identity
        webView.isUserInteractionEnabled = true
    }

    public func openPortal() {
        switch portalTarget()?.lowercased() {
            case "widget":
                callUserback(function: "openPortal", arguments: ["portal"])
            case "redirect", "window":
                if let url = portalURL() {
                    openURL(url)
                    return
                }
                callUserback(function: "openPortal")
            default:
                callUserback(function: "openPortal")
        }
    }

    public func openRoadmap() {
        switch roadmapTarget()?.lowercased() {
            case "widget":
                callUserback(function: "openPortal", arguments: ["roadmap"])
            case "redirect", "window":
                if let url = portalURL() {
                    openURL(url)
                    return
                }
                callUserback(function: "openRoadmap")
            default:
                callUserback(function: "openRoadmap")
        }
    }

    public func openAnnouncement() {
        switch (latestWidgetConfig?["announcement_target"] as? String)?.lowercased() {
            case "widget":
                callUserback(function: "openPortal", arguments: ["announcement"])
            case "redirect", "window":
                if let url = portalURL() {
                    openURL(url)
                    return
                }
                callUserback(function: "openAnnouncement")
            default:
                callUserback(function: "openAnnouncement")
        }
    }

    // Disable showLauncher and hideLauncher for now as they require more discussion on expected behavior and API design
    // public func showLauncher() {
    //     // TODO: need discuss
    // }

    // public func hideLauncher() {
    //     // TODO: need discuss
    // }

    public func setEmail(_ email: String) {
        callUserback(function: "setEmail", arguments: [email])
    }

    public func setName(_ name: String) {
        callUserback(function: "setName", arguments: [name])
    }

    public func setCategories(_ categories: String) {
        callUserback(function: "setCategories", arguments: [categories])
    }

    public func setPriority(_ priority: String) {
        callUserback(function: "setPriority", arguments: [priority])
    }

    public func setTheme(_ theme: String) {
        callUserback(function: "setTheme", arguments: [theme])
    }

    public func startSessionReplay(options: [String: Any] = [:]) {
        callUserback(function: "startSessionReplay", arguments: [options])
    }

    public func stopSessionReplay() {
        callUserback(function: "stopSessionReplay")
    }

    public func addCustomEvent(_ title: String, details: [String: Any]? = nil) {
        callUserback(function: "addCustomEvent", arguments: [title, details])
    }

    public func identify(userID: Any, userInfo: [String: Any]? = nil) {
        callUserback(function: "identify", arguments: [userID, userInfo])
    }

    public func clearIdentity() {
        callUserback(function: "identify", arguments: [-1])
    }

    public func setData(_ data: [String: Any]) {
        callUserback(function: "setData", arguments: [data])
    }

    public func addHeader(key: String, value: String) {
        callUserback(function: "addHeader", arguments: [key, value])
    }

    public func close() {
        guard let webView else { return }
        evaluateJavaScript("window.Userback && window.Userback.close && window.Userback.close();")
        webView.isUserInteractionEnabled = false
        webView.isHidden = true
        webView.transform = .identity
        webView.alpha = 0
        webView.removeFromSuperview()
    }

    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let controller = WKUserContentController()
        messageHandlerProxy = WeakScriptMessageHandler(delegate: self)
        if let messageHandlerProxy {
            controller.add(messageHandlerProxy, name: "userbackSDK")
        }

        let script = WKUserScript(
            source: buildInjectedJS(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(script)
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.alpha = 0
        webView.isOpaque = false
        webView.isHidden = true
        webView.isUserInteractionEnabled = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1"
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        return webView
    }

    @discardableResult
    private func attachToWindow(_ webView: WKWebView) -> Bool {
        guard let window = activeWindow() else {
            return false
        }
        let containerView = presentationContainerView(for: window)

        let configuredURLString = configuration?.widgetJSURL ?? defaultWidgetJSURL
        if shouldLoadAsWidgetScript(configuredURLString) {
                let html = """
                <html>
                    <head>
                        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\">
                    </head>
                    <body>
                        <script src=\"\(configuredURLString)\"></script>
                    </body>
                </html>
                """
                webView.loadHTMLString(html, baseURL: URL(string: "https://static.userback.io"))
        } else if let url = URL(string: configuredURLString) {
                webView.load(URLRequest(url: url))
        }

        if webView.superview !== containerView {
            webView.removeFromSuperview()
            containerView.addSubview(webView)
        }
        containerView.bringSubviewToFront(webView)
        pendingWindowAttachment = false
        removeActivationObservers()
        return true
    }

    private func presentationContainerView(for window: UIWindow) -> UIView {
        if let rootView = window.rootViewController?.view {
            return rootView
        }
        return window
    }

    private func reloadWidget() {
        guard let webView else { return }

        webView.configuration.userContentController.removeAllUserScripts()
        let script = WKUserScript(
            source: buildInjectedJS(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(script)

        if !attachToWindow(webView) {
            scheduleWindowAttachRetry()
        }
        state = .loading
    }

    private func shouldLoadAsWidgetScript(_ urlString: String?) -> Bool {
        guard let urlString,
              let url = URL(string: urlString),
              !url.path.isEmpty else {
            return true
        }

        return url.path.lowercased().hasSuffix(".js")
    }

    private func scheduleWindowAttachRetry() {
        pendingWindowAttachment = true
        guard activationObservers.isEmpty else { return }

        log("No active window yet. Deferring SDK attachment until app becomes active.")

        let center = NotificationCenter.default
        let sceneObserver = center.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tryAttachPendingWebView()
            }
        }

        let appObserver = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tryAttachPendingWebView()
            }
        }

        activationObservers = [sceneObserver, appObserver]
    }

    private func tryAttachPendingWebView() {
        guard pendingWindowAttachment else { return }

        if webView == nil {
            guard activeWindow() != nil else { return }
            let webView = createWebView()
            self.webView = webView
            state = .loading
            startFlushTimerIfNeeded()
        }

        guard let webView else { return }
        _ = attachToWindow(webView)
    }

    private func removeActivationObservers() {
        guard !activationObservers.isEmpty else { return }
        let center = NotificationCenter.default
        activationObservers.forEach { center.removeObserver($0) }
        activationObservers.removeAll()
    }

    private func startFlushTimerIfNeeded() {
        guard flushTimer == nil else { return }

        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.flushBufferedEvents()
        }
    }

    private func flushBufferedEvents() {
        guard state == .ready else { return }
        guard !eventBuffer.isEmpty else { return }

        let pending = eventBuffer
        eventBuffer.removeAll()

        for event in pending {
            guard let json = jsonString(from: event) else { continue }
            evaluateJavaScript("window.Userback && window.Userback.addNativeEvent(\(json));")
        }
    }

    private func nativeUAData() -> [String: Any] {
        let device = UIDevice.current
        return [
            "platform": "ios",
            "platformVersion": device.systemVersion,
            "model": device.model,
            "sdkVersion": Self.sdkVersion
        ]
    }

    private func buildInjectedJS() -> String {
        let device = UIDevice.current
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let fullAppVersion = buildNumber.isEmpty ? appVersion : "\(appVersion) (\(buildNumber))"

        let screen = UIScreen.main.bounds
        let scale = UIScreen.main.scale

        let nativeEnv: [String: Any] = [
            "platform": "ios",
            "sdk_version": Self.sdkVersion,
            "app_version": fullAppVersion,
            "os_version": device.systemVersion,
            "device_model": device.model,
            "device_name": device.name,
            "resolution_x": Int(screen.width * scale),
            "resolution_y": Int(screen.height * scale),
            "screen_width_pt": Int(screen.width),
            "screen_height_pt": Int(screen.height),
            "dpi_scale": scale
        ]

        return """
        window.Userback = window.Userback || {};
        Userback.load_type = "mobile_sdk";
        Userback.access_token = \(jsonLiteral(configuration?.accessToken));
        Userback.user_data = \(jsonLiteral(configuration?.userData));
        Userback.widget_css = \(jsonLiteral(configuration?.widgetCSS));
        Userback.survey_url = \(jsonLiteral(configuration?.surveyURL));
        Userback.request_url = \(jsonLiteral(configuration?.requestURL));
        Userback.track_url = \(jsonLiteral(configuration?.trackURL));
        Userback.native_env = \(jsonLiteral(nativeEnv));
        Userback.native_ua_data = \(jsonLiteral(nativeUAData()));
        """
    }

    private func jsonLiteral(_ value: Any?) -> String {
        guard let value else { return "null" }

        if let string = value as? String {
            return jsQuotedString(string)
        }

        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "null"
        }

        return json
    }

    private func jsonString(from value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func jsQuotedString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let jsonArray = String(data: data, encoding: .utf8),
              jsonArray.count >= 2 else {
            return "\"\""
        }
        return String(jsonArray.dropFirst().dropLast())
    }

    private func jsValueLiteral(_ value: Any?) -> String {
        guard let value else { return "null" }

        if let string = value as? String {
            return jsQuotedString(string)
        }

        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }

        if let int = value as? Int {
            return String(int)
        }

        if let double = value as? Double {
            return String(double)
        }

        if let float = value as? Float {
            return String(float)
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "null"
        }

        return json
    }

    private func callUserback(function: String, arguments: [Any?] = []) {
        let args = arguments.map { jsValueLiteral($0) }.joined(separator: ", ")
        evaluateJavaScript("window.Userback && typeof window.Userback.\(function) === 'function' && window.Userback.\(function)(\(args));")
    }

    private func openURL(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)? = nil) {
        webView?.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.log("JavaScript evaluation error: \(error.localizedDescription)")
            }
            completion?(result, error)
        }
    }

    private func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })?
            .windows
            .first(where: { $0.isKeyWindow })
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })?
            .windows
            .first(where: { !$0.isHidden })
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first
    }

    private func log(_ message: String) {
        #if DEBUG
        print("UserbackSDK: \(message)")
        #endif
    }
}

extension UserbackSDK: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state = .ready
        flushBufferedEvents()
    }
}

extension UserbackSDK: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "userbackSDK" else { return }

        guard let body = parseMessageBody(message.body),
              let type = body["type"] as? String else {
            if let body = message.body as? String,
               body.caseInsensitiveCompare("close") == .orderedSame {
                close()
                return
            }
            log("Ignoring unsupported script message body: \(message.body)")
            return
        }

        switch type.lowercased() {
            case "load":
                guard let payload = body["payload"] as? [String: Any] else {
                    log("Received 'load' message without config payload.")
                    return
                }
                latestWidgetConfig = payload
                onWidgetConfigLoaded?(payload)
            case "close":
                close()
            default:
                break
        }

        if let event = body["event"] as? String,
           event.caseInsensitiveCompare("close") == .orderedSame {
            close()
            return
        }
    }

    private func parseMessageBody(_ rawBody: Any) -> [String: Any]? {
        if let body = rawBody as? [String: Any] {
            return body
        }

        if let jsonString = rawBody as? String,
           let data = jsonString.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let body = object as? [String: Any] {
            return body
        }

        return nil
    }
}

#else

public enum UserbackSDK {
    public static let sdkVersion = "1.0.0"
    public static func version() -> String { sdkVersion }
}

#endif
