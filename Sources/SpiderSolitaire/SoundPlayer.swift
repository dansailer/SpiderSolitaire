#if canImport(AppKit)
import AppKit
import SpiderBoard

/// Plays built-in macOS system sounds (/System/Library/Sounds). No bundled audio.
enum SoundPlayer {
    @MainActor
    static func play(_ cue: SoundCue) {
        guard let sound: NSSound = NSSound(named: NSSound.Name(cue.systemSoundName)) else { return }
        if sound.isPlaying { _ = sound.stop() }
        _ = sound.play()
    }
}
#endif
