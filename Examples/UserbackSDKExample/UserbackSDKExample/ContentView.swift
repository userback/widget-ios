//
//  ContentView.swift
//  UserbackSDKExample
//
//  Created by Adrian Liu on 17/2/2026.
//

import SwiftUI
import UserbackSDK

struct ContentView: View {
    var body: some View {
        TabView {
            HomeScreen()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            ShopScreen()
                .tabItem {
                    Label("Shop", systemImage: "cart")
                }

            ProfileScreen()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
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
                    UserbackSDK.shared.open(mode: "checkout")
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
                        UserbackSDK.shared.open(mode: "general")
                    } label: {
                        Label("Send Feedback", systemImage: "bubble.left.and.bubble.right")
                    }

                    Button {
                        UserbackSDK.shared.open(mode: "bug")
                    } label: {
                        Label("Report a Bug", systemImage: "ant")
                    }

                    Button {
                        UserbackSDK.shared.open(mode: "feature")
                    } label: {
                        Label("Request a Feature", systemImage: "lightbulb")
                    }
                }
            }
            .navigationTitle("Profile")
            .listStyle(.insetGrouped)
        }
    }
}

#Preview {
    ContentView()
}
