//
//  UserbackSDKExampleApp.swift
//  UserbackSDKExample
//
//  Created by Adrian Liu on 17/2/2026.
//

import SwiftUI
import UserbackSDK

@main
struct UserbackSDKExampleApp: App {
    init() {
        UserbackSDK.shared.start(
            accessToken: "P-munRw6sN7ExmKIuAwNvumliFy",
            userData: ["id": "example-user-id", "info": ["name": "Example User"]],
            widgetCSS: "https://app.dev.userback.net/dist/widget_dev/widget.min.css",
            surveyURL: "https://app.dev.userback.net/s",
            requestURL: "https://api.dev.userback.net/",
            trackURL: "https://events.dev.userback.net",
            widgetJSURL: "https://app.dev.userback.net/dist/widget_dev/widget.min.js"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
