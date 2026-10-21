import AppKit
import CoreAudio
import SwiftUI

enum AudioRead {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func number<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T {
        var value = initial, property = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0) }
        guard status == noErr else { return initial }
        return value
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var property = address(selector)
        var value: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0) }
        guard status == noErr else { return "" }
        return value?.takeRetainedValue() as String? ?? ""
    }
    static func list(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var property = address(selector, scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr, size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!) }
        return result == noErr ? Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size)) : []
    }
    static var defaultOutput: AudioObjectID { number(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0)) }
    static func outputs() -> [OutputDevice] {
        list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap { id in
            guard !list(id, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput).isEmpty else { return nil }
            let uid = string(id, kAudioDevicePropertyDeviceUID)
            guard !uid.isEmpty, !uid.hasPrefix("cl.mezcla.") else { return nil }
            return OutputDevice(id: uid, objectID: id, name: string(id, kAudioObjectPropertyName), sampleRate: number(id, kAudioDevicePropertyNominalSampleRate, initial: Float64(0)))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func owner(pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
            let parent = MZParentPID(current)
            if parent <= 1 || parent == current { break }
            current = parent
        }
        return NSRunningApplication(processIdentifier: pid)
    }
    static func apps() -> [AudioApplication] {
        var grouped: [String: AudioApplication] = [:]
        for process in list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            let pid = number(process, kAudioProcessPropertyPID, initial: pid_t(0))
            guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { continue }
            let active = number(process, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) != 0
            let owner = owner(pid: pid)
            let rawBundle = string(process, kAudioProcessPropertyBundleID)
            let bundle = owner?.bundleIdentifier ?? rawBundle
            let name = owner?.localizedName ?? (bundle.isEmpty ? "Proceso \(pid)" : bundle.components(separatedBy: ".").last ?? bundle)
            guard let identity = AppIdentityResolver.resolve(rawBundle: rawBundle, ownerBundle: owner?.bundleIdentifier,
                name: name, regularApp: owner?.activationPolicy == .regular, bundlePath: owner?.bundleURL?.path) else { continue }
            let key = identity.id
            let legacyKey = bundle.isEmpty ? "pid.\(pid)" : bundle
            if var app = grouped[key] {
                app.processes.append(process)
                app.active = app.active || active
                app.legacyIDs.insert(legacyKey)
                grouped[key] = app
            } else {
                let canonicalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identity.id)
                let icon = canonicalURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? owner?.icon
                grouped[key] = AudioApplication(id: key, name: identity.name, detail: identity.detail,
                    processes: [process], active: active, icon: icon, legacyIDs: [legacyKey])
            }
        }
        return grouped.values.map { app in var app = app; app.processes.sort(); return app }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct OutputDevice: Identifiable, Equatable {
    let id: String
    let objectID: AudioObjectID
    let name: String
    let sampleRate: Double
}
struct AudioApplication: Identifiable {
    let id: String
    let name: String
    let detail: String?
    var processes: [AudioObjectID]
    var active: Bool
    let icon: NSImage?
    var legacyIDs: Set<String>
}
struct AppSettings: Codable {
    var volume: Float = 1
    var muted = false
    var output = "default"
    var controlled = false
}
final class LiveRoute {
    let pointer: OpaquePointer
    let processes: [AudioObjectID]
    let output: OutputDevice
    init(pointer: OpaquePointer, processes: [AudioObjectID], output: OutputDevice) { self.pointer = pointer; self.processes = processes; self.output = output }
    deinit { MZRouteDestroy(pointer) }
}

final class MixerModel: ObservableObject {
    @Published var applications: [AudioApplication] = []
    @Published var outputs: [OutputDevice] = []
    @Published var settings: [String: AppSettings] = [:]
    @Published var errors: [String: String] = [:]
    @Published var peaks: [String: Float] = [:]
    @Published var enabled = true
    @Published var defaultOutputName = "Salida del sistema"
    @Published var defaultOutputID: AudioObjectID = 0
    @Published var outputVolumes: [String: OutputVolumeState] = [:]
    @Published var outputErrors: [String: String] = [:]
    @Published var running = Set<String>()
    private var routes: [String: LiveRoute] = [:]
    private var discoveryTimer: Timer?
    private var meterTimer: Timer?
    private var outputTimer: Timer?
    private let deviceVolume = DeviceVolumeService()
    private var observers: [NSObjectProtocol] = []
    private var asleep = false
    private var refreshing = false
    private var failedSignatures: [String: String] = [:]
    private var seen = Set<String>()

