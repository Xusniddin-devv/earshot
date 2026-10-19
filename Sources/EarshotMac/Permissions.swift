import AVFoundation
import ApplicationServices
import CoreGraphics

/// Preflight checks for `earshot doctor`. All of these are granted to Terminal, not Earshot.
public enum Permissions {
    public static var accessibility: Bool { AXIsProcessTrusted() }
    public static var inputMonitoring: Bool { CGPreflightListenEventAccess() }
    public static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    /// Shows the system prompts for the permissions that can prompt.
    public static func request() {
        if !accessibility {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        if !inputMonitoring { _ = CGRequestListenEventAccess() }
        if microphone == .notDetermined { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
    }
}
