import SwiftUI

struct MixerView: View {
    @ObservedObject var model: MixerModel
    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 10) {
                    if !model.visibleOutputs.isEmpty {
                        SectionHeading(title: "Salidas", subtitle: "Volumen del dispositivo", symbol: "hifispeaker.fill")
                            .padding(.top, 16)
                        ForEach(model.visibleOutputs) { output in OutputVolumeRow(model: model, output: output) }
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "keyboard").padding(.top, 1)
                            Text("El teclado controla General. Cada salida ajusta todas las apps que la usan.")
                                .fixedSize(horizontal: false, vertical: true)
                        }.font(.system(size: 11)).foregroundStyle(MixerTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
                    }
                    SectionHeading(title: "Aplicaciones", subtitle: "\(model.running.count) \(model.running.count == 1 ? "controlada" : "controladas")", symbol: "music.note")
                        .padding(.top, 12)
                    if model.applications.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform").font(.system(size: 30)).foregroundStyle(MixerTheme.accent)
                                .frame(width: 64, height: 64).background(MixerTheme.slate.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                            Text("Dale play a tu mezcla").font(.system(size: 16, weight: .semibold))
                            Text("Reproduce música o un video. Su aplicación aparecerá aquí para ajustar el volumen y elegir una salida.")
                                .font(.system(size: 12)).foregroundStyle(MixerTheme.secondary).multilineTextAlignment(.center).frame(maxWidth: 310)
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                    ForEach(model.applications) { app in AppRow(model: model, app: app) }
                }.padding(.horizontal, 24).padding(.bottom, 22)
            }
            footer
        }
        .frame(width: MixerTheme.width, height: MixerTheme.height)
        .foregroundStyle(MixerTheme.text)
        .background(MixerTheme.background)
        .tint(MixerTheme.accent)
        .accentColor(MixerTheme.accent)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(MixerTheme.background)
                    .frame(width: 44, height: 44).background(MixerTheme.accent, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mezcla").font(.system(size: 28, weight: .bold)).tracking(-0.8)
                    Text("Cada app, a tu volumen.").font(.system(size: 12)).foregroundStyle(MixerTheme.secondary)
                }
                Spacer()
                Text("PROTOTIPO").font(.system(size: 8, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(MixerTheme.secondary).padding(.horizontal, 9).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(MixerTheme.slate))
            }
            HStack(spacing: 10) {
                Circle().fill(model.enabled ? MixerTheme.accent : MixerTheme.secondary)
                    .frame(width: 7, height: 7).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.enabled ? "Mezcla activa" : "Control por app desactivado").font(.system(size: 12, weight: .semibold))
                    Text(model.defaultOutputName).font(.system(size: 11)).foregroundStyle(MixerTheme.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(model.enabled ? "Desactivar" : "Activar") { model.toggleEnabled() }
                    .buttonStyle(MixerButtonStyle(prominent: !model.enabled))
                    .help("Desactiva el control por aplicación. Los volúmenes de las salidas se mantienen.")
            }
        }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
            .background(MixerTheme.slate.opacity(0.16))
            .overlay(alignment: .bottom) { Rectangle().fill(MixerTheme.slate.opacity(0.7)).frame(height: 1) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lock.shield").foregroundStyle(MixerTheme.secondary)
                Text("El audio se procesa en tu Mac y no se guarda. macOS puede pedir permiso al activar una app.")
                    .fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 11)).foregroundStyle(MixerTheme.secondary)
            HStack {
                Button("Permisos de audio") { model.openPrivacy() }
                    .buttonStyle(.plain).foregroundStyle(MixerTheme.accent)
                Spacer()
                Button("Salir de Mezcla") { model.shutdown(); NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).foregroundStyle(MixerTheme.secondary)
            }.font(.system(size: 11, weight: .medium))
        }.padding(.horizontal, 24).padding(.vertical, 15)
            .background(MixerTheme.background)
            .overlay(alignment: .top) { Rectangle().fill(MixerTheme.slate.opacity(0.7)).frame(height: 1) }
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(MixerTheme.accent).accessibilityHidden(true)
            Text(title).font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(subtitle).font(.system(size: 11)).foregroundStyle(MixerTheme.secondary)
        }.padding(.bottom, 2)
    }
}

struct OutputVolumeRow: View {
    @ObservedObject var model: MixerModel
    let output: OutputDevice
    var state: OutputVolumeState { model.outputVolumes[output.id] ?? OutputVolumeState() }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "hifispeaker.fill").font(.system(size: 13)).foregroundStyle(MixerTheme.text)
                    .frame(width: 26, height: 26).background(MixerTheme.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                Text(output.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                if output.objectID == model.defaultOutputID {
                    Label("General", systemImage: "keyboard").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MixerTheme.text).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(MixerTheme.background.opacity(0.65), in: Capsule())
                }
            }
            if let volume = state.volume {
                HStack(spacing: 8) {
                    Button { model.toggleOutputMute(output) } label: {
                        Image(systemName: state.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(state.muted == true ? MixerTheme.accent : MixerTheme.text)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!state.canSetMute)
                        .opacity(state.canSetMute ? 1 : 0.45)
                        .accessibilityLabel("\(state.muted == true ? "Activar sonido de" : "Silenciar") \(output.name)")
                    Slider(value: Binding(get: { Double(model.outputVolumes[output.id]?.volume ?? volume) },
                        set: { model.setOutputVolume(output, volume: Float($0)) }), in: 0...1)
                        .disabled(!state.canSetVolume).accessibilityLabel("Volumen de salida: \(output.name)")
                    VolumeReadout(volume: volume)
                }
            }
            if !state.canSetVolume {
                Text("Ajusta el volumen en el dispositivo.").font(.system(size: 11)).foregroundStyle(MixerTheme.text)
            } else if state.muted == true {
                Label("Salida silenciada", systemImage: "speaker.slash").font(.system(size: 11)).foregroundStyle(MixerTheme.text)
            }
            if let error = model.outputErrors[output.id] {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(MixerTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).background(MixerTheme.slate, in: RoundedRectangle(cornerRadius: 15))
            .help("Afecta a todas las aplicaciones que salen por \(output.name).")
    }
}

