//
//  ContentView.swift
//  UserbackSDKExample
//
//  Created by Adrian Liu on 17/2/2026.
//

import SwiftUI
import UserbackSDK

struct ContentView: View {
    @State private var selectedTab: String = "Home"

    private let tabScreenNames = ["Home": "HomeScreen", "Shop": "ShopScreen", "Profile": "ProfileScreen"]

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeScreen()
                .tabItem { Label("Home", systemImage: "house") }
                .tag("Home")

            ShopScreen()
                .tabItem { Label("Shop", systemImage: "cart") }
                .tag("Shop")

            ProfileScreen()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag("Profile")
        }
        .onAppear {
            UserbackSDK.shared.enterScreen(tabScreenNames[selectedTab] ?? selectedTab)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            UserbackSDK.shared.leaveScreen(tabScreenNames[oldTab] ?? oldTab)
            UserbackSDK.shared.enterScreen(tabScreenNames[newTab] ?? newTab)
        }
    }
}

private struct HomeScreen: View {
    @State private var requestStatus = "No request yet"

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Welcome")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Explore the app and let us know what you think.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text(requestStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    HomeCard(title: "Latest Updates", icon: "sparkles")
                    HomeCard(title: "Special Offers", icon: "tag")
                    HomeCard(title: "News", icon: "newspaper")
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}

private struct HomeCard: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.headline)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

private struct ShopScreen: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Shop")
                    .font(.largeTitle)

                Button("Checkout Feedback") {
                    UserbackSDK.shared.openForm(projectKey: "YOUR_PROJECT_KEY_1")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("Shop")
        }
    }
}

private struct ProfileScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading) {
                            Text("Demo User")
                                .font(.headline)
                            Text("demo.user@example.com")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Settings") {
                    Label("Account", systemImage: "person")
                    Label("Notifications", systemImage: "bell")
                }

                Section("Support") {
                    Button {
                        UserbackSDK.shared.openForm(projectKey: "FR")
                    } label: {
                        Label("Project 1 Feedback", systemImage: "bubble.left.and.bubble.right")
                    }

                    Button {
                        UserbackSDK.shared.openForm(projectKey: "PROJ2")
                    } label: {
                        Label("Project 2 Feedback", systemImage: "bubble.left.and.bubble.right")
                    }

                    Button {
                        UserbackSDK.shared.openForm(projectKey: "VF")
                    } label: {
                        Label("Project 3 Feedback", systemImage: "bubble.left.and.bubble.right")
                    }

                    Button {
                        UserbackSDK.shared.openForm()
                    } label: {
                        Label("Project 4 Feedback", systemImage: "bubble.left.and.bubble.right")
                    }

                    Button {
                        UserbackSDK.shared.openSurvey("9b3JMC")
                    } label: {
                        Label("Open Survey", systemImage: "list.bullet.clipboard")
                    }
                }

                Section("SDK Endpoint Tests") {
                    NavigationLink {
                        EndpointTestScreen()
                    } label: {
                        Label("Open Endpoint Tester", systemImage: "hammer")
                    }
                }
            }
            .navigationTitle("Profile")
            .listStyle(.insetGrouped)
        }
    }
}

private struct EndpointTestScreen: View {
    @State private var endpointStatus = "Not tested"

