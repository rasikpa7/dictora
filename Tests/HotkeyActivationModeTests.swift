import Foundation
import Testing

#if os(macOS)
import Carbon.HIToolbox
@testable import DictoraMac
#else
@testable import DictoraiOS
#endif

@Suite("HotkeyActivationMode")
struct HotkeyActivationModeTests {
    @Test("Every mode is fully described for the settings picker")
    func everyModeIsDescribed() {
        for mode in HotkeyActivationMode.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.shortDescription.isEmpty)
        }
    }

    @Test("Raw values are stable, because preferences persist them")
    func rawValuesAreStable() {
        #expect(HotkeyActivationMode.doubleTap.rawValue == "doubleTap")
        #expect(HotkeyActivationMode.holdToTalk.rawValue == "holdToTalk")
    }

    @Test("Hold-to-talk is the default for Fn-style dictation")
    func defaultIsHoldToTalk() {
        #expect(HotkeyActivationMode.default == .holdToTalk)
    }

    @Test("Legacy toggle preference decodes as double-tap")
    func legacyToggleDecodesAsDoubleTap() throws {
        let data = Data(#""toggle""#.utf8)
        let decoded = try JSONDecoder().decode(HotkeyActivationMode.self, from: data)
        #expect(decoded == .doubleTap)
    }
}

#if os(macOS)
@Suite("Global shortcut")
struct HotkeyShortcutTests {
    @Test("The default shortcut is Fn")
    func defaultShortcutIsFn() {
        #expect(ShortcutPreset.default == .fnGlobe)
        #expect(ShortcutPreset.default.shortcut.kind == .functionKey)
        #expect(ShortcutPreset.default.shortcut.displayString == "Fn")
    }

    @Test("Chords render with their modifier symbols")
    func chordsRenderModifiers() {
        #expect(ShortcutPreset.optionSpace.shortcut.displayString == "⌥Space")
        #expect(ShortcutPreset.controlOptionSpace.shortcut.displayString == "⌃⌥Space")
        #expect(ShortcutPreset.commandShiftD.shortcut.displayString == "⇧⌘D")
    }

    @Test("Space-based chords share a key code and differ only in modifiers")
    func spaceChordsDifferByModifier() {
        guard
            case .carbon(let optionKeyCode, let optionModifiers) = ShortcutPreset.optionSpace.shortcut.kind,
            case .carbon(let controlKeyCode, let controlModifiers) = ShortcutPreset.controlOptionSpace.shortcut.kind
        else {
            Issue.record("Both presets should be Carbon chords")
            return
        }
        #expect(optionKeyCode == controlKeyCode)
        #expect(optionModifiers != controlModifiers)
    }
}

@Suite("Text insertion outcome")
struct TextInsertionOutcomeTests {
    @Test("Only Accessibility and paste actually reach the target app")
    func reachedTargetApp() {
        #expect(TextInsertionOutcome.insertedViaAccessibility.reachedTargetApp)
        #expect(TextInsertionOutcome.pastedViaClipboard.reachedTargetApp)
        #expect(!TextInsertionOutcome.copiedToClipboard(reason: "no access").reachedTargetApp)
        #expect(!TextInsertionOutcome.failed(reason: "empty").reachedTargetApp)
    }

    @Test("Successful outcomes need no explanation, unsuccessful ones carry theirs")
    func detailAccompaniesFailures() {
        #expect(TextInsertionOutcome.insertedViaAccessibility.detail == nil)
        #expect(TextInsertionOutcome.copiedToClipboard(reason: "no access").detail == "no access")
        #expect(TextInsertionOutcome.failed(reason: "empty").detail == "empty")
    }
}
#endif
