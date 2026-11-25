#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import Observation
import OSLog

/// A system-wide key combination, including the special Fn / Globe key.
struct HotkeyShortcut: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Carbon `RegisterEventHotKey` combination. Works without Accessibility.
        case carbon(keyCode: UInt32, modifiers: UInt32)
        /// Fn / Globe alone — observed via a CGEvent tap on `flagsChanged`,
        /// because a lone modifier cannot be a Carbon hotkey.
        case functionKey
    }

    var kind: Kind
    var displayString: String
}

extension ShortcutPreset {
    /// The key combination this preset maps to.
    var shortcut: HotkeyShortcut {
        switch self {
        case .fnGlobe:
            HotkeyShortcut(kind: .functionKey, displayString: displayString)
        case .optionSpace:
            HotkeyShortcut(
                kind: .carbon(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
                displayString: displayString
            )
        case .controlOptionSpace:
            HotkeyShortcut(
                kind: .carbon(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
                displayString: displayString
            )
        case .commandShiftD:
            HotkeyShortcut(
                kind: .carbon(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey)),
                displayString: displayString
            )
        case .controlShiftD:
            HotkeyShortcut(
                kind: .carbon(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | shiftKey)),
                displayString: displayString
            )
        }
    }
}

/// Registers Dictora's global dictation shortcut and reports key down and up.
///
/// Two mechanisms, chosen by the shortcut: Carbon's `RegisterEventHotKey` for
/// ordinary chords, and a listen-only `CGEvent` tap for the Fn / Globe key.
/// This type is mechanical — it registers what it is told to and reports why it
/// could not. Choosing a shortcut and falling back is policy, and lives in
/// ``SystemDictationCoordinator``.
@MainActor
@Observable
final class GlobalHotkeyManager {
    enum RegistrationState: Equatable, Sendable {
        case inactive
        case active
        case failed(String)

        var isActive: Bool { self == .active }
        var failureReason: String? {
            if case .failed(let reason) = self { return reason }
            return nil
        }
    }

    private(set) var state: RegistrationState = .inactive
    private(set) var shortcut: HotkeyShortcut?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var onPress: (@MainActor () -> Void)?
    private var onRelease: (@MainActor () -> Void)?

    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "GlobalHotkey")

    /// `'DCTR'` — four-char signature Carbon uses to namespace hotkey IDs.
    private static let signature: OSType = 0x4443_5452
    private static let identifier: UInt32 = 1
    /// Lets the C event handler find the manager that owns a given hotkey ID.
    fileprivate static var registry: [UInt32: GlobalHotkeyManager] = [:]

    init() {}

    /// - Parameter onRelease: Only called for hold-to-talk; both mechanisms
    ///   report key up, so callers that don't need it can ignore it.
    @discardableResult
    func register(
        _ shortcut: HotkeyShortcut,
        onPress: @escaping @MainActor () -> Void,
        onRelease: (@MainActor () -> Void)? = nil
    ) -> RegistrationState {
        unregister()

        self.shortcut = shortcut
        self.onPress = onPress
        self.onRelease = onRelease

        switch shortcut.kind {
        case .functionKey:
            return registerFunctionKey()
        case .carbon(let keyCode, let modifiers):
            return registerCarbon(keyCode: keyCode, modifiers: modifiers, display: shortcut.displayString)
        }
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
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        FnKeyTap.shared.detach()
        Self.registry[Self.identifier] = nil
        onPress = nil
        onRelease = nil
        shortcut = nil
        state = .inactive
    }

    fileprivate func handlePress() {
        onPress?()
    }

    fileprivate func handleRelease() {
        onRelease?()
    }

    // MARK: - Fn / Globe

    private func registerFunctionKey() -> RegistrationState {
        guard AXIsProcessTrusted() else {
            return finishWithFailure(
                "Dictora needs Accessibility access to watch for the Fn key."
            )
        }

        // Observing a lone modifier key is "input monitoring" to the system. The
        // tap can be created without it yet never receive an event, so check
        // first and ask, instead of registering a shortcut that silently does nothing.
        guard CGPreflightListenEventAccess() else {
            _ = CGRequestListenEventAccess()
            return finishWithFailure(
                "Dictora needs Input Monitoring access to watch for the Fn key. Allow it in System Settings › Privacy & Security › Input Monitoring."
            )
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: dictoraFnEventTapCallback,
            userInfo: nil
        ) else {
            return finishWithFailure(
                "Could not watch for the Fn key. Repair Accessibility access below, then try again."
            )
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // The tap must be reachable from the C callback, which cannot touch the
        // main actor. A session tap already sees events destined for Dictora
        // itself, so no additional local monitor is needed.
        FnKeyTap.shared.attach(tap: tap, manager: self)

        state = .active
        logger.info("Watching for the Fn key")
        return state
    }

    // MARK: - Carbon

    private func registerCarbon(keyCode: UInt32, modifiers: UInt32, display: String) -> RegistrationState {
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
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard registerStatus == noErr, let reference else {
            return finishWithFailure("\(display) is already in use by another app.")
        }

        hotKeyRef = reference
        Self.registry[Self.identifier] = self
        state = .active
        logger.info("Registered global shortcut \(display, privacy: .public)")
        return state
    }

    private func finishWithFailure(_ message: String) -> RegistrationState {
        logger.error("\(message, privacy: .public)")
        let attempted = shortcut
        unregister()
        shortcut = attempted
        state = .failed(message)
        return state
    }
}

