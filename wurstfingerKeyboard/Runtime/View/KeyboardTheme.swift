//
//  KeyboardTheme.swift
//  Wurstfinger
//
//  Thumb-Key's color themes. Each palette maps the Material roles Thumb-Key
//  draws with onto key parts: surface (letter keys), surfaceVariant (utility
//  keys), primary/secondary (legends), inversePrimary (pressed key),
//  outline (key border), tertiary (press animation).
//

import SwiftUI
import UIKit

/// Light/dark choice. Raw values are persisted.
enum ThemeMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

/// Color scheme. Raw values are persisted. `system` follows iOS colors, in
/// place of Android's wallpaper-based dynamic colors.
enum ThemeColor: String, CaseIterable {
    case system
    case green
    case pink
    case matrix
    case srcery
    case blue
    case dracula
    case twilight
    case highContrast
    case highContrastColorful
    case ancom
    case neon

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .green: "Green"
        case .pink: "Pink"
        case .matrix: "Matrix"
        case .srcery: "Srcery"
        case .blue: "Blue"
        case .dracula: "Dracula"
        case .twilight: "Twilight"
        case .highContrast: String(localized: "High contrast")
        case .highContrastColorful: String(localized: "High contrast colorful")
        case .ancom: "Ancom"
        case .neon: "Neon"
        }
    }
}

/// Colors for one theme in one appearance.
struct KeyboardPalette {
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let tertiaryContainer: Color
    let background: Color
    let surface: Color
    let surfaceVariant: Color
    let outline: Color
    let inversePrimary: Color

    /// Thumb-Key's `MUTED` legend color.
    var muted: Color {
        secondary.opacity(0.5)
    }

    /// iOS system colors.
    static let system = KeyboardPalette(
        primary: Color(.label),
        secondary: Color(.secondaryLabel),
        tertiary: .accentColor,
        tertiaryContainer: Color.accentColor.opacity(0.25),
        background: Color(.systemBackground),
        surface: Color(.secondarySystemBackground),
        surfaceVariant: Color(.systemGray5),
        outline: Color(.separator),
        inversePrimary: Color(.systemGray3)
    )

    /// Palette for `color` in `scheme`, honoring the forced `mode`.
    static func resolve(color: ThemeColor, mode: ThemeMode, scheme: ColorScheme) -> KeyboardPalette {
        let dark = switch mode {
        case .system: scheme == .dark
        case .light: false
        case .dark: true
        }
        guard let pair = hexPalettes[color] else { return .system }
        return dark ? pair.dark : pair.light
    }

    /// Appearance a palette is drawn for, so system colors resolve to the
    /// forced light/dark choice.
    static func colorScheme(mode: ThemeMode, scheme: ColorScheme) -> ColorScheme {
        switch mode {
        case .system: scheme
        case .light: .light
        case .dark: .dark
        }
    }

    // MARK: - Thumb-Key Palettes

