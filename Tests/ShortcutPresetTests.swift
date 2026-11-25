import Foundation
import Testing

#if os(macOS)
@testable import DictoraMac
#else
@testable import DictoraiOS
#endif

@Suite("ShortcutPreset")
struct ShortcutPresetTests {
    @Test("Every preset is fully described for the picker")
    func everyPresetIsDescribed() {
        for preset in ShortcutPreset.allCases {
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.displayString.isEmpty)
            #expect(!preset.detail.isEmpty)
        }
    }

    @Test("Raw values are stable, because preferences persist them")
    func rawValuesAreStable() {
        #expect(ShortcutPreset.fnGlobe.rawValue == "fnGlobe")
        #expect(ShortcutPreset.optionSpace.rawValue == "optionSpace")
    }

    @Test("Fn is the only preset that needs Accessibility")
    func onlyFnNeedsAccessibility() {
        let needing = ShortcutPreset.allCases.filter(\.requiresAccessibility)
        #expect(needing == [.fnGlobe])
    }

    @Test("The fallback works without Accessibility, so it can always take over")
    func fallbackNeedsNoAccessibility() {
        #expect(!ShortcutPreset.fallback.requiresAccessibility)
        #expect(ShortcutPreset.fallback != ShortcutPreset.default)
    }

    @Test("Presets are distinguishable on screen")
    func displayStringsAreUnique() {
        let strings = Set(ShortcutPreset.allCases.map(\.displayString))
        #expect(strings.count == ShortcutPreset.allCases.count)
    }
}

#if os(macOS)
@Suite("Preset to key mapping")
struct ShortcutPresetMappingTests {
    @Test("Fn is the only preset that isn't a Carbon chord")
    func fnIsNotCarbon() {
        #expect(ShortcutPreset.fnGlobe.shortcut.kind == .functionKey)

        for preset in ShortcutPreset.allCases where preset != .fnGlobe {
            guard case .carbon = preset.shortcut.kind else {
                Issue.record("\(preset) should map to a Carbon chord")
                continue
            }
        }
    }

    @Test("Chords carry modifiers, so they can't fire on a bare keypress")
    func chordsHaveModifiers() {
        for preset in ShortcutPreset.allCases {
            guard case .carbon(_, let modifiers) = preset.shortcut.kind else { continue }
            #expect(modifiers != 0, "\(preset) has no modifier keys")
        }
    }

    @Test("A shortcut renders the same way everywhere it's shown")
    func shortcutCarriesItsPresetDisplayString() {
        for preset in ShortcutPreset.allCases {
            #expect(preset.shortcut.displayString == preset.displayString)
        }
    }

    @Test("No two presets map to the same key combination")
    func mappingsAreUnique() {
        var seen: [HotkeyShortcut.Kind] = []
        for preset in ShortcutPreset.allCases {
            let kind = preset.shortcut.kind
            #expect(!seen.contains(kind), "\(preset) duplicates another preset")
            seen.append(kind)
        }
    }
}
#endif