    var body: some View {
        Form {
            Section("Status") {
                Text(endpointStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Lifecycle") {
                Button("Init") {
                    let token = (Bundle.main.object(forInfoDictionaryKey: "USERBACK_ACCESS_TOKEN") as? String) ?? ""
                    UserbackSDK.shared.start(accessToken: token)
                    endpointStatus = "Called start()"
                }

                Button("Check isLoaded") {
                    UserbackSDK.shared.isLoaded { loaded in
                        endpointStatus = "isLoaded: \(loaded)"
                    }
                }

                Button("Refresh") {
                    UserbackSDK.shared.refresh(refreshFeedback: true, refreshSurvey: true)
                    endpointStatus = "Called refresh()"
                }

                Button("Destroy") {
                    UserbackSDK.shared.stop()
                    endpointStatus = "Called stop()"
                }
            }

            Section("Open / Close") {
                Button("Open Form – Project 1") {
                    UserbackSDK.shared.openForm(projectKey: "YOUR_PROJECT_KEY_1")
                    endpointStatus = "Called openForm(YOUR_PROJECT_KEY_1)"
                }

                Button("Open Form – Project 2") {
                    UserbackSDK.shared.openForm(projectKey: "YOUR_PROJECT_KEY_2")
                    endpointStatus = "Called openForm(YOUR_PROJECT_KEY_2)"
                }

                Button("Open Form – Project 3") {
                    UserbackSDK.shared.openForm(projectKey: "YOUR_PROJECT_KEY_3")
                    endpointStatus = "Called openForm(YOUR_PROJECT_KEY_3)"
                }

                Button("Open Portal") {
                    UserbackSDK.shared.openPortal()
                    endpointStatus = "Called openPortal()"
                }

                Button("Open Roadmap") {
                    UserbackSDK.shared.openRoadmap()
                    endpointStatus = "Called openRoadmap()"
                }

                Button("Open Announcement") {
                    UserbackSDK.shared.openAnnouncement()
                    endpointStatus = "Called openAnnouncement()"
                }

                Button("Close Widget") {
                    UserbackSDK.shared.close()
                    endpointStatus = "Called close()"
                }
            }

            Section("Identity & Data") {
                Button("Identify User") {
                    UserbackSDK.shared.identify(
                        userID: "ios-sample-user-001",
                        userInfo: ["email": "demo.user@example.com", "plan": "pro"]
                    )
                    endpointStatus = "Called identify()"
                }

                Button("Clear Identity") {
                    UserbackSDK.shared.clearIdentity()
                    endpointStatus = "Called clearIdentity()"
                }

                Button("Set Data") {
                    UserbackSDK.shared.setData([
                        "build": "ios-debug",
                        "is_test": true,
                        "screen": "profile"
                    ])
                    endpointStatus = "Called setData()"
                }

                Button("Add Header") {
                    UserbackSDK.shared.addHeader(key: "X-Debug-Source", value: "ios-sample")
                    endpointStatus = "Called addHeader()"
                }
            }

            Section("Field Setters") {
                Button("Set Email") {
                    UserbackSDK.shared.setEmail("demo.user@example.com")
                    endpointStatus = "Called setEmail()"
                }

                Button("Set Name") {
                    UserbackSDK.shared.setName("Demo User")
                    endpointStatus = "Called setName()"
                }

                Button("Set Categories") {
                    UserbackSDK.shared.setCategories("ios,dev")
                    endpointStatus = "Called setCategories()"
                }

                Button("Set Priority") {
                    UserbackSDK.shared.setPriority("high")
                    endpointStatus = "Called setPriority()"
                }

                Button("Set Theme (dark)") {
                    UserbackSDK.shared.setTheme("dark")
                    endpointStatus = "Called setTheme(dark)"
                }
            }

            Section("Session Replay & Events") {
                Button("Start Session Replay") {
                    UserbackSDK.shared.startSessionReplay(options: [
                        "tags": ["ios", "sample"],
                        "mask_rules": ["input[type=password]"]
                    ])
                    endpointStatus = "Called startSessionReplay()"
                }

                Button("Stop Session Replay") {
                    UserbackSDK.shared.stopSessionReplay()
                    endpointStatus = "Called stopSessionReplay()"
                }

                Button("Add Custom Event") {
                    UserbackSDK.shared.addCustomEvent("ios_test_event", details: ["source": "endpoint_tester"])
                    endpointStatus = "Called addCustomEvent()"
                }
            }

            Section("Native Logging (Auto-Started)") {
                Button("Emit Test Console Log") {
                    print("[Sample] Native console event at \(Date())")
                    endpointStatus = "Printed test console log"
                }

                Button("Emit Console Warning") {
                    print("[Sample][WARN] Simulated warning at \(Date())")
                    endpointStatus = "Printed warning log"
                }

                Button("Emit Console Error") {
                    print("[Sample][ERROR] Simulated error at \(Date())")
                    endpointStatus = "Printed error log"
                }

                Button("Emit Delayed Console Log (2s)") {
                    endpointStatus = "Scheduling delayed log..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        print("[Sample] Delayed console log fired at \(Date())")
                        endpointStatus = "Printed delayed log"
                    }
                }

                Button("Trigger Test Network Request") {
                    guard let url = URL(string: "https://httpbin.org/get") else {
                        endpointStatus = "Invalid test URL"
                        return
                    }

                    URLSession.shared.dataTask(with: url) { _, _, error in
                        DispatchQueue.main.async {
                            if let error {
                                endpointStatus = "Test request failed: \(error.localizedDescription)"
                            } else {
                                endpointStatus = "Sent test request to httpbin"
                            }
                        }
                    }.resume()
                }

                Button("Trigger Test Network Error") {
                    guard let url = URL(string: "https://nonexistent-userback-sample.invalid") else {
                        endpointStatus = "Invalid test URL"
                        return
                    }

                    URLSession.shared.dataTask(with: url) { _, _, error in
                        DispatchQueue.main.async {
                            if let error {
                                endpointStatus = "Expected network error: \(error.localizedDescription)"
                            } else {
                                endpointStatus = "Unexpected success on invalid host"
                            }
                        }
                    }.resume()
                }
            }
        }
        .navigationTitle("Endpoint Tester")
    }
}

#Preview {
    ContentView()
}
