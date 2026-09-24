//
//  BehaviorSettingsView.swift
//  wurstfinger
//
//  Thumb-Key's behavior settings: typing aids and gesture tuning.
//

import SwiftUI

struct BehaviorSettingsView: View {
    @AppStorage(SettingsKey.autoCapitalizeEnabled.rawValue, store: SharedDefaults.store)
    private var autoCapitalize = BehaviorSettings().autoCapitalize

    @AppStorage(SettingsKey.spacebarMultiTaps.rawValue, store: SharedDefaults.store)
    private var spacebarMultiTaps = BehaviorSettings().spacebarMultiTaps

    @AppStorage(SettingsKey.switchToLettersAfterSpace.rawValue, store: SharedDefaults.store)
    private var switchToLettersAfterSpace = BehaviorSettings().switchToLettersAfterSpace

    @AppStorage(SettingsKey.minSwipeLength.rawValue, store: SharedDefaults.store)
    private var minSwipeLength = BehaviorSettings().minSwipeLength

    @AppStorage(SettingsKey.slideEnabled.rawValue, store: SharedDefaults.store)
    private var slideEnabled = BehaviorSettings().slideEnabled

    @AppStorage(SettingsKey.slideCursorMovementMode.rawValue, store: SharedDefaults.store)
    private var slideCursorMovementMode = BehaviorSettings().slideCursorMovementMode

    @AppStorage(SettingsKey.slideSensitivity.rawValue, store: SharedDefaults.store)
    private var slideSensitivity = BehaviorSettings().slideSensitivity

    @AppStorage(SettingsKey.slideSpacebarDeadzone.rawValue, store: SharedDefaults.store)
    private var slideSpacebarDeadzone = BehaviorSettings().slideSpacebarDeadzone

    @AppStorage(SettingsKey.slideBackspaceDeadzone.rawValue, store: SharedDefaults.store)
    private var slideBackspaceDeadzone = BehaviorSettings().slideBackspaceDeadzone

    @AppStorage(SettingsKey.slideHoldEnabled.rawValue, store: SharedDefaults.store)
    private var slideHoldEnabled = BehaviorSettings().slideHoldEnabled

    @AppStorage(SettingsKey.dragReturnEnabled.rawValue, store: SharedDefaults.store)
    private var dragReturnEnabled = BehaviorSettings().dragReturnEnabled

    @AppStorage(SettingsKey.circularDragEnabled.rawValue, store: SharedDefaults.store)
    private var circularDragEnabled = BehaviorSettings().circularDragEnabled

    @AppStorage(SettingsKey.clockwiseDragAction.rawValue, store: SharedDefaults.store)
    private var clockwiseDragAction = BehaviorSettings().clockwiseDragAction

    @AppStorage(SettingsKey.counterclockwiseDragAction.rawValue, store: SharedDefaults.store)
    private var counterclockwiseDragAction = BehaviorSettings().counterclockwiseDragAction

    @AppStorage(SettingsKey.ghostKeysEnabled.rawValue, store: SharedDefaults.store)
    private var ghostKeysEnabled = BehaviorSettings().ghostKeysEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Auto-capitalize", isOn: $autoCapitalize)
                Toggle(isOn: $spacebarMultiTaps) {
                    labeled("Space bar multi-taps", detail: "Tap space again for \", \", \". \", \"? \" and more")
                }
                Toggle("Switch to letters after space", isOn: $switchToLettersAfterSpace)
            } header: {
                Text("Typing")
            }

            Section {
                sliderRow(
                    "Minimum swipe length",
                    value: $minSwipeLength,
                    range: BehaviorSettings.minSwipeLengthRange,
                    unit: "px"
                )
                Toggle(isOn: $dragReturnEnabled) {
                    labeled("Swipe and return", detail: "Swipe out and back for the other case or a variant")
                }
                Toggle(isOn: $circularDragEnabled) {
                    labeled("Circles", detail: "Draw a circle on a key")
                }
                if circularDragEnabled {
                    Picker("Clockwise circle", selection: $clockwiseDragAction) {
                        circleActionOptions
                    }
                    Picker("Counter-clockwise circle", selection: $counterclockwiseDragAction) {
                        circleActionOptions
                    }
                }
                Toggle(isOn: $ghostKeysEnabled) {
                    labeled("Ghost keys", detail: "Swipe number-layer symbols from the letter keys")
                }
            } header: {
                Text("Gestures")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { slideEnabled },
                    set: { enabled in
                        slideEnabled = enabled
                        if enabled {
                            slideHoldEnabled = false
                        }
                    }
                )) {
                    labeled("Slide gestures", detail: "Slide on space to move the cursor, on backspace to select and delete")
                }
                if slideEnabled {
                    Picker("Cursor movement", selection: $slideCursorMovementMode) {
                        Text("Linear").tag(SlideCursorMovementMode.linear)
                        Text("Quadratic").tag(SlideCursorMovementMode.quadratic)
                        Text("Threshold").tag(SlideCursorMovementMode.threshold)
                        Text("Constant").tag(SlideCursorMovementMode.constant)
                    }
                    sliderRow(
                        "Slide sensitivity",
                        value: $slideSensitivity,
                        range: BehaviorSettings.slideSensitivityRange,
                        unit: nil
                    )
                    Toggle(isOn: $slideSpacebarDeadzone) {
                        labeled("Space bar dead zone", detail: "Short swipes on space keep working")
                    }
                    Toggle(isOn: $slideBackspaceDeadzone) {
                        labeled("Backspace dead zone", detail: "Short swipes on backspace keep working")
                    }
                }
                Toggle(isOn: Binding(
                    get: { slideHoldEnabled },
                    set: { enabled in
                        slideHoldEnabled = enabled
                        if enabled {
                            slideEnabled = false
                        }
                    }
                )) {
                    labeled("Slide and hold", detail: "Hold after a swipe on space or backspace to repeat it")
                }
            } header: {
                Text("Space and backspace")
            }
        }
        .navigationTitle("Behavior")
    }

    @ViewBuilder
    private var circleActionOptions: some View {
        Text("Opposite case letter").tag(CircularDragAction.oppositeCase)
        Text("Number key").tag(CircularDragAction.numeric)
    }

    private func labeled(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func sliderRow(
        _ title: LocalizedStringKey,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unit: String?
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(unit.map { "\(value.wrappedValue) \($0)" } ?? "\(value.wrappedValue)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound) ... Double(range.upperBound),
                step: 1
            )
        }
    }
}

#Preview {
    NavigationStack {
        BehaviorSettingsView()
    }
}
