//
//  ContentView.swift
//  wurstfinger
//
//  Created by Claas Flint on 24.10.25.
//

import SwiftUI

struct ContentView: View {
    private enum Tab {
        case home, setup, test, settings
    }

    @State private var selectedTab = Tab.home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)

            OnboardingView()
                .tabItem {
                    Label("Setup", systemImage: "list.number")
                }
                .tag(Tab.setup)

            TestAreaView()
                .tabItem {
                    Label("Test", systemImage: "keyboard")
                }
                .tag(Tab.test)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        // The keyboard's settings swipe opens wurstfinger://settings.
        .onOpenURL { url in
            if url.host == "settings" {
                selectedTab = .settings
            }
        }
    }
}

#Preview {
    ContentView()
}
