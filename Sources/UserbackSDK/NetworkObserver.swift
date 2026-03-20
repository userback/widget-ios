import Foundation

#if canImport(UIKit) && canImport(WebKit)

@MainActor
public final class NetworkObserver {
    public static let shared = NetworkObserver()

    private var isRegistered = false

    private init() {}

    public func start() {
        guard !isRegistered else { return }
        URLProtocol.registerClass(UserbackNetworkURLProtocol.self)
        isRegistered = true
        print("NetworkObserver started")
    }

    public func stop() {
        guard isRegistered else { return }
        URLProtocol.unregisterClass(UserbackNetworkURLProtocol.self)
        isRegistered = false
        print("NetworkObserver stopped")
    }
}

private final class UserbackNetworkURLProtocol: URLProtocol {
    private static let handledKey = "HandledByUserbackNetworkObserver"

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var sessionDelegate: NetworkSessionDelegate?
    private var responseBodySize: Int64 = 0
    private var requestStart = Date()

    override class func canInit(with request: URLRequest) -> Bool {
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }

        // Avoid capturing SDK upload traffic itself.
        if let host = request.url?.host?.lowercased(), host.contains("userback") {
            return false
        }

        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
        requestStart = Date()

        let config = URLSessionConfiguration.default
        config.protocolClasses = []

        let delegate = NetworkSessionDelegate(
            onResponse: { [weak self] response in
                guard let self else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            },
            onData: { [weak self] data in
                guard let self else { return }
                self.responseBodySize += Int64(data.count)
                self.client?.urlProtocol(self, didLoad: data)
            },
            onComplete: { [weak self] error in
                guard let self else { return }
                if let error {
                    self.client?.urlProtocol(self, didFailWithError: error)
                } else {
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            },
            onMetrics: { [weak self] task, metrics in
                guard let self else { return }
                self.sendNetworkEvent(task: task, metrics: metrics)
            }
        )

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        self.sessionDelegate = delegate

        let task = session.dataTask(with: mutableRequest as URLRequest)
        self.dataTask = task
        task.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        session?.invalidateAndCancel()
        dataTask = nil
        session = nil
        sessionDelegate = nil
    }

    private func sendNetworkEvent(task: URLSessionTask, metrics: URLSessionTaskMetrics) {
        let transaction = metrics.transactionMetrics.first
        let response = transaction?.response as? HTTPURLResponse

        let event: [String: Any] = [
            "eventType": "network",
            "name": task.originalRequest?.url?.absoluteString ?? "",
            "type": initiatorType(for: task.originalRequest),
            "method": task.originalRequest?.httpMethod ?? "GET",
            "status": response?.statusCode ?? 0,
            "responseStatus": response?.statusCode ?? 0,
            "startTime": requestStart.timeIntervalSince1970 * 1000,
            "duration": Date().timeIntervalSince(requestStart) * 1000,
            "domainLookupStart": ms(transaction?.domainLookupStartDate),
            "domainLookupEnd": ms(transaction?.domainLookupEndDate),
            "connectStart": ms(transaction?.connectStartDate),
            "connectEnd": ms(transaction?.connectEndDate),
            "requestStart": ms(transaction?.requestStartDate),
            "responseStart": ms(transaction?.responseStartDate),
            "responseEnd": ms(transaction?.responseEndDate),
            "encodedBodySize": transaction?.countOfResponseBodyBytesReceived ?? 0,
            "transferSize": responseBodySize,
        ]

        Task { @MainActor in
            UserbackSDK.shared.sendNativeEvent(event)
        }
    }

    private func ms(_ date: Date?) -> Double {
        guard let date else { return 0 }
        return date.timeIntervalSince1970 * 1000
    }

    private func initiatorType(for request: URLRequest?) -> String {
        guard let request else { return "other" }

        if let fetchDest = request.value(forHTTPHeaderField: "Sec-Fetch-Dest")?.lowercased(),
           !fetchDest.isEmpty,
           fetchDest != "empty" {
            return fetchDest
        }

        if let xRequestedWith = request.value(forHTTPHeaderField: "X-Requested-With")?.lowercased(),
           xRequestedWith == "xmlhttprequest" {
            return "xmlhttprequest"
        }

        if let accept = request.value(forHTTPHeaderField: "Accept")?.lowercased() {
            if accept.contains("javascript") {
                return "script"
            }
            if accept.contains("text/css") {
                return "style"
            }
            if accept.contains("image/") {
                return "image"
            }
            if accept.contains("text/html") {
                return "document"
            }
        }

        return "other"
    }
}

private final class NetworkSessionDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let onResponse: (URLResponse) -> Void
    private let onData: (Data) -> Void
    private let onComplete: (Error?) -> Void
    private let onMetrics: (URLSessionTask, URLSessionTaskMetrics) -> Void

    init(
        onResponse: @escaping (URLResponse) -> Void,
        onData: @escaping (Data) -> Void,
        onComplete: @escaping (Error?) -> Void,
        onMetrics: @escaping (URLSessionTask, URLSessionTaskMetrics) -> Void
    ) {
        self.onResponse = onResponse
        self.onData = onData
        self.onComplete = onComplete
        self.onMetrics = onMetrics
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        onResponse(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete(error)
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        onMetrics(task, metrics)
    }
}

#endif
