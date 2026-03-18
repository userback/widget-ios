# widget-ios
Integrating Userback widget into your iOS application.

## UserbackSDK

This repository contains `UserbackSDK`, an iOS SDK provided as a Swift Package.

Quick start:

- Add the package to your app in Xcode: `File > Add Packages...` and select this repository (or the remote URL when published).
- Import in your app code: `import UserbackSDK` and call `UserbackSDK.version()`.

Run tests locally:

```bash
swift test
```

## Native Observer Examples

The SDK includes optional native observers that forward console and network events into `UserbackSDK.shared.sendNativeEvent(...)`.

### 1) Start observers after SDK start

```swift
import UserbackSDK

UserbackSDK.shared.start(
	accessToken: "YOUR_ACCESS_TOKEN"
)

LogObserver.shared.start()
NetworkObserver.shared.start()
```

### 2) Generate sample events

```swift
// Console event
print("checkout button tapped")

// Network event
URLSession.shared.dataTask(with: URL(string: "https://httpbin.org/get")!).resume()
```

### 3) Stop observers (optional)

```swift
LogObserver.shared.stop()
NetworkObserver.shared.stop()
```

Notes:

- `LogObserver` redirects `stdout/stderr` while running.
- `NetworkObserver` uses `URLProtocol`, so start it once and stop it during teardown if needed.
- In the sample app, you can test both from the Endpoint Tester screen.

## Example App Config (Dev)

The sample iOS app reads Userback config from a real Info.plist file:

- `Examples/UserbackSDKExample/UserbackSDKExample/Info.plist`
- `Examples/UserbackSDKExample/Info.plist`

Keys used:

- `USERBACK_ACCESS_TOKEN`
- `USERBACK_WIDGET_CSS_URL`
- `USERBACK_SURVEY_URL`
- `USERBACK_REQUEST_URL`
- `USERBACK_TRACK_URL`
- `USERBACK_WIDGET_JS_URL`

Where to edit in Xcode:

1. Open `Examples/UserbackSDKExample/UserbackSDKExample.xcodeproj`
2. Select target `UserbackSDKExample`
3. Open `Info.plist`
4. Update the `USERBACK_*` values for your current dev/ngrok environment

Notes:

- The example target uses `GENERATE_INFOPLIST_FILE = NO` and `INFOPLIST_FILE = Info.plist`.
- Keep dev token/endpoints in `Info.plist` instead of hardcoding in source.
