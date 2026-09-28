// Adapted from Sokuji native/audio-host/mac/main.swift (AGPL-3.0),
// reviewed at 821a641ecb510d591b3e8b542bfbf798c80f0f9c.
import CoreAudio
import Foundation

/// A diagnostic about open output streams, not about audible samples. Excluding
/// our process tree here must never change the audio that the tap captures.
enum AudioRenderingActivity {
    static func isRendering(
        _ objects: [AudioObjectID],
        excluding roots: Set<pid_t>,
        processID: (AudioObjectID) -> pid_t?,
        parentProcessID: (pid_t) -> pid_t,
        isRunningOutput: (AudioObjectID) -> Bool
    ) -> Bool {
        objects.contains { object in
            if !roots.isEmpty, let pid = processID(object),
               isDescendant(pid, of: roots, parentProcessID: parentProcessID) {
                return false
            }
            // A failed PID lookup is not proof that this is our own process.
            return isRunningOutput(object)
        }
    }

    static func isDescendant(
        _ pid: pid_t,
        of roots: Set<pid_t>,
        parentProcessID: (pid_t) -> pid_t
    ) -> Bool {
        var current = pid
        for _ in 0..<8 {
            // launchd is everyone's ancestor; never let PID 1 exclude the world.
            guard current > 1 else { return false }
            if roots.contains(current) { return true }
            current = parentProcessID(current)
        }
        return false
    }
}
