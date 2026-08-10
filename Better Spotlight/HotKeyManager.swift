import AppKit
import ApplicationServices
import Carbon

/// Registers global launcher shortcuts.
///
/// Important: on modern macOS, Carbon often claims ⌘Space with `noErr` but never
/// delivers the event. For Spotlight takeover we always also install a CGEvent tap
/// when Accessibility is granted.
final class HotKeyManager: @unchecked Sendable {
    private let lock = NSLock()
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onPressed: (() -> Void)?
    private var lastFireAt: Date = .distantPast

    private var tapKeyCode: Int64 = 49
    private var tapRequiresCommand = false
    private var tapRequiresOption = false
    private var tapRequiresControl = false
    private var tapRequiresShift = false

    private(set) var lastStatusMessage: String = "Not registered"

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        claimsSpotlight: Bool,
        alsoRegisterOptionSpaceFallback: Bool,
        handler: @escaping () -> Void
    ) {
        unregister()

        lock.lock()
        onPressed = handler
        tapKeyCode = Int64(keyCode)
        tapRequiresCommand = modifiers & UInt32(cmdKey) != 0
        tapRequiresOption = modifiers & UInt32(optionKey) != 0
        tapRequiresControl = modifiers & UInt32(controlKey) != 0
        tapRequiresShift = modifiers & UInt32(shiftKey) != 0
        lock.unlock()

        if claimsSpotlight {
            SpotlightShortcutTakeover.disableSystemSpotlightShortcut()
        }

        installSharedHandlerIfNeeded()

        var parts: [String] = []
        let carbonOK = registerCarbonHotKey(keyCode: keyCode, modifiers: modifiers, id: 1)
        parts.append(carbonOK ? "Carbon OK" : "Carbon failed")

        // Always keep ⌥Space as escape hatch unless it already is the primary.
        let primaryIsOptionSpace =
            keyCode == UInt32(kVK_Space) && modifiers == UInt32(optionKey)
        if alsoRegisterOptionSpaceFallback, !primaryIsOptionSpace {
            let fallbackOK = registerCarbonHotKey(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(optionKey),
                id: 2
            )
            parts.append(fallbackOK ? "⌥Space OK" : "⌥Space failed")
        }

        // Event tap: required for reliable ⌘Space; also used if Carbon failed.
        let wantsTap = claimsSpotlight || !carbonOK
        var tapOK = false
        if wantsTap {
            if !SpotlightShortcutTakeover.isAccessibilityTrusted {
                _ = SpotlightShortcutTakeover.ensureAccessibility(prompt: claimsSpotlight)
            }
            if SpotlightShortcutTakeover.isAccessibilityTrusted {
                tapOK = registerEventTap()
                parts.append(tapOK ? "Event tap OK" : "Event tap failed")
            } else {
                parts.append("Event tap needs Accessibility")
            }
        }

        let working = carbonOK || tapOK
        lastStatusMessage = working
            ? "Listening (\(parts.joined(separator: ", ")))"
            : "Failed (\(parts.joined(separator: ", ")))"
        DebugLog.log("HotKey: \(lastStatusMessage)")
    }

    func unregister() {
        lock.lock()
        defer { lock.unlock() }

        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        onPressed = nil
        lastStatusMessage = "Not registered"
    }

    deinit {
        unregister()
    }

    private func fire() {
        // Carbon + CGEvent tap can both deliver the same physical keypress.
        lock.lock()
        let now = Date()
        if now.timeIntervalSince(lastFireAt) < 0.08 {
            lock.unlock()
            return
        }
        lastFireAt = now
        let handler = onPressed
        lock.unlock()
        DispatchQueue.main.async {
            handler?()
        }
    }

    private func installSharedHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if hotKeyID.signature == OSType(0x4253_504C) {
                    manager.fire()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        if status != noErr {
            DebugLog.log("InstallEventHandler failed: \(status)")
        }
    }

    @discardableResult
    private func registerCarbonHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4253_504C), id: id) // "BSPL"
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
            return true
        }
        DebugLog.log("RegisterEventHotKey id=\(id) failed: \(status)")
        return false
    }

    private func registerEventTap() -> Bool {
        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let command = event.flags.contains(.maskCommand)
                let shift = event.flags.contains(.maskShift)
                let option = event.flags.contains(.maskAlternate)
                let control = event.flags.contains(.maskControl)

                let matches =
                    keyCode == manager.tapKeyCode
                    && command == manager.tapRequiresCommand
                    && option == manager.tapRequiresOption
                    && control == manager.tapRequiresControl
                    && shift == manager.tapRequiresShift

                if matches {
                    manager.fire()
                    return nil // swallow so nothing else also handles it
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            DebugLog.log("CGEvent.tapCreate failed")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}