// MARK: - Fn tap plumbing

/// Bridges the C event-tap callback, which runs outside any actor, to the
/// main-actor manager.
///
/// It also holds the edge state and the tap itself: macOS disables a tap that
/// takes too long to respond, and re-enabling it has to happen inside the
/// callback, where hopping to the main actor first is not possible.
private final class FnKeyTap: @unchecked Sendable {
    static let shared = FnKeyTap()

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var isDown = false
    private weak var manager: GlobalHotkeyManager?

    private init() {}

    func attach(tap: CFMachPort, manager: GlobalHotkeyManager) {
        lock.withLock {
            self.tap = tap
            self.manager = manager
            self.isDown = false
        }
    }

    func detach() {
        lock.withLock {
            tap = nil
            manager = nil
            isDown = false
        }
    }

    func reenableTap() {
        guard let tap = lock.withLock({ tap }) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns the owning manager only when this event is a genuine Fn edge —
    /// the same state repeated (auto-repeat, or Fn held while another modifier
    /// changes) is swallowed here.
    func manager(forFnDown down: Bool) -> GlobalHotkeyManager? {
        lock.withLock {
            guard down != isDown else { return nil }
            isDown = down
            return manager
        }
    }
}

/// Virtual key code reported by the Fn / Globe key.
private let fnVirtualKeyCode: Int64 = 63

private func dictoraFnEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // macOS disables a tap that is slow or that the user interrupts. Without
    // re-enabling it here the shortcut silently stops working until relaunch.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        FnKeyTap.shared.reenableTap()
        return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

    // Gating on the key code, not just the Fn flag: macOS sets the Fn flag on
    // arrow and function keys too, and any modifier pressed while Fn is held
    // repeats the flag. The key code identifies the Fn key itself.
    guard event.getIntegerValueField(.keyboardEventKeycode) == fnVirtualKeyCode else {
        return Unmanaged.passUnretained(event)
    }

    let isDown = event.flags.contains(.maskSecondaryFn)
    guard let manager = FnKeyTap.shared.manager(forFnDown: isDown) else {
        return Unmanaged.passUnretained(event)
    }

    Task { @MainActor in
        isDown ? manager.handlePress() : manager.handleRelease()
    }

    return Unmanaged.passUnretained(event)
}

/// Carbon requires a C function pointer, so this cannot be a method.
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
        isPress ? manager.handlePress() : manager.handleRelease()
    }
    return noErr
}
#endif
