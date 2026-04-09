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

    private enum WidgetPosition: String {
        case w
        case e
        case sw
        case se
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
    private var systemWarningObservers: [NSObjectProtocol] = []
    private var orientationObserver: NSObjectProtocol?
    private var pendingWindowAttachment = false
    private var formOpenTimeoutTask: DispatchWorkItem?
    private var latestWidgetConfig: [String: Any]?
    private var latestWidgetSize: CGSize?
    private var webViewLayoutConstraints: [NSLayoutConstraint] = []
    private weak var webViewContainerView: UIView?

    public var onWidgetConfigLoaded: (([String: Any]) -> Void)?
    public var onWidgetResize: ((CGSize) -> Void)?

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
        startNativeObserversIfNeeded()

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
        NSLayoutConstraint.deactivate(webViewLayoutConstraints)
        webViewLayoutConstraints.removeAll()
        webViewContainerView = nil
        webView?.removeFromSuperview()
        webView = nil
        pendingWindowAttachment = false
        latestWidgetConfig = nil
        latestWidgetSize = nil
        stopNativeObserversIfNeeded()
        removeActivationObservers()
    }

    public func widgetConfig() -> [String: Any]? {
        latestWidgetConfig
    }

    public func widgetSize() -> CGSize? {
        latestWidgetSize
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

    private func startNativeObserversIfNeeded() {
        LogObserver.shared.start()
        NetworkObserver.shared.start()
        startSystemWarningObserversIfNeeded()
        startOrientationObserverIfNeeded()
    }

    private func stopNativeObserversIfNeeded() {
        stopSystemWarningObserversIfNeeded()
        stopOrientationObserver()
        LogObserver.shared.stop()
        NetworkObserver.shared.stop()
    }

    private func startSystemWarningObserversIfNeeded() {
        guard systemWarningObservers.isEmpty else { return }

        let center = NotificationCenter.default
        let memoryObserver = center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendSystemWarningEvent(
                    name: "memory_warning",
                    message: "iOS memory warning received.",
                    trackType: "warn"
                )
            }
        }

        let thermalObserver = center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleThermalStateChange()
            }
        }

        systemWarningObservers = [memoryObserver, thermalObserver]
    }

    private func stopSystemWarningObserversIfNeeded() {
        guard !systemWarningObservers.isEmpty else { return }
        let center = NotificationCenter.default
        systemWarningObservers.forEach { center.removeObserver($0) }
        systemWarningObservers.removeAll()
    }

    private func startOrientationObserverIfNeeded() {
        guard orientationObserver == nil else { return }
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let orientation = UIDevice.current.orientation
                let screenWidth = Int(UIScreen.main.bounds.width)
                let screenHeight = Int(UIScreen.main.bounds.height)
                self.log("Device orientation changed: \(orientation.rawValue), screenWidth: \(screenWidth)")
                self.setNativeResizing(true)
                self.sendMessageToJavaScript(
                    ["type": "native_rotate", "payload": ["orientation": orientation.rawValue, "screenWidth": screenWidth, "screenHeight": screenHeight]],
                    customEventName: "userback:rotate",
                    successLogPrefix: "Rotate"
                )
                self.latestWidgetSize = nil
                self.applyLatestWidgetSizeToWebViewIfNeeded()
            }
        }
    }

    private func stopOrientationObserver() {
        guard let observer = orientationObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        orientationObserver = nil
    }

    private func handleThermalStateChange() {
        let thermalState = ProcessInfo.processInfo.thermalState

        let stateName: String
        let trackType: String

        switch thermalState {
            case .nominal:
                return
            case .fair:
                stateName = "fair"
                trackType = "warn"
            case .serious:
                stateName = "serious"
                trackType = "warn"
            case .critical:
                stateName = "critical"
                trackType = "error"
            @unknown default:
                stateName = "unknown"
                trackType = "warn"
        }

        sendSystemWarningEvent(
            name: "thermal_state",
            message: "iOS thermal state changed to \(stateName).",
            trackType: trackType,
            additional: ["thermal_state": stateName]
        )
    }

    private func sendSystemWarningEvent(
        name: String,
        message: String,
        trackType: String,
        additional: [String: Any] = [:]
    ) {
        var event: [String: Any] = [
            "type": "warn",
            "_track_type": trackType,
            "name": name,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]

        for (key, value) in additional {
            event[key] = value
        }

        sendNativeEvent(event)
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

    public func openForm(mode: String = "", directTo: String? = nil) {
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

        // Keep the current host stable while the widget is open. Re-parenting during
        // transient WebKit presentations (e.g. select/context UI) causes visible jumps.
        if webView.superview == nil || webView.window !== window {
            if !attachToWindow(webView) {
                scheduleWindowAttachRetry()
                return
            }
        }

        webView.superview?.bringSubviewToFront(webView)
        webView.isHidden = true
        webView.alpha = 0
        webView.transform = .identity
        webView.isUserInteractionEnabled = false

        formOpenTimeoutTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.log("openForm timed out — JS SDK did not respond. Closing WebView.")
            self.close()
        }
        formOpenTimeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
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
        webView.isUserInteractionEnabled = false
        webView.isHidden = true
        webView.transform = .identity
        webView.alpha = 0
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
        applyWebViewLayerStyle(to: webView)
        webView.alpha = 0
        webView.isOpaque = false
        webView.isHidden = true
        webView.isUserInteractionEnabled = false
        // Prevent any automatic content inset adjustments to avoid layout issues with the widget.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
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
                        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover\">
                        <style>
                            html, body {
                                margin: 0;
                                padding: 0;
                                width: 100%;
                                height: 100%;
                                background: transparent;
                            }
                        </style>
                    </head>
                    <body>
                        <script src=\"\(configuredURLString)\"></script>
                    </body>
                </html>
                """
                let baseURL = URL(string: configuredURLString).flatMap { URL(string: "\($0.scheme ?? "https")://\($0.host ?? "")") }
                webView.loadHTMLString(html, baseURL: baseURL)
        } else if let url = URL(string: configuredURLString) {
                webView.load(URLRequest(url: url))
        }

        if webView.superview !== containerView {
            pinWebViewToContainer(webView, containerView: containerView)
        } else if webView.translatesAutoresizingMaskIntoConstraints {
            pinWebViewToContainer(webView, containerView: containerView)
        }

        containerView.bringSubviewToFront(webView)
        pendingWindowAttachment = false
        removeActivationObservers()
        return true
    }

    private func presentationContainerView(for window: UIWindow) -> UIView {
        if let presentingViewController = presentingViewController(for: window) {
            return presentingViewController.view
        }
        return window
    }

    private func presentingViewController(for window: UIWindow) -> UIViewController? {
        if let root = window.rootViewController {
            return topMostViewController(from: root)
        }
        return nil
    }

    private func topMostViewController(from root: UIViewController) -> UIViewController {
        var current = root

        while true {
            if let presented = current.presentedViewController {
                current = presented
                continue
            }

            if let nav = current as? UINavigationController,
               let visible = nav.visibleViewController {
                current = visible
                continue
            }

            if let tab = current as? UITabBarController,
               let selected = tab.selectedViewController {
                current = selected
                continue
            }

            break
        }

        return current
    }

    private func pinWebViewToContainer(_ webView: WKWebView, containerView: UIView) {
        NSLayoutConstraint.deactivate(webViewLayoutConstraints)
        webViewLayoutConstraints.removeAll()
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(webView)
        webViewContainerView = containerView
        applyWidgetSizeConstraints(to: webView, in: containerView)
    }

    private func applyWidgetSizeConstraints(to webView: WKWebView, in containerView: UIView) {
        NSLayoutConstraint.deactivate(webViewLayoutConstraints)

        let containerWidth = containerView.bounds.width
        let containerHeight = containerView.bounds.height
        let isModal = latestWidgetConfig?["use_modal"] as? Bool == true

        if !isModal, let size = latestWidgetSize, size.width > 0, size.height > 0, containerWidth > 800 {
            var constraints: [NSLayoutConstraint] = [
                webView.widthAnchor.constraint(equalToConstant: size.width),
                webView.heightAnchor.constraint(equalToConstant: size.height),
            ]

            switch widgetPositionFromConfig() {
                case .w:
                    constraints.append(webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor))
                    constraints.append(webView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor))
                case .e:
                    constraints.append(webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor))
                    constraints.append(webView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor))
                case .sw:
                    constraints.append(webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor))
                    constraints.append(webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor))
                case .se:
                    constraints.append(webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor))
                    constraints.append(webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor))
            }

            webViewLayoutConstraints = constraints
        } else {
            webViewLayoutConstraints = [
                webView.widthAnchor.constraint(equalToConstant: containerWidth),
                webView.heightAnchor.constraint(equalToConstant: containerHeight),
                webView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                webView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            ]
        }

        NSLayoutConstraint.activate(webViewLayoutConstraints)
    }

    private func widgetPositionFromConfig() -> WidgetPosition {
        guard let rawPosition = latestWidgetConfig?["position"] as? String,
              let position = WidgetPosition(rawValue: rawPosition.lowercased()) else {
            return .se
        }
        return position
    }

    private func applyWebViewLayerStyle(to webView: WKWebView) {
        let screenWidth = UIScreen.main.bounds.width
        if screenWidth > 800 {
            webView.layer.borderWidth = 0
            webView.layer.cornerRadius = 0
            webView.layer.shadowColor = UIColor.black.cgColor
            webView.layer.shadowOpacity = 0.1
            webView.layer.shadowOffset = CGSize(width: 0, height: 0)
            webView.layer.shadowRadius = 10
            webView.layer.masksToBounds = false
            webView.scrollView.layer.cornerRadius = 0
            webView.scrollView.clipsToBounds = false
        } else {
            webView.layer.borderWidth = 0
            webView.layer.cornerRadius = 0
            webView.layer.shadowOpacity = 0
            webView.layer.masksToBounds = true
            webView.scrollView.layer.cornerRadius = 0
            webView.scrollView.clipsToBounds = false
        }
    }

    private func setNativeResizing(_ resizing: Bool) {
        webView?.evaluateJavaScript("window.__nativeResizing = \(resizing);")
    }

    private func applyLatestWidgetSizeToWebViewIfNeeded() {
        guard let webView, let containerView = webView.superview ?? webViewContainerView else {
            return
        }
        applyWebViewLayerStyle(to: webView)
        applyWidgetSizeConstraints(to: webView, in: containerView)
        containerView.layoutIfNeeded()
        applyBreakpoint(in: webView)
        if state == .ready {
            let containerBounds = containerView.bounds
            let deviceWidth = Int(containerBounds.width)
            let deviceHeight = Int(containerBounds.height)
            sendMessageToJavaScript(
                ["type": "native_device_size", "payload": ["deviceWidth": deviceWidth, "deviceHeight": deviceHeight]],
                customEventName: "userback:nativeDeviceSize",
                successLogPrefix: "Device size"
            )
        }
    }

    private func applyBreakpoint(in webView: WKWebView) {
        let isTablet = UIScreen.main.bounds.width > 800
        webView.evaluateJavaScript("""
            var container = document.querySelector('.userback-button-container');
            if (container) {
                if (\(isTablet)) {
                    container.setAttribute('data-breakpoint', 'tablet');
                } else {
                    container.removeAttribute('data-breakpoint');
                }
            }
        """)
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
            sendNativeEventToJavaScript(event)
        }
    }

    private func sendNativeEventToJavaScript(_ event: [String: Any]) {
        let message: [String: Any] = [
            "type": "native_event",
            "payload": event
        ]

        let customEventName = nativeEventName(for: event)

        sendMessageToJavaScript(
            message,
            customEventName: customEventName,
            successLogPrefix: "Native event"
        )
    }

    private func nativeEventName(for event: [String: Any]) -> String {
        let eventType = (event["eventType"] as? String)?.lowercased()

        switch eventType {
            case "network":
                return "userback:nativeNetworkEvent"
            default:
                return "userback:nativeLogEvent"
        }
    }

    private func nativeUAData() -> [String: Any] {
        let device = UIDevice.current
        return [
            "platform": "ios",
            "platformVersion": device.systemVersion,
            "model": deviceModelIdentifier(),
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
            "device_model": deviceModelIdentifier(),
            "device_name": device.name,
            "resolution_x": Int(screen.width * scale),
            "resolution_y": Int(screen.height * scale),
            "screen_width_pt": Int(screen.width),
            "screen_height_pt": Int(screen.height),
            "dpi_scale": scale
        ]

        var devOverrides = ""
        if let widgetCSS = configuration?.widgetCSS { devOverrides += "Userback.widget_css = \(jsonLiteral(widgetCSS));\n" }
        if let surveyURL = configuration?.surveyURL { devOverrides += "Userback.survey_url = \(jsonLiteral(surveyURL));\n" }
        if let requestURL = configuration?.requestURL { devOverrides += "Userback.request_url = \(jsonLiteral(requestURL));\n" }
        if let trackURL = configuration?.trackURL { devOverrides += "Userback.track_url = \(jsonLiteral(trackURL));\n" }

        return """
        window.Userback = window.Userback || {};
        Userback.load_type = "mobile_sdk";
        Userback.access_token = \(jsonLiteral(configuration?.accessToken));
        Userback.user_data = \(jsonLiteral(configuration?.userData));
        \(devOverrides)
        Userback.native_env = \(jsonLiteral(nativeEnv));
        Userback.native_ua_data = \(jsonLiteral(nativeUAData()));
        """
    }

    private func deviceModelIdentifier() -> String {
        #if targetEnvironment(simulator)
        let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { buffer in
            buffer.compactMap { $0 == 0 ? nil : String(UnicodeScalar($0)) }.joined()
        }
        #endif
        let modelMap: [String: String] = [
            // iPhone
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            // iPad
            "iPad13,18": "iPad (10th generation)",
            "iPad13,19": "iPad (10th generation)",
            "iPad14,1":  "iPad mini (6th generation)",
            "iPad14,2":  "iPad mini (6th generation)",
            "iPad13,4":  "iPad Pro 11\" (3rd generation)",
            "iPad13,5":  "iPad Pro 11\" (3rd generation)",
            "iPad13,6":  "iPad Pro 11\" (3rd generation)",
            "iPad13,7":  "iPad Pro 11\" (3rd generation)",
            "iPad13,8":  "iPad Pro 12.9\" (5th generation)",
            "iPad13,9":  "iPad Pro 12.9\" (5th generation)",
            "iPad13,10": "iPad Pro 12.9\" (5th generation)",
            "iPad13,11": "iPad Pro 12.9\" (5th generation)",
            "iPad14,3":  "iPad Pro 11\" (4th generation)",
            "iPad14,4":  "iPad Pro 11\" (4th generation)",
            "iPad14,5":  "iPad Pro 12.9\" (6th generation)",
            "iPad14,6":  "iPad Pro 12.9\" (6th generation)",
            "iPad16,3":  "iPad Pro 11\" (M4)",
            "iPad16,4":  "iPad Pro 11\" (M4)",
            "iPad16,5":  "iPad Pro 13\" (M4)",
            "iPad16,6":  "iPad Pro 13\" (M4)",
            "iPad13,1":  "iPad Air (4th generation)",
            "iPad13,2":  "iPad Air (4th generation)",
            "iPad13,16": "iPad Air (5th generation)",
            "iPad13,17": "iPad Air (5th generation)",
            "iPad14,8":  "iPad Air 11\" (M2)",
            "iPad14,9":  "iPad Air 11\" (M2)",
            "iPad14,10": "iPad Air 13\" (M2)",
            "iPad14,11": "iPad Air 13\" (M2)",
        ]
        return modelMap[identifier] ?? identifier
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

        guard let body = parseMessageBody(message.body) else {
            if let body = message.body as? String,
               body.caseInsensitiveCompare("close") == .orderedSame {
                close()
                return
            }
            log("Ignoring unsupported script message body: \(message.body)")
            return
        }

        guard let messageType = (body["type"] as? String) ?? (body["event"] as? String) else {
            log("Ignoring script message without type/event: \(body)")
            return
        }

        switch messageType.lowercased() {
            case "load":
                guard let payload = body["payload"] as? [String: Any] else {
                    log("Received 'load' message without config payload.")
                    return
                }
                latestWidgetConfig = payload
                applyLatestWidgetSizeToWebViewIfNeeded()
                onWidgetConfigLoaded?(payload)
            case "widget_resize":
                handleWidgetResize(body)
            case "widget_action":
                handleWidgetAction(body)
            case "open_feedback_view":
                latestWidgetSize = nil
                applyLatestWidgetSizeToWebViewIfNeeded()
            case "load_error":
                let message = (body["payload"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                log("JS SDK load error: \(message). Closing WebView.")
                close()
            case "hcaptcha_required":
                let message = (body["payload"] as? [String: Any])?["message"] as? String ?? "hCaptcha required"
                log("JS SDK hCaptcha required: \(message). Closing WebView.")
            case "close":
                close()
            default:
                break
        }
    }

    private func handleWidgetAction(_ body: [String: Any]) {
        guard let payload = body["payload"] as? [String: Any],
              let action = payload["action"] as? String else {
            log("Received 'widget_action' message without valid payload/action.")
            return
        }

        let target = (payload["target"] as? String)?.lowercased()

        switch action.lowercased() {
            case "gotoportal":
                openPortal(forcedTarget: target)
            case "openhelp":
                openHelp(forcedTarget: target)
            case "gotoannouncement":
                openAnnouncement(forcedTarget: target)
            case "gotoroadmap":
                openRoadmap(forcedTarget: target)
            case "attachscreenshot":
                attachScreenshotAndSendToJS()
            default:
                log("Ignoring unsupported widget action: \(action)")
        }
    }

    private func handleWidgetResize(_ body: [String: Any]) {
        guard let payload = body["payload"] as? [String: Any] else {
            log("Received 'widget_resize' message without payload.")
            return
        }

        let width = (payload["width"] as? NSNumber)?.doubleValue
            ?? (payload["width"] as? Double)
            ?? (payload["width"] as? Int).map(Double.init)
            ?? (payload["width"] as? String).flatMap(Double.init)
        let height = (payload["height"] as? NSNumber)?.doubleValue
            ?? (payload["height"] as? Double)
            ?? (payload["height"] as? Int).map(Double.init)
            ?? (payload["height"] as? String).flatMap(Double.init)

        guard let width, let height, width >= 0, height >= 0 else {
            log("Received 'widget_resize' message with invalid width/height.")
            return
        }

        let size = CGSize(width: width, height: height + 20)
        let isLast = payload["last"] as? Bool == true
        latestWidgetSize = size
        formOpenTimeoutTask?.cancel()
        formOpenTimeoutTask = nil
        applyLatestWidgetSizeToWebViewIfNeeded()
        if isLast {
            webView?.isHidden = false
            webView?.alpha = 1
            webView?.isUserInteractionEnabled = true
        }
        onWidgetResize?(size)
    }

    private func openPortal(forcedTarget target: String?) {
        guard let target else {
            openPortal()
            return
        }

        switch target {
            case "widget":
                callUserback(function: "openPortal", arguments: ["portal"])
            case "redirect", "window":
                if let url = portalURL() {
                    openURL(url)
                    return
                }
                callUserback(function: "openPortal")
            default:
                openPortal()
        }
    }

    private func openRoadmap(forcedTarget target: String?) {
        guard let target else {
            openRoadmap()
            return
        }

        switch target {
            case "widget":
                callUserback(function: "openPortal", arguments: ["roadmap"])
            case "redirect", "window":
                if let url = portalURL() {
                    openURL(url)
                    return
                }
                callUserback(function: "openRoadmap")
            default:
                openRoadmap()
        }
    }

    private func openAnnouncement(forcedTarget target: String?) {
        guard let target else {
            openAnnouncement()
            return
        }

        switch target {
            case "widget":
                callUserback(function: "openPortal", arguments: ["announcement"])
            case "redirect", "window":
                if let url = portalURL() {
                    openURL(url)
                    return
                }
                callUserback(function: "openAnnouncement")
            default:
                openAnnouncement()
        }
    }

    private func openHelp(forcedTarget target: String?) {
        switch target {
            case "redirect", "window":
                if let url = helpURL() {
                    openURL(url)
                    return
                }
                callUserback(function: "openHelp")
            default:
                callUserback(function: "openHelp")
        }
    }

    private func helpURL() -> URL? {
        guard let raw = latestWidgetConfig?["help_link"] as? String,
              !raw.isEmpty else {
            return portalURL()
        }
        return URL(string: raw)
    }

    private func attachScreenshotAndSendToJS() {
        guard let screenshotDataURL = captureActiveWindowScreenshotDataURL() else {
            log("Failed to capture screenshot for attachScreenshot action.")
            return
        }

        sendScreenshotToJavaScript(screenshotDataURL)
    }

    private func captureActiveWindowScreenshotDataURL() -> String? {
        guard let window = activeWindow() else { return nil }

        let savedOffset = webView?.scrollView.contentOffset

        webView?.isHidden = true

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = UIScreen.main.scale

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: rendererFormat)
        let screenshot = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        webView?.isHidden = false

        if let offset = savedOffset {
            webView?.scrollView.setContentOffset(offset, animated: false)
        }

        guard let data = screenshot.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private func sendScreenshotToJavaScript(_ dataURL: String) {
        let message: [String: Any] = [
            "type": "native_screenshot",
            "payload": [
                "data_url": dataURL
            ]
        ]

        sendMessageToJavaScript(
            message,
            customEventName: "userback:nativeScreenshot",
            successLogPrefix: "Screenshot"
        )
    }

    private func sendMessageToJavaScript(
        _ message: [String: Any],
        customEventName: String,
        successLogPrefix: String
    ) {
        var enrichedMessage = message
        enrichedMessage["mobileSDK"] = true

        if var payload = enrichedMessage["payload"] as? [String: Any] {
            payload["mobileSDK"] = true
            enrichedMessage["payload"] = payload
        }

        guard let messageJSON = jsonString(from: enrichedMessage) else {
            log("\(successLogPrefix) payload serialization failed for JS delivery.")
            return
        }

        let eventNameLiteral = jsQuotedString(customEventName)

        let script = """
        (function() {
            var message = \(messageJSON);
            var eventName = \(eventNameLiteral);
            var routes = [];

            try {
                window.dispatchEvent(new CustomEvent(eventName, { detail: message }));
                routes.push('window.dispatchEvent');
            } catch (error) {
                routes.push('window.dispatchEvent:error');
            }
            return routes.join(', ');
        })();
        """

        evaluateJavaScript(script) { [weak self] result, _ in
            guard let route = result as? String else {
                self?.log("\(successLogPrefix) queued for JS, but delivery route was not confirmed.")
                return
            }
            self?.log("\(successLogPrefix) delivered to JS via: \(route)")
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
