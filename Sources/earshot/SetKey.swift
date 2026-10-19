import CoreGraphics
import EarshotCore
import Foundation

/// `earshot set-key`: waits for one key press and saves it as the talk key.
func runSetKey() {
    print("Press the key you want to hold to talk (20 s)…")
    fflush(stdout)
    let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                      eventsOfInterest: mask, callback: { _, type, event, _ in
                                          let code = event.getIntegerValueField(.keyboardEventKeycode)
                                          switch type {
                                          // flagsChanged fires on release too; only a press sets a modifier flag.
                                          case .flagsChanged where event.flags.rawValue & 0xFF0000 != 0:
                                              chose(KeyChoice.fromModifier(keycode: code), code: code)
                                          case .keyDown:
                                              chose(KeyChoice.fromKey(keycode: code), code: code)
                                          default:
                                              break
                                          }
                                          return Unmanaged.passUnretained(event)
                                      }, userInfo: nil)
    else {
        print("Can't read the keyboard. Grant Input Monitoring to your terminal app (run `earshot doctor`).")
        exit(1)
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        print("No key pressed. Nothing changed.")
        exit(1)
    }
    RunLoop.main.run()
}

private func chose(_ choice: KeyChoice, code: Int64) {
    if case .rejected(let why) = choice {
        print("Key \(code): \(why).")
        fflush(stdout)
        return
    }
    var config = Config.load(Paths.live.configFile)
    choice.apply(to: &config)
    do {
        try config.save(Paths.live.configFile)
    } catch {
        print("Could not save \(Paths.live.configFile.path): \(error)")
        exit(1)
    }
    print("Saved: hold \(config.hotkeyLabel) to talk. Restart `earshot` to use it.")
    exit(0)
}
