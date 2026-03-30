# widget-ios
Integrating Userback widget into your iOS application.

## UserbackSDK

This repository contains `UserbackSDK`, an iOS SDK provided as a Swift Package.

## Installation

Add the package to your app in Xcode: `File > Add Packages...` and select this repository (or the remote URL when published).

## Setup

### 1. Start the SDK

Call `start` as early as possible, typically in `AppDelegate` or your root view controller:

```swift
import UserbackSDK

UserbackSDK.shared.start(accessToken: "YOUR_ACCESS_TOKEN")
```

With optional configuration:

```swift
UserbackSDK.shared.start(
    accessToken: "YOUR_ACCESS_TOKEN",
    userData: ["plan": "pro"],
    widgetCSS: "https://example.com/widget.css"
)
```

### 2. Open the feedback form

```swift
UserbackSDK.shared.openForm()
```

With options:

```swift
// Open a specific mode
UserbackSDK.shared.openForm(mode: "bug")

// Open and navigate directly to a target
UserbackSDK.shared.openForm(mode: "general", directTo: "screenshot")
```

### 3. Identify the user

```swift
UserbackSDK.shared.identify(userID: "user-123", userInfo: [
    "name": "Jane Smith",
    "email": "jane@example.com"
])
```

### 4. Set user properties

```swift
UserbackSDK.shared.setEmail("jane@example.com")
UserbackSDK.shared.setName("Jane Smith")
UserbackSDK.shared.setCategories("bug,feedback")
UserbackSDK.shared.setPriority("high")
UserbackSDK.shared.setTheme("dark")
UserbackSDK.shared.setData(["plan": "pro", "version": "2.0"])
```

### 5. Close the widget

```swift
UserbackSDK.shared.close()
```

### 6. Stop the SDK

```swift
UserbackSDK.shared.stop()
```

---

## Rotation Support

For smoother WebView resizing during device rotation, forward `viewWillTransition` from your view controller:

```swift
override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    UserbackSDK.shared.viewWillTransition(to: size, with: coordinator)
}
```

This is optional — the SDK handles rotation automatically via `UIDevice.orientationDidChangeNotification` if this is not called.

---

## Other Actions

```swift
// Open portal, roadmap, or announcements
UserbackSDK.shared.openPortal()
UserbackSDK.shared.openRoadmap()
UserbackSDK.shared.openAnnouncement()

// Session replay
UserbackSDK.shared.startSessionReplay()
UserbackSDK.shared.stopSessionReplay()

// Custom events
UserbackSDK.shared.addCustomEvent("checkout_tapped", details: ["item": "pro_plan"])

// Add custom request headers
UserbackSDK.shared.addHeader(key: "X-App-Version", value: "2.0")

// Refresh widget data
UserbackSDK.shared.refresh()
```

---

## Native Observers

The SDK includes optional observers that forward console logs and network events to Userback.

### Start observers

```swift
UserbackSDK.shared.start(accessToken: "YOUR_ACCESS_TOKEN")

LogObserver.shared.start()
NetworkObserver.shared.start()
```

### Generate sample events

```swift
// Console event
print("checkout button tapped")

// Network event
URLSession.shared.dataTask(with: URL(string: "https://httpbin.org/get")!).resume()
```

### Stop observers

```swift
LogObserver.shared.stop()
NetworkObserver.shared.stop()
```

Notes:
- `LogObserver` redirects `stdout/stderr` while running.
- `NetworkObserver` uses `URLProtocol`, so start it once and stop during teardown if needed.

---

## JS SDK Events

The native SDK dispatches the following events to the JS SDK via `window.dispatchEvent`:

| Event | Payload | Description |
|---|---|---|
| `userback:nativeDeviceSize` | `{ deviceWidth, deviceHeight }` | Fired on load and rotation with the app container dimensions |
| `userback:nativeFocusWidget` | `{}` | Fired after resize/rotation to prompt the widget to focus itself |
| `native:rotate` | `{ orientation, screenWidth, screenHeight }` | Fired when device orientation changes |

The JS SDK can also post a `focus_widget` message back to native to trigger native scroll positioning:

```js
window.webkit.messageHandlers.userbackSDK.postMessage({
    type: "focus_widget",
    payload: {}
});
```

---

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

---

## Run Tests

```bash
swift test
```
