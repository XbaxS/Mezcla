import Foundation
import CoreAudio

private struct Property: Hashable {
    let device: AudioObjectID
    let selector: UInt32
    let element: UInt32
}
private final class FakeHardware: VolumeHardware {
    var identifiers: [AudioObjectID: String] = [10: "Mac-speakers", 20: "Bluetooth"]
    var values: [Property: Float] = [:]
    var locked = Set<Property>()
    var writes: [Property] = []
    var failing: Property?
    func key(_ device: UInt32, _ element: UInt32 = 0, _ selector: UInt32 = kAudioDevicePropertyVolumeScalar) -> Property {
        Property(device: device, selector: selector, element: element)
    }
    func uid(_ device: AudioObjectID) -> String? { identifiers[device] }
    func channels(_ device: AudioObjectID) -> [UInt32] { [1, 2] }
    func read(_ device: AudioObjectID, selector: UInt32, element: UInt32) -> Float? { values[key(device, element, selector)] }
    func writable(_ device: AudioObjectID, selector: UInt32, element: UInt32) -> Bool {
        let property = key(device, element, selector)
        return values[property] != nil && !locked.contains(property)
    }
    func write(_ device: AudioObjectID, selector: UInt32, element: UInt32, value: Float) -> OSStatus {
        let property = key(device, element, selector)
        writes.append(property)
        if property == failing { return -1 }
        values[property] = value
        return noErr
    }
}

@main
struct DeviceVolumeTests {
    static func near(_ a: Float?, _ b: Float) { precondition(a != nil && abs(a! - b) < 0.0001) }
    static func expectFailure(_ action: () throws -> Void) {
        do { try action(); preconditionFailure("Expected an error") } catch {}
    }
    static func main() throws {
        let hardware = FakeHardware(), mac = VolumeTarget(objectID: 10, uid: "Mac-speakers")
        let service = DeviceVolumeService(hardware: hardware)
        hardware.values[hardware.key(10)] = 0.2
        hardware.values[hardware.key(20)] = 0.6
        hardware.values[hardware.key(10, 0, kAudioDevicePropertyMute)] = 0
        hardware.values[hardware.key(20, 0, kAudioDevicePropertyMute)] = 0

        // Regression: Safari uses the Mac while the keyboard controls Bluetooth.
        // Raising the secondary device to 100% must not touch Bluetooth at all.
        try service.setVolume(1, target: mac)
        near(hardware.values[hardware.key(10)], 1)
        near(hardware.values[hardware.key(20)], 0.6)
        precondition(hardware.writes.allSatisfy { $0.device == 10 && $0.selector == kAudioDevicePropertyVolumeScalar })
        try service.setMuted(true, target: mac)
        precondition(service.state(mac).muted == true)
        near(hardware.values[hardware.key(20, 0, kAudioDevicePropertyMute)], 0)
        try service.setMuted(false, target: mac)
        precondition(service.state(mac).muted == false)
        // External hardware/keyboard changes appear on the next read.
        hardware.values[hardware.key(10)] = 0.7
        near(service.state(mac).volume, 0.7)
        try service.setVolume(2, target: mac); near(service.state(mac).volume, 1)
        try service.setVolume(-1, target: mac); near(service.state(mac).volume, 0)
        let beforeInvalid = hardware.writes.count
        expectFailure { try service.setVolume(.nan, target: mac) }
        precondition(hardware.writes.count == beforeInvalid)

        // Hardware with separate channels keeps its relative balance.
        hardware.values[hardware.key(10)] = nil
        hardware.values[hardware.key(10, 1)] = 0.2
        hardware.values[hardware.key(10, 2)] = 0.4
        try service.setVolume(1, target: mac)
        near(hardware.values[hardware.key(10, 1)], 0.5)
        near(hardware.values[hardware.key(10, 2)], 1)
        hardware.failing = hardware.key(10, 2)
        expectFailure { try service.setVolume(0.4, target: mac) }
        near(hardware.values[hardware.key(10, 1)], 0.5) // first channel rolled back
        near(hardware.values[hardware.key(10, 2)], 1)
        hardware.failing = nil
        try service.setVolume(0, target: mac)
        try service.setVolume(0.3, target: mac)
        near(hardware.values[hardware.key(10, 1)], 0.3)
        near(hardware.values[hardware.key(10, 2)], 0.3)
        hardware.locked.insert(hardware.key(10, 2))
        precondition(!service.state(mac).canSetVolume)
        let beforeLocked = hardware.writes.count
        expectFailure { try service.setVolume(1, target: mac) }
        precondition(hardware.writes.count == beforeLocked)

        // Object IDs reused after disconnect must never address the new device.
        hardware.identifiers[10] = "different-device"
        let beforeDisconnect = hardware.writes.count
        expectFailure { try service.setMuted(true, target: mac) }
        expectFailure { try service.setVolume(1, target: mac) }
        precondition(service.state(mac).volume == nil && hardware.writes.count == beforeDisconnect)
        hardware.identifiers[10] = nil
        expectFailure { try service.setVolume(0.5, target: mac) }
        let unsupported = VolumeTarget(objectID: 30, uid: "HDMI")
        hardware.identifiers[30] = "HDMI"
        precondition(!service.state(unsupported).canSetVolume)
        expectFailure { try service.setVolume(1, target: unsupported) }
        print("PASS: independent device volume/mute, full volume on secondary output, live readback, stereo balance, rollback, read-only devices and stale device IDs.")
    }
}
