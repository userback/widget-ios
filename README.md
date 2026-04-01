# widget-ios
Integrating Userback widget into your iOS application.

## UserbackSDK

This repository contains `UserbackSDK`, an iOS SDK provided as a Swift Package.

## Installation

### Swift Package Manager

In Xcode, go to `File > Add Package Dependencies...` and enter:

```
https://github.com/userback/widget-ios
```

Select a version and add `UserbackSDK` to your target.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/userback/widget-ios", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["UserbackSDK"]
    )
]
```

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

## Run Tests

```bash
swift test
```
