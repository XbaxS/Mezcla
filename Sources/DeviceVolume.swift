import Foundation
import CoreAudio

struct VolumeTarget: Equatable {
    let objectID: AudioObjectID
    let uid: String
}

struct OutputVolumeState {
    var volume: Float?
    var canSetVolume = false
    var muted: Bool?
    var canSetMute = false
}

protocol VolumeHardware {
    func uid(_ device: AudioObjectID) -> String?
    func channels(_ device: AudioObjectID) -> [UInt32]
    func read(_ device: AudioObjectID, selector: UInt32, element: UInt32) -> Float?
    func writable(_ device: AudioObjectID, selector: UInt32, element: UInt32) -> Bool
    func write(_ device: AudioObjectID, selector: UInt32, element: UInt32, value: Float) -> OSStatus
}

struct CoreAudioVolumeHardware: VolumeHardware {
    private func address(_ selector: UInt32, _ element: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }
    func uid(_ device: AudioObjectID) -> String? {
        var property = address(kAudioDevicePropertyDeviceUID)
        property.mScope = kAudioObjectPropertyScopeGlobal
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    func channels(_ device: AudioObjectID) -> [UInt32] {
        var property = address(kAudioDevicePropertyStreamConfiguration), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr, size > 0 else { return [] }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, memory) == noErr else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
        let count = buffers.reduce(UInt32(0)) { $0 + $1.mNumberChannels }
        return count > 0 ? Array(1...count) : []
    }
    func read(_ device: AudioObjectID, selector: UInt32, element: UInt32) -> Float? {
        var property = address(selector, element)
        guard AudioObjectHasProperty(device, &property) else { return nil }
        var size: UInt32 = 4
        if selector == kAudioDevicePropertyMute {
            var value: UInt32 = 0
            return AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr ? Float(value) : nil
        }
        var value: Float = 0
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr, value.isFinite else { return nil }
        return min(1, max(0, value))
    }
    func writable(_ device: AudioObjectID, selector: UInt32, element: UInt32) -> Bool {
        var property = address(selector, element), settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &property) &&
            AudioObjectIsPropertySettable(device, &property, &settable) == noErr && settable.boolValue
    }
    func write(_ device: AudioObjectID, selector: UInt32, element: UInt32, value: Float) -> OSStatus {
        var property = address(selector, element)
        if selector == kAudioDevicePropertyMute {
            var mute: UInt32 = value > 0 ? 1 : 0
            return AudioObjectSetPropertyData(device, &property, 0, nil, 4, &mute)
        }
        var volume = value
        return AudioObjectSetPropertyData(device, &property, 0, nil, 4, &volume)
    }
}

enum OutputVolumeError: LocalizedError {
    case disconnected, unsupported, invalidValue, writeFailed(OSStatus)
    var errorDescription: String? {
        switch self {
        case .disconnected: return "La salida se desconectó. Vuelve a seleccionarla."
        case .unsupported: return "Esta salida no permite ajustar su volumen desde el Mac."
        case .invalidValue: return "El volumen solicitado no es válido."
        case .writeFailed(let code): return "No se pudo ajustar esta salida (\(code))."
        }
    }
}

/// Addresses the chosen physical device directly; never changes the system's default output.
/// Hardware volume deliberately stays outside route identity and saved per-app gain.
final class DeviceVolumeService {
    private let hardware: VolumeHardware
    init(hardware: VolumeHardware = CoreAudioVolumeHardware()) { self.hardware = hardware }

    private func controls(_ target: VolumeTarget, selector: UInt32) -> [(element: UInt32, value: Float)] {
        if let main = hardware.read(target.objectID, selector: selector, element: 0) { return [(0, main)] }
        return hardware.channels(target.objectID).compactMap { element in
            hardware.read(target.objectID, selector: selector, element: element).map { (element, $0) }
        }
    }
    private func writable(_ target: VolumeTarget, selector: UInt32, controls: [(element: UInt32, value: Float)]) -> Bool {
        !controls.isEmpty && controls.allSatisfy { hardware.writable(target.objectID, selector: selector, element: $0.element) }
    }
    func state(_ target: VolumeTarget) -> OutputVolumeState {
        guard hardware.uid(target.objectID) == target.uid else { return OutputVolumeState() }
        let volume = controls(target, selector: kAudioDevicePropertyVolumeScalar)
        let mute = controls(target, selector: kAudioDevicePropertyMute)
        return OutputVolumeState(volume: volume.map(\.value).max(),
            canSetVolume: writable(target, selector: kAudioDevicePropertyVolumeScalar, controls: volume),
            muted: mute.isEmpty ? nil : mute.allSatisfy { $0.value != 0 },
            canSetMute: writable(target, selector: kAudioDevicePropertyMute, controls: mute))
    }
    func setVolume(_ requested: Float, target: VolumeTarget) throws {
        guard requested.isFinite else { throw OutputVolumeError.invalidValue }
        let volume = min(1, max(0, requested))
        let current = controls(target, selector: kAudioDevicePropertyVolumeScalar)
        let maximum = current.map(\.value).max() ?? 0
        // Preserve stereo/multichannel balance rather than forcing both sides equal.
        let values = current.map { maximum > 0 ? volume * $0.value / maximum : volume }
        try write(target, selector: kAudioDevicePropertyVolumeScalar, previous: current, values: values)
    }
    func setMuted(_ muted: Bool, target: VolumeTarget) throws {
        let current = controls(target, selector: kAudioDevicePropertyMute)
        try write(target, selector: kAudioDevicePropertyMute, previous: current, values: current.map { _ in muted ? 1 : 0 })
    }
    private func write(_ target: VolumeTarget, selector: UInt32, previous: [(element: UInt32, value: Float)], values: [Float]) throws {
        guard hardware.uid(target.objectID) == target.uid else { throw OutputVolumeError.disconnected }
        guard writable(target, selector: selector, controls: previous) else { throw OutputVolumeError.unsupported }
        var applied: [(element: UInt32, value: Float)] = []
        for (control, value) in zip(previous, values) {
            // A removed device's object ID can be reused. Never write through a stale UID.
            guard hardware.uid(target.objectID) == target.uid else { throw OutputVolumeError.disconnected }
            let status = hardware.write(target.objectID, selector: selector, element: control.element, value: value)
            guard status == noErr else {
                for saved in applied.reversed() where hardware.uid(target.objectID) == target.uid {
                    _ = hardware.write(target.objectID, selector: selector, element: saved.element, value: saved.value)
                }
                throw OutputVolumeError.writeFailed(status)
            }
            applied.append(control)
        }
    }
}
