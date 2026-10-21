import Foundation
import CoreAudio

/// Opt-in hardware regression check. Briefly lowers built-in speakers and restores
/// their volume. Requires another device to be the current system output.
@main
struct DeviceVolumeHardwareCheck {
    static func defaultOutput() -> AudioObjectID {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var result: AudioObjectID = 0, size: UInt32 = 4
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &result)
        return result
    }
    static func devices() -> [AudioObjectID] {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
        _ = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!) }
        return ids
    }
    static func main() throws {
        guard CommandLine.arguments.contains("--verify") else {
            print("Use --verify to briefly change and restore the built-in speaker volume.")
            return
        }
        let hardware = CoreAudioVolumeHardware(), service = DeviceVolumeService()
        let primaryID = defaultOutput()
        guard let speakerID = devices().first(where: { hardware.uid($0) == "BuiltInSpeakerDevice" }),
              speakerID != primaryID, let primaryUID = hardware.uid(primaryID) else {
            print("SKIP: connect a separate system output before testing the secondary speakers.")
            exit(77)
        }
        let speakers = VolumeTarget(objectID: speakerID, uid: "BuiltInSpeakerDevice")
        let primary = VolumeTarget(objectID: primaryID, uid: primaryUID)
        let before = service.state(speakers), otherBefore = service.state(primary)
        guard before.canSetVolume, let initial = before.volume else {
            print("FAIL: built-in speaker volume is unavailable")
            exit(1)
        }
        let trial: Float = initial > 0.1 ? initial - 0.1 : (initial > 0.01 ? 0 : 0.02)
        var changed: Float?
        var failure: Error?
        do {
            try service.setVolume(trial, target: speakers)
            Thread.sleep(forTimeInterval: 0.25)
            changed = service.state(speakers).volume
        } catch { failure = error }
        // Always attempt restoration before checking any assertions.
        try service.setVolume(initial, target: speakers)
        Thread.sleep(forTimeInterval: 0.25)
        let after = service.state(speakers), otherAfter = service.state(primary)
        func equal(_ a: Float?, _ b: Float?) -> Bool {
            if let a, let b { return abs(a - b) < 0.005 }
            return a == nil && b == nil
        }
        let success = failure == nil && changed != nil && abs(changed! - trial) < 0.03 &&
            !equal(changed, initial) && equal(after.volume, initial) &&
            equal(otherBefore.volume, otherAfter.volume) && otherBefore.muted == otherAfter.muted &&
            before.muted == after.muted && defaultOutput() == primaryID
        let report: [String: Any] = ["success": success, "secondary_before": initial,
            "secondary_during": changed as Any? ?? NSNull(), "secondary_restored": after.volume as Any? ?? NSNull(),
            "primary_volume_unchanged": equal(otherBefore.volume, otherAfter.volume),
            "default_output_unchanged": defaultOutput() == primaryID]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if !success { exit(1) }
    }
}
