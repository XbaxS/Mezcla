import SwiftUI

struct MixerView: View {
    @ObservedObject var model: MixerModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "slider.vertical.3").font(.system(size: 24, weight: .semibold)).foregroundStyle(.mint)
                    .frame(width: 48, height: 48).background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mezcla").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Cada app, a tu volumen.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("PROTOTIPO").font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(.secondary)
            }.padding(22)
            HStack(spacing: 10) {
                Image(systemName: model.enabled ? "waveform" : "pause.circle").foregroundStyle(model.enabled ? .mint : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.enabled ? "Mezclador disponible" : "Control por app desactivado").font(.system(size: 12, weight: .semibold))
                    Text(model.defaultOutputName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button(model.enabled ? "Desactivar" : "Activar") { model.toggleEnabled() }.controlSize(.small)
                    .help("Desactiva el control por aplicación. Los volúmenes de las salidas se mantienen.")
            }.padding(13).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 22)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if !model.visibleOutputs.isEmpty {
                        HStack {
                            Text("SALIDAS").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                            Spacer()
                            Text("Volumen del dispositivo").font(.system(size: 10))
                        }.foregroundStyle(.secondary).padding(.top, 20).padding(.bottom, 2)
                        ForEach(model.visibleOutputs) { output in OutputVolumeRow(model: model, output: output) }
                        Text("El teclado ajusta la salida marcada como General. Cada volumen de salida afecta a todas las apps que usan ese dispositivo.")
                            .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text("MÚSICA Y AUDIO").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                        Spacer()
                        Text("\(model.running.count) \(model.running.count == 1 ? "controlada" : "controladas")").font(.system(size: 11))
                    }.foregroundStyle(.secondary).padding(.top, 13).padding(.bottom, 2)
                    if model.applications.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list").font(.system(size: 32)).foregroundStyle(.secondary)
                            Text("Reproduce algo para empezar").font(.system(size: 15, weight: .semibold))
                            Text("Abre música o un video. Su aplicación aparecerá aquí para que elijas el volumen y la salida.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(model.applications) { app in AppRow(model: model, app: app) }
                }.padding(.horizontal, 22).padding(.bottom, 16)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Activa el control en cada app. macOS puede pedir permiso para capturar su audio; Mezcla lo procesa en tu Mac y no lo guarda.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Permisos de audio") { model.openPrivacy() }.buttonStyle(.link).font(.system(size: 11))
                    Spacer()
                    Button("Salir de Mezcla") { model.shutdown(); NSApplication.shared.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 22).padding(.vertical, 15).background(.primary.opacity(0.025))
        }
        .frame(width: 440, height: 700)
        .background(.background)
        .tint(.mint)
    }
}

struct OutputVolumeRow: View {
    @ObservedObject var model: MixerModel
    let output: OutputDevice
    var state: OutputVolumeState { model.outputVolumes[output.id] ?? OutputVolumeState() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.fill").foregroundStyle(.secondary)
                Text(output.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Spacer()
                if output.objectID == model.defaultOutputID {
                    Text("General").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(.primary.opacity(0.05), in: Capsule())
                }
            }
            if let volume = state.volume {
                HStack(spacing: 9) {
                    Button { model.toggleOutputMute(output) } label: {
                        Image(systemName: state.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(state.muted == true ? .orange : .secondary).frame(width: 22)
                    }.buttonStyle(.plain).disabled(!state.canSetMute)
                        .accessibilityLabel("\(state.muted == true ? "Activar" : "Silenciar") \(output.name)")
                    Slider(value: Binding(get: { Double(model.outputVolumes[output.id]?.volume ?? volume) },
                        set: { model.setOutputVolume(output, volume: Float($0)) }), in: 0...1)
                        .disabled(!state.canSetVolume).accessibilityLabel("Volumen de salida: \(output.name)")
                    Text("\(Int((volume * 100).rounded())) %").font(.system(size: 11, design: .monospaced)).frame(width: 43, alignment: .trailing)
                }
            }
            if !state.canSetVolume {
                Text("Ajusta el volumen en el dispositivo.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else if state.muted == true {
                Text("Salida silenciada").font(.system(size: 10)).foregroundStyle(.orange)
            }
            if let error = model.outputErrors[output.id] {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).background(.mint.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .help("Afecta a todas las aplicaciones que salen por \(output.name).")
    }
}

struct AppRow: View {
    @ObservedObject var model: MixerModel
    let app: AudioApplication
    var preference: AppSettings { model.preference(app.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 30, height: 30) }
                else { Image(systemName: "app.fill").font(.system(size: 26)).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let detail = app.detail {
                        Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text(status).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Controlar \(app.name)", isOn: Binding(get: { preference.controlled }, set: { value in model.update(app.id) { $0.controlled = value } }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            if preference.controlled {
                Text("Volumen de la app").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { model.update(app.id) { $0.muted.toggle() } } label: {
                        Image(systemName: preference.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(preference.muted ? .orange : .secondary).frame(width: 22)
                    }.buttonStyle(.plain).help(preference.muted ? "Activar sonido" : "Silenciar")
                    Slider(value: Binding(get: { Double(preference.volume) }, set: { value in model.update(app.id) { $0.volume = Float(value) } }), in: 0...1)
                        .accessibilityLabel("Volumen de \(app.name)")
                    Text("\(Int((preference.volume * 100).rounded())) %").font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 43, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Image(systemName: "hifispeaker").font(.system(size: 12)).foregroundStyle(.secondary)
                    Picker("Salida", selection: Binding(get: { preference.output }, set: { value in model.update(app.id) { $0.output = value } })) {
                        Text("Salida del sistema").tag("default")
                        ForEach(model.outputs) { output in Text(output.name).tag(output.id) }
                        if preference.output != "default", !model.outputs.contains(where: { $0.id == preference.output }) { Text("Salida desconectada").tag(preference.output) }
                    }.labelsHidden().controlSize(.small)
                }
                GeometryReader { geometry in
                    Capsule().fill(.primary.opacity(0.05)).overlay(alignment: .leading) {
                        Capsule().fill(.mint.opacity(0.65)).frame(width: geometry.size.width * CGFloat(preference.muted ? 0 : (model.peaks[app.id] ?? 0) * preference.volume))
                    }
                }.frame(height: 3).accessibilityHidden(true)
                if let error = model.errors[app.id] {
                    Text(error).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Reintentar") { model.retry(app.id) }.controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.045)))
    }
    var status: String {
        if !model.enabled { return "Audio original" }
        if model.errors[app.id] != nil { return "Requiere atención" }
        if model.running.contains(app.id) { return app.active ? "Control de audio activo" : "Esperando audio" }
        if preference.controlled { return "Esperando reproducción" }
        return app.active ? "Reproduciendo · sin ajustar" : "En pausa"
    }
}