private struct VolumeReadout: View {
    let volume: Float
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(Int((volume * 100).rounded()))").font(.system(size: 15, weight: .semibold, design: .monospaced))
            Text("%").font(.system(size: 10, weight: .medium))
        }.frame(width: 53, alignment: .trailing).foregroundStyle(MixerTheme.text)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(Int((volume * 100).rounded())) por ciento")
    }
}

struct AppRow: View {
    @ObservedObject var model: MixerModel
    let app: AudioApplication
    var preference: AppSettings { model.preference(app.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Group {
                    if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 32, height: 32) }
                    else { Image(systemName: "app.fill").font(.system(size: 27)).foregroundStyle(MixerTheme.secondary) }
                }.frame(width: 38, height: 38).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(app.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let detail = app.detail {
                            Text("· \(detail)").font(.system(size: 10)).foregroundStyle(MixerTheme.secondary).lineLimit(1)
                        }
                    }
                    HStack(spacing: 5) {
                        if model.errors[app.id] != nil {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(MixerTheme.accent)
                        } else if model.running.contains(app.id) && model.enabled {
                            Circle().fill(preference.muted ? MixerTheme.secondary : MixerTheme.accent).frame(width: 5, height: 5)
                        }
                        Text(status)
                    }.font(.system(size: 11)).foregroundStyle(MixerTheme.secondary)
                }
                Spacer(minLength: 8)
                Toggle("Controlar \(app.name)", isOn: Binding(get: { preference.controlled }, set: { value in model.update(app.id) { $0.controlled = value } }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if preference.controlled {
                Rectangle().fill(MixerTheme.slate.opacity(0.7)).frame(height: 1)
                HStack(spacing: 8) {
                    Button { model.update(app.id) { $0.muted.toggle() } } label: {
                        Image(systemName: preference.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(preference.muted ? MixerTheme.accent : MixerTheme.secondary)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(preference.muted ? "Activar sonido" : "Silenciar")
                        .accessibilityLabel("\(preference.muted ? "Activar sonido de" : "Silenciar") \(app.name)")
                    Slider(value: Binding(get: { Double(preference.volume) }, set: { value in model.update(app.id) { $0.volume = Float(value) } }), in: 0...1)
                        .accessibilityLabel("Volumen de \(app.name)")
                        .help("Volumen de la app, independiente del volumen de la salida.")
                    VolumeReadout(volume: preference.volume)
                }
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward").font(.system(size: 11, weight: .semibold)).foregroundStyle(MixerTheme.accent).frame(width: 30)
                        .accessibilityHidden(true)
                    Picker("Salida de \(app.name)", selection: Binding(get: { preference.output }, set: { value in model.update(app.id) { $0.output = value } })) {
                        Text("Salida del sistema").tag("default")
                        ForEach(model.outputs) { output in Text(output.name).tag(output.id) }
                        if preference.output != "default", !model.outputs.contains(where: { $0.id == preference.output }) { Text("Salida desconectada").tag(preference.output) }
                    }.labelsHidden().controlSize(.small)
                }
                GeometryReader { geometry in
                    Capsule().fill(MixerTheme.slate).overlay(alignment: .leading) {
                        Capsule().fill(MixerTheme.accent).frame(width: geometry.size.width * CGFloat(preference.muted ? 0 : (model.peaks[app.id] ?? 0) * preference.volume))
                    }
                }.frame(height: 3).accessibilityHidden(true)
                if let error = model.errors[app.id] {
                    Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(MixerTheme.accent).fixedSize(horizontal: false, vertical: true)
                    Button("Reintentar") { model.retry(app.id) }.buttonStyle(MixerButtonStyle())
                }
            }
        }
        .padding(16)
        .background(MixerTheme.slate.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MixerTheme.slate.opacity(preference.controlled ? 1 : 0.55)))
    }
    var status: String {
        if !model.enabled { return "Audio original" }
        if model.errors[app.id] != nil { return "Requiere atención" }
        if preference.controlled && preference.muted { return "Silenciada" }
        if model.running.contains(app.id) { return app.active ? "En reproducción" : "Esperando audio" }
        if preference.controlled { return "Esperando reproducción" }
        return app.active ? "Reproduciendo · sin ajustar" : "En pausa"
    }
}