    private init(
        primary: Color, secondary: Color, tertiary: Color, tertiaryContainer: Color, background: Color,
        surface: Color, surfaceVariant: Color, outline: Color, inversePrimary: Color
    ) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.tertiaryContainer = tertiaryContainer
        self.background = background
        self.surface = surface
        self.surfaceVariant = surfaceVariant
        self.outline = outline
        self.inversePrimary = inversePrimary
    }

    /// Roles in order: primary, secondary, tertiary, tertiaryContainer,
    /// background, surface, surfaceVariant, outline, inversePrimary (ARGB).
    private init(_ argb: [UInt32]) {
        let colors = argb.map { value in
            Color(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: Double((value >> 24) & 0xFF) / 255
            )
        }
        self.init(
            primary: colors[0], secondary: colors[1], tertiary: colors[2], tertiaryContainer: colors[3],
            background: colors[4], surface: colors[5], surfaceVariant: colors[6], outline: colors[7],
            inversePrimary: colors[8]
        )
    }

    private static let hexPalettes: [ThemeColor: (light: KeyboardPalette, dark: KeyboardPalette)] = {
        let matrix = KeyboardPalette([
            0xFF00_E630, 0xFF69_DF8C, 0xFF96_D784, 0xFF10_2D0F, 0xFF00_0000,
            0xFF00_0000, 0xFF00_1000, 0xFF42_493F, 0xFF00_2006,
        ])
        return [
            .pink: (
                KeyboardPalette([
                    0xFFA6_3166, 0xFF74_5660, 0xFF7D_5636, 0xFFFF_DCC3, 0xFFFF_FBFF,
                    0xFFFF_FBFF, 0xFFF2_DDE2, 0xFF83_7377, 0xFFFF_B0CB,
                ]),
                KeyboardPalette([
                    0xFFFF_B0CB, 0xFFE2_BDC7, 0xFFF0_BC95, 0xFF62_3F21, 0xFF20_1A1C,
                    0xFF20_1A1C, 0xFF51_4347, 0xFF9E_8C91, 0xFFA6_3166,
                ])
            ),
            .green: (
                KeyboardPalette([
                    0xFF21_6C29, 0xFF52_634F, 0xFF38_656A, 0xFFBC_EBF1, 0xFFFC_FDF6,
                    0xFFFC_FDF6, 0xFFDE_E5D8, 0xFF72_796F, 0xFF8B_D987,
                ]),
                KeyboardPalette([
                    0xFF8B_D987, 0xFFB9_CCB3, 0xFFA0_CFD4, 0xFF1F_4D52, 0xFF1A_1C19,
                    0xFF1A_1C19, 0xFF42_4940, 0xFF8C_9388, 0xFF21_6C29,
                ])
            ),
            .srcery: (
                KeyboardPalette([
                    0xFF6D_5E00, 0xFF65_5E40, 0xFF42_664F, 0xFFC4_ECCF, 0xFFFF_FBFF,
                    0xFFFF_FBFF, 0xFFE9_E2D0, 0xFF7C_7768, 0xFFDE_C64C,
                ]),
                KeyboardPalette([
                    0xFFDE_C64C, 0xFFD0_C7A2, 0xFFA9_D0B4, 0xFF2B_4E39, 0xFF1D_1B16,
                    0xFF1D_1B16, 0xFF4A_4739, 0xFF96_9080, 0xFF6D_5E00,
                ])
            ),
            .blue: (
                KeyboardPalette([
                    0xFF00_6874, 0xFF00_6874, 0xFF00_696D, 0xFF6F_F6FC, 0xFFF8_FDFF,
                    0xFFF8_FDFF, 0xFFDB_E4E6, 0xFF6F_797A, 0xFF4F_D8EB,
                ]),
                KeyboardPalette([
                    0xFF4F_D8EB, 0xFF4F_D8EB, 0xFF4C_D9DF, 0xFF00_4F52, 0xFF00_1F25,
                    0xFF00_1F25, 0xFF3F_484A, 0xFF89_9294, 0xFF00_6874,
                ])
            ),
            .dracula: (
                KeyboardPalette([
                    0xFF47_58A9, 0xFF5A_5D72, 0xFF76_546E, 0xFFFF_D7F2, 0xFFFE_FBFF,
                    0xFFFE_FBFF, 0xFFE3_E1EC, 0xFF76_7680, 0xFFB9_C3FF,
                ]),
                KeyboardPalette([
                    0xFFB9_C3FF, 0xFFC3_C5DD, 0xFFE5_BAD8, 0xFF5C_3C55, 0xFF1B_1B1F,
                    0xFF1B_1B1F, 0xFF45_464F, 0xFF90_909A, 0xFF47_58A9,
                ])
            ),
            .twilight: (
                KeyboardPalette([
                    0xFF44_475A, 0xFF62_72A3, 0xFFB9_78C9, 0xFFFE_B76C, 0xFFF7_F7F1,
                    0xFFA3_FEFE, 0xFF8A_E8FC, 0xFF44_475A, 0xFFFE_FEA4,
                ]),
                KeyboardPalette([
                    0xFFF7_F7F1, 0xFFBD_93F9, 0xFFE5_BAD8, 0xFFFE_B76C, 0xFF1D_1E26,
                    0xFF28_2A36, 0xFF44_475A, 0xFF62_72A4, 0xFFF0_F98B,
                ])
            ),
            .highContrast: (
                KeyboardPalette([
                    0xFF00_0000, 0xFF14_1414, 0xFFFF_FFFF, 0xFF5A_5A5A, 0xFFE4_E4E4,
                    0xFFFF_FFFF, 0xFFF1_F1F1, 0xFF16_1616, 0xFF1D_1D1D,
                ]),
                KeyboardPalette([
                    0xFFFF_FFFF, 0xFFF3_F3F3, 0xFF00_0000, 0xFFE2_E2E2, 0xFF1D_1D1D,
                    0xFF0F_0F0F, 0xFF00_0000, 0xFFCC_CCCC, 0xFFFF_FFFF,
                ])
            ),
            .highContrastColorful: (
                KeyboardPalette([
                    0xFF13_3558, 0xFF1A_446F, 0xFFFF_9901, 0xFF1A_FFFF, 0xFFFF_DD00,
                    0xFFFF_F4BE, 0xFFFF_E38C, 0xFFFF_871B, 0xFFC1_FFFF,
                ]),
                KeyboardPalette([
                    0xFFFF_F192, 0xFFFF_F8C9, 0xFF82_5BAD, 0xFFDF_995B, 0xFF18_1320,
                    0xFF24_1B33, 0xFF1F_1927, 0xFF62_537A, 0xFFFF_F200,
                ])
            ),
            .ancom: (
                KeyboardPalette([
                    0xFF00_0000, 0xFF59_5959, 0xFFA0_0000, 0xFFCC_0000, 0xFFE0_E0E0,
                    0xFFE0_E0E0, 0xFFE0_E0E0, 0xFF75_7575, 0xFFFF_7070,
                ]),
                KeyboardPalette([
                    0xFFE0_E0E0, 0xFFFF_4040, 0xFFFF_4040, 0xFF20_2020, 0xFF00_0000,
                    0xFF00_0000, 0xFF00_0000, 0xFF90_9090, 0xFF40_4040,
                ])
            ),
            .matrix: (matrix, matrix),
            .neon: (
                KeyboardPalette([
                    0xFF64_4AB3, 0xFF39_91F1, 0xFF39_91F1, 0x803D_2582, 0xFF00_0000,
                    0xFF00_0000, 0xFF00_0000, 0xFF3D_2582, 0x803D_2582,
                ]),
                KeyboardPalette([
                    0xFF39_91F1, 0xFF64_4AB3, 0xFF64_4AB3, 0x800E_539F, 0xFF00_0000,
                    0xFF00_0000, 0xFF00_0000, 0xFF0E_539F, 0x800E_539F,
                ])
            ),
        ]
    }()
}
