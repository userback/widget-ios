# widget-ios
Integrating Userback widget into your iOS application.

## What's new in v2

- **Surveys** — `openSurvey(surveyKey:)` opens a specific survey directly.
- **Screen tracking** — `enterScreen`/`leaveScreen` attribute surveys to the screen the user was on.
- **Multi-project support** — `openForm` accepts an optional `projectKey` to route feedback to a specific Userback project when your app is set up with more than one.

All of the above are additive. Existing v1 `openForm(mode:, directTo:)` calls keep working unchanged — no code changes required to upgrade.

### Upgrading from v1

```swift
dependencies: [
    .package(url: "https://github.com/userback/widget-ios", from: "2.0.0")
]
```

Or in Xcode: `File > Packages > Update to Latest Package Versions`, then select a `2.x` version if prompted.

If you're still passing a general web widget access token (`P-...`) as `accessToken`, switch to your app's **Mobile Key** instead — find it in the Userback app under **Workspace Settings → Mobile SDK**. The Mobile Key is required for screen tracking, native events, and multi-project routing.

## UserbackSDK

This repository contains `UserbackSDK`, an iOS SDK provided as a Swift Package.

## Requirements

- iOS 13.0+
- Swift 5.5+
- Xcode 13+

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

Call `start` as early as possible, typically in `AppDelegate` or your root view controller. Use your app's **Mobile Key** — found in the Userback app under **Workspace Settings → Mobile SDK** — not a general web widget access token (`P-...`):

```swift
import UserbackSDK

UserbackSDK.shared.start(accessToken: "YOUR_MOBILE_KEY")
```

With optional configuration:

```swift
UserbackSDK.shared.start(
    accessToken: "YOUR_MOBILE_KEY",
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

// Route to a specific project, if your app has more than one set up
UserbackSDK.shared.openForm(mode: "general", projectKey: "YOUR_PROJECT_KEY")
```

### 3. Open a survey

```swift
UserbackSDK.shared.openSurvey("YOUR_SURVEY_KEY")
```

Find a survey's key in the Userback app under that survey's settings.

### 4. Screen tracking

Call `enterScreen` when a screen becomes active and `leaveScreen` when it's dismissed, so surveys can be attributed to the correct screen. The screen name you pass must match a screen configured in the Userback app under **Survey Designer → Target → Mobile Screens** — that's how a survey gets targeted to appear only on specific screens:

```swift
UserbackSDK.shared.enterScreen("ProductDetailScreen")
UserbackSDK.shared.leaveScreen("ProductDetailScreen")
```

### 5. Identify the user

```swift
UserbackSDK.shared.identify(userID: "user-123", userInfo: [
    "name": "Jane Smith",
    "email": "jane@example.com"
])
```

### 6. Set user properties

```swift
UserbackSDK.shared.setEmail("jane@example.com")
UserbackSDK.shared.setName("Jane Smith")
UserbackSDK.shared.setCategories("bug,feedback")
UserbackSDK.shared.setPriority("high")
UserbackSDK.shared.setTheme("dark")
UserbackSDK.shared.setData(["plan": "pro", "version": "2.0"])
```

### 7. Close the widget

```swift
UserbackSDK.shared.close()
```

### 8. Stop the SDK

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

## Example App

A working example app is included in `Examples/UserbackSDKExample/`.

To run it:

1. Open `Examples/UserbackSDKExample/UserbackSDKExample.xcodeproj` in Xcode
2. Open `UserbackSDKExample/Info.plist`
3. Replace `YOUR_ACCESS_TOKEN` with your Userback Mobile Key (Workspace Settings → Mobile SDK)
4. Build and run on a simulator or device

## Run Tests

```bash
swift test
```