    init() {
        if let data = UserDefaults.standard.data(forKey: "applicationSettings"), let value = try? JSONDecoder().decode([String: AppSettings].self, from: data) { settings = value }
        refresh()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        outputTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshOutputVolumes() }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.peaks = self.routes.mapValues { min(1, MZRoutePeak($0.pointer)) }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.asleep = true; self?.stopRoutes() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.asleep = false; self?.failedSignatures.removeAll(); self?.refresh() })
    }
    func preference(_ id: String) -> AppSettings { settings[id] ?? AppSettings() }
    func update(_ id: String, _ change: (inout AppSettings) -> Void) {
        var value = preference(id)
        change(&value)
        value.volume = min(1, max(0, value.volume))
        settings[id] = value
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "applicationSettings") }
        failedSignatures[id] = nil
        errors[id] = nil
        reconcile()
        refreshOutputVolumes()
    }
    func toggleEnabled() {
        enabled.toggle()
        failedSignatures.removeAll()
        errors.removeAll()
        reconcile()
    }
    func stopRoutes() { routes.removeAll(); running = []; peaks = [:] }
    func shutdown() { discoveryTimer?.invalidate(); meterTimer?.invalidate(); outputTimer?.invalidate(); stopRoutes() }
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        outputs = AudioRead.outputs()
        defaultOutputID = AudioRead.defaultOutput
        defaultOutputName = outputs.first { $0.objectID == defaultOutputID }?.name ?? "Sin salida disponible"
        let discovered = AudioRead.apps()
        var aliases: [String: Set<String>] = [:]
        for app in discovered {
            for alias in app.legacyIDs { aliases[alias, default: []].insert(app.id) }
        }
        let migrated = SettingsMigration.migrate(settings, aliases: aliases)
        if migrated.keys.count != settings.keys.count {
            settings = migrated
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "applicationSettings") }
        }
        for app in discovered where app.active { seen.insert(app.id) }
        applications = discovered.filter { seen.contains($0.id) || preference($0.id).controlled }
        reconcile()
        refreshOutputVolumes()
    }
    var visibleOutputs: [OutputDevice] {
        let selected = Set(applications.compactMap { app -> String? in
            let value = preference(app.id)
            return value.controlled ? value.output : nil
        })
        return outputs.filter { $0.objectID == defaultOutputID || selected.contains($0.id) }
    }
    func refreshOutputVolumes() {
        guard !asleep else { return }
        outputVolumes = Dictionary(uniqueKeysWithValues: visibleOutputs.map { output in
            (output.id, deviceVolume.state(VolumeTarget(objectID: output.objectID, uid: output.id)))
        })
    }
    func setOutputVolume(_ output: OutputDevice, volume: Float) {
        do {
            try deviceVolume.setVolume(volume, target: VolumeTarget(objectID: output.objectID, uid: output.id))
            outputErrors[output.id] = nil
        } catch { outputErrors[output.id] = error.localizedDescription }
        refreshOutputVolumes()
    }
    func toggleOutputMute(_ output: OutputDevice) {
        let target = VolumeTarget(objectID: output.objectID, uid: output.id)
        do {
            try deviceVolume.setMuted(!(deviceVolume.state(target).muted ?? false), target: target)
            outputErrors[output.id] = nil
        } catch { outputErrors[output.id] = error.localizedDescription }
        refreshOutputVolumes()
    }
    private func reconcile() {
        guard enabled, !asleep else { stopRoutes(); return }
        let valid = Set(applications.filter { preference($0.id).controlled }.map(\.id))
        for id in Array(routes.keys) where !valid.contains(id) { routes[id] = nil }
        for app in applications {
            let preference = preference(app.id)
            guard preference.controlled else { errors[app.id] = nil; continue }
            let output = preference.output == "default" ? outputs.first { $0.objectID == AudioRead.defaultOutput } : outputs.first { $0.id == preference.output }
            guard let output else {
                routes[app.id] = nil
                errors[app.id] = "Salida desconectada. Se restauró el audio normal de la app."
                continue
            }
            let signature = "\(app.processes)-\(output.id)-\(output.objectID)-\(output.sampleRate)"
            if let route = routes[app.id], route.processes == app.processes, route.output == output {
                MZRouteSetGain(route.pointer, preference.muted ? 0 : preference.volume)
                continue
            }
            routes[app.id] = nil
            guard failedSignatures[app.id] != signature else { continue }
            // Defer initial interception until this application actually produces audio.
            guard app.active else { continue }
            var status: Int32 = 0
            let pointer = app.processes.withUnsafeBufferPointer { processes in
                output.id.withCString { uid in MZRouteCreate(processes.baseAddress, UInt32(processes.count), uid, preference.muted ? 0 : preference.volume, &status) }
            }
            if let pointer {
                routes[app.id] = LiveRoute(pointer: pointer, processes: app.processes, output: output)
                errors[app.id] = nil
            } else {
                failedSignatures[app.id] = signature
                errors[app.id] = "No se pudo activar (\(status)). Revisa el permiso de grabación de audio del sistema y pulsa Reintentar."
            }
        }
        running = Set(routes.keys)
    }
    func retry(_ id: String) { failedSignatures[id] = nil; refresh() }
    func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
}
