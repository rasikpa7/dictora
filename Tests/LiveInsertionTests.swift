import AppKit
import ApplicationServices
import Foundation
import Testing

@testable import DictoraMac

private let liveInsertionEnabled: Bool =
    ProcessInfo.processInfo.environment["DICTORA_LIVE_TESTS"] == "1" && AXIsProcessTrusted()

/// Inserts into a real TextEdit window. Needs Accessibility access for the test
/// host, and is off unless `DICTORA_LIVE_TESTS=1`, because it drives another app.
@Suite("Live insertion", .serialized)
@MainActor
struct LiveInsertionTests {
    private func openTextEdit() async throws -> NSRunningApplication {
        // The previous test's TextEdit may still be shutting down.
        while !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty {
            try await Task.sleep(for: .milliseconds(200))
        }
        try await Task.sleep(for: .seconds(1))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dictora-live-\(UUID().uuidString).txt")
        try "".write(to: file, atomically: true, encoding: .utf8)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let app = try await NSWorkspace.shared.open(
            [file],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
            configuration: configuration
        )
        try await Task.sleep(for: .seconds(2))
        return app
    }

    private func fieldText(of app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(unsafeDowncast(focused, to: AXUIElement.self), kAXValueAttribute as CFString, &value)
        return value as? String
    }

    @Test("Direct insertion lands in the field and is verified", .enabled(if: liveInsertionEnabled))
    func accessibilityInsertion() async throws {
        let app = try await openTextEdit()
        defer { app.forceTerminate() }

        let manager = TextInsertionManager(accessibility: AccessibilityManager())
        let outcome = await manager.insert("Hello from Dictora.", into: app.processIdentifier)

        #expect(outcome == .insertedViaAccessibility)
        #expect(fieldText(of: app)?.contains("Hello from Dictora.") == true)
    }

    @Test("Paste fallback inserts the text and restores the whole clipboard", .enabled(if: liveInsertionEnabled))
    func pasteInsertionRestoresClipboard() async throws {
        let app = try await openTextEdit()
        defer { app.forceTerminate() }

        // A clipboard holding something that isn't plain text must survive.
        let customType = NSPasteboard.PasteboardType("com.dictora.test.blob")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("KEEP ME", forType: .string)
        item.setData(Data([1, 2, 3, 4]), forType: customType)
        pasteboard.writeObjects([item])

        let manager = TextInsertionManager(accessibility: AccessibilityManager())
        let outcome = await manager.pasteUsingClipboard("Pasted by Dictora.")

        #expect(outcome == .pastedViaClipboard)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fieldText(of: app)?.contains("Pasted by Dictora.") == true)
        #expect(pasteboard.string(forType: .string) == "KEEP ME")
        #expect(pasteboard.data(forType: customType) == Data([1, 2, 3, 4]))
    }
}
