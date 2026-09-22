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
        #expect(HotkeyActivationMode.toggle.rawValue == "toggle")
        #expect(HotkeyActivationMode.holdToTalk.rawValue == "holdToTalk")
    }

    @Test("Tap-to-toggle is the default")
    func defaultIsToggle() {
        #expect(HotkeyActivationMode.default == .toggle)
    }
}

#if os(macOS)
@Suite("Global shortcut")
struct HotkeyShortcutTests {
    @Test("The default shortcut is Option + Space")
    func defaultShortcutIsOptionSpace() {
        let shortcut = HotkeyShortcut.optionSpace
        #expect(shortcut.displayString == "⌥Space")
    }

    @Test("Modifiers are rendered in the standard macOS order")
    func modifierOrder() {
        let shortcut = HotkeyShortcut(
            keyCode: HotkeyShortcut.optionSpace.keyCode,
            modifiers: HotkeyShortcut.optionSpace.modifiers | UInt32(cmdKey) | UInt32(shiftKey)
        )
        #expect(shortcut.displayString == "⌥⇧⌘Space")
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
