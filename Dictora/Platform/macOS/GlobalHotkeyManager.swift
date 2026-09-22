#if os(macOS)
import Carbon.HIToolbox
import Foundation
import Observation
import OSLog

/// A system-wide key combination.
struct HotkeyShortcut: Equatable, Sendable {
    /// Virtual key code, e.g. `kVK_Space`.
    var keyCode: UInt32
    /// Carbon modifier mask, e.g. `optionKey`.
    var modifiers: UInt32

    /// Dictora's intended default shortcut.
    static let optionSpace = HotkeyShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCode == UInt32(kVK_Space) ? "Space" : "Key \(keyCode)")
        return parts.joined()
    }
}

/// Registers Dictora's global dictation shortcut.
///
/// Uses Carbon's `RegisterEventHotKey`, which is the only public, non-private
/// API for a true system-wide hotkey that works inside the App Sandbox without
/// requiring Accessibility or Input Monitoring permission.
@MainActor
@Observable
final class GlobalHotkeyManager {
    enum RegistrationState: Equatable, Sendable {
        case inactive
        case active
        case failed(String)

        var isActive: Bool { self == .active }
    }

    private(set) var state: RegistrationState = .inactive
    private(set) var shortcut: HotkeyShortcut = .optionSpace

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onPress: (@MainActor () -> Void)?
    private var onRelease: (@MainActor () -> Void)?

    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "GlobalHotkey")

    /// `'DCTR'` — four-char signature Carbon uses to namespace hotkey IDs.
    private static let signature: OSType = 0x4443_5452
    private static let identifier: UInt32 = 1
    /// Lets the C event handler find the manager that owns a given hotkey ID.
    fileprivate static var registry: [UInt32: GlobalHotkeyManager] = [:]

    init() {}

    /// Carbon resources are released in ``unregister()`` rather than `deinit`,
    /// which cannot touch main-actor state.
    /// - Parameter onRelease: Only needed for hold-to-talk. Carbon delivers the
    ///   release event even when the shortcut is used as a simple toggle, so
    ///   callers that ignore it simply pass `nil`.
    @discardableResult
    func register(
        _ shortcut: HotkeyShortcut = .optionSpace,
        onPress: @escaping @MainActor () -> Void,
        onRelease: (@MainActor () -> Void)? = nil
    ) -> RegistrationState {
        unregister()

        self.shortcut = shortcut
        self.onPress = onPress
        self.onRelease = onRelease

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        var handlerRef: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            dictoraHotkeyEventHandler,
            eventTypes.count,
            &eventTypes,
            nil,
            &handlerRef
        )
        guard handlerStatus == noErr else {
            return finishWithFailure("Could not install the keyboard event handler (\(handlerStatus)).")
        }
        eventHandlerRef = handlerRef

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        var reference: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard registerStatus == noErr, let reference else {
            // The most common cause is another app already owning the combination.
            return finishWithFailure("\(shortcut.displayString) is already in use by another app.")
        }

        hotKeyRef = reference
        Self.registry[Self.identifier] = self
        state = .active
        logger.info("Registered global shortcut \(shortcut.displayString, privacy: .public)")
        return state
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        Self.registry[Self.identifier] = nil
        onPress = nil
        onRelease = nil
        state = .inactive
    }

    fileprivate func handlePress() {
        onPress?()
    }

    fileprivate func handleRelease() {
        onRelease?()
    }

    private func finishWithFailure(_ message: String) -> RegistrationState {
        logger.error("\(message, privacy: .public)")
        unregister()
        state = .failed(message)
        return state
    }
}

/// Carbon requires a C function pointer, so this cannot be a method.
///
/// Carbon delivers hotkey events on the main run loop, which is why hopping
/// back onto the main actor with `assumeIsolated` is safe here.
private func dictoraHotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let identifier = hotKeyID.id
    let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    MainActor.assumeIsolated {
        guard let manager = GlobalHotkeyManager.registry[identifier] else { return }
        if isPress {
            manager.handlePress()
        } else {
            manager.handleRelease()
        }
    }
    return noErr
}
#endif
