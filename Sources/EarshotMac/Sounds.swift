import AppKit

/// Short system sounds. The finish sound is the only thing Earshot ever plays on its own.
public enum Sounds {
    public static func finish() { play("Glass") }
    public static func listenStart() { play("Tink") }
    public static func listenStop() { play("Pop") }

    private static func play(_ name: String) {
        guard let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        s.volume = 0.4
        s.play()
    }
}
