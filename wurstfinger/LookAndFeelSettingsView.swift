//
//  LookAndFeelSettingsView.swift
//  wurstfinger
//
//  Thumb-Key's look-and-feel settings: theme, legends, key shape,
//  animations and sound.
//

import SwiftUI

struct LookAndFeelSettingsView: View {
    @AppStorage(SettingsKey.themeMode.rawValue, store: SharedDefaults.store)
    private var themeMode = ThemeMode.system

    @AppStorage(SettingsKey.themeColor.rawValue, store: SharedDefaults.store)
    private var themeColor = ThemeColor.system

    @AppStorage(SettingsKey.hideLetters.rawValue, store: SharedDefaults.store)
    private var hideLetters = false

    @AppStorage(SettingsKey.hideSymbols.rawValue, store: SharedDefaults.store)
    private var hideSymbols = false

    @AppStorage(SettingsKey.showToastOnLayoutSwitch.rawValue, store: SharedDefaults.store)
    private var showToastOnLayoutSwitch = true

    @AppStorage(SettingsKey.keyboardSplit.rawValue, store: SharedDefaults.store)
    private var keyboardSplit = false

    @AppStorage(SettingsKey.backdropEnabled.rawValue, store: SharedDefaults.store)
    private var backdropEnabled = false

    @AppStorage(SettingsKey.keyPadding.rawValue, store: SharedDefaults.store)
    private var keyPadding = LookSettings().keyPadding

    @AppStorage(SettingsKey.keyBorderWidth.rawValue, store: SharedDefaults.store)
    private var keyBorderWidth = LookSettings().keyBorderWidth

    @AppStorage(SettingsKey.keyRadius.rawValue, store: SharedDefaults.store)
    private var keyRadius = LookSettings().keyRadius

    @AppStorage(SettingsKey.bottomOffset.rawValue, store: SharedDefaults.store)
    private var bottomOffset = 0.0

    @AppStorage(SettingsKey.animationSpeed.rawValue, store: SharedDefaults.store)
    private var animationSpeed = LookSettings().animationSpeed

    @AppStorage(SettingsKey.animationHelperSpeed.rawValue, store: SharedDefaults.store)
    private var animationHelperSpeed = LookSettings().animationHelperSpeed

    @AppStorage(SettingsKey.soundOnTap.rawValue, store: SharedDefaults.store)
    private var soundOnTap = false

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $themeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("Theme color", selection: $themeColor) {
                    ForEach(ThemeColor.allCases, id: \.self) { color in
                        Text(color.displayName).tag(color)
                    }
                }
            } header: {
                Text("Theme")
            }

            Section {
                Toggle("Hide letters", isOn: $hideLetters)
                Toggle("Hide symbols", isOn: $hideSymbols)
                Toggle("Show layout name when switching", isOn: $showToastOnLayoutSwitch)
            } header: {
                Text("Legends")
            }

            Section {
                Toggle(isOn: $keyboardSplit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Split keyboard")
                        Text("One copy of the keys for each thumb")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                sliderRow("Key padding", value: $keyPadding, range: LookSettings.keyPaddingRange, unit: "pt")
                sliderRow(
                    "Key border width", value: $keyBorderWidth,
                    range: LookSettings.keyBorderWidthRange, unit: nil
                )
                sliderRow("Key radius", value: $keyRadius, range: LookSettings.keyRadiusRange, unit: "%")
                sliderRow("Bottom offset", value: $bottomOffset, range: 0 ... 250, unit: "pt")
                Toggle("Keyboard backdrop", isOn: $backdropEnabled)
            } header: {
                Text("Keys")
            }

            Section {
                sliderRow(
                    "Animation speed", value: $animationSpeed,
                    range: LookSettings.animationSpeedRange, unit: "ms"
                )
                sliderRow(
                    "Animation helper speed", value: $animationHelperSpeed,
                    range: LookSettings.animationSpeedRange, unit: "ms"
                )
                Toggle("Play sound on tap", isOn: $soundOnTap)
            } header: {
                Text("Feedback")
            }
        }
        .navigationTitle("Look and feel")
    }

    private func sliderRow(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String?
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                let number = Int(value.wrappedValue.rounded())
                Text(unit.map { "\(number) \($0)" } ?? "\(number)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}

#Preview {
    NavigationStack {
        LookAndFeelSettingsView()
    }
}
