import CoreGraphics
import EarshotCore

/// Push-to-talk via a listen-only event tap; the logic lives in `PushToTalk`.
/// Needs Input Monitoring (granted to Terminal). Callbacks arrive on the main run loop.
public final class Hotkey {
    private var machine: PushToTalk
    private let onDown: () -> Void
    private let onUp: () -> Void
    private let onCancel: () -> Void
    private var tap: CFMachPort?

    public init(machine: PushToTalk, onDown: @escaping () -> Void, onUp: @escaping () -> Void,
                onCancel: @escaping () -> Void) {
        self.machine = machine
        self.onDown = onDown
        self.onUp = onUp
        self.onCancel = onCancel
    }

    /// False when macOS refuses the tap (Input Monitoring not granted).
    public func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
                                              guard let info else { return Unmanaged.passUnretained(event) }
                                              Unmanaged<Hotkey>.fromOpaque(info).takeUnretainedValue()
                                                  .handle(type, event)
                                              return Unmanaged.passUnretained(event)
                                          }, userInfo: me)
        else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        let action: PushToTalk.Action?
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .flagsChanged:
            action = machine.flagsChanged(keycode: event.getIntegerValueField(.keyboardEventKeycode),
                                          flags: event.flags.rawValue)
        case .keyDown:
            // Earshot's own synthetic typing must not cancel anything; it only types after release anyway.
            action = machine.keyDown(keycode: event.getIntegerValueField(.keyboardEventKeycode))
        case .keyUp:
            action = machine.keyUp(keycode: event.getIntegerValueField(.keyboardEventKeycode))
        default:
            return
        }
        switch action {
        case .start: onDown()
        case .stop: onUp()
        case .cancel: onCancel()
        case nil: break
        }
    }
}
