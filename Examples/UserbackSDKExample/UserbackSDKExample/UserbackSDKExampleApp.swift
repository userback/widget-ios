//
//  UserbackSDKExampleApp.swift
//  UserbackSDKExample
//
//  Created by Adrian Liu on 17/2/2026.
//

import SwiftUI
import UserbackSDK

private struct UserbackAppConfig {
    let accessToken: String
    let widgetCSS: String
    let surveyURL: String
    let requestURL: String
    let trackURL: String
    let widgetJSURL: String

    init(bundle: Bundle = .main) {
        accessToken = Self.readString("USERBACK_ACCESS_TOKEN", from: bundle)
        widgetCSS = Self.readString("USERBACK_WIDGET_CSS_URL", from: bundle)
        surveyURL = Self.readString("USERBACK_SURVEY_URL", from: bundle)
        requestURL = Self.readString("USERBACK_REQUEST_URL", from: bundle)
        trackURL = Self.readString("USERBACK_TRACK_URL", from: bundle)
        widgetJSURL = Self.readString("USERBACK_WIDGET_JS_URL", from: bundle)
    }

    var allURLs: [String] {
        [widgetCSS, surveyURL, requestURL, trackURL, widgetJSURL]
    }

    private static func readString(_ key: String, from bundle: Bundle) -> String {
        (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

@main
struct UserbackSDKExampleApp: App {
    init() {
        let config = UserbackAppConfig()

        #if DEBUG
        assert(!config.accessToken.isEmpty, "Missing Info.plist key: USERBACK_ACCESS_TOKEN")
        config.allURLs.forEach { urlString in
            assert(URL(string: urlString) != nil, "Invalid dev endpoint URL: \(urlString)")
        }
        #endif

        UserbackSDK.shared.start(
            accessToken: config.accessToken,
            userData: ["id": "example-user-id", "info": ["name": "Example User"]],
            widgetCSS: config.widgetCSS,
            surveyURL: config.surveyURL,
            requestURL: config.requestURL,
            trackURL: config.trackURL,
            widgetJSURL: config.widgetJSURL
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
