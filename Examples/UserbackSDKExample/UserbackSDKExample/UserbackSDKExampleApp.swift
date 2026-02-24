//
//  UserbackSDKExampleApp.swift
//  UserbackSDKExample
//
//  Created by Adrian Liu on 17/2/2026.
//

import SwiftUI
import UserbackSDK

private struct DevEndpoints {
    let widgetCSS = "https://app.userback.ngrok.app/dist/widget_dev/widget.min.css"
    let surveyURL = "https://app.userback.ngrok.app/s"
    let requestURL = "https://api.userback.ngrok.app/"
    let trackURL = "https://events.userback.ngrok.app"
    let widgetJSURL = "https://app.userback.ngrok.app/dist/widget_dev/widget.min.js"

    var allURLs: [String] {
        [widgetCSS, surveyURL, requestURL, trackURL, widgetJSURL]
    }
}

@main
struct UserbackSDKExampleApp: App {
    init() {
        let endpoints = DevEndpoints()

        #if DEBUG
        endpoints.allURLs.forEach { urlString in
            assert(URL(string: urlString) != nil, "Invalid dev endpoint URL: \(urlString)")
        }
        #endif

        UserbackSDK.shared.start(
            accessToken: "USERBACK_ACCESS_TOKEN",
            userData: ["id": "example-user-id", "info": ["name": "Example User"]],
            widgetCSS: endpoints.widgetCSS,
            surveyURL: endpoints.surveyURL,
            requestURL: endpoints.requestURL,
            trackURL: endpoints.trackURL,
            widgetJSURL: endpoints.widgetJSURL
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
