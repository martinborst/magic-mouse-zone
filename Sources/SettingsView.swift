import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: ScrollEngine

    var body: some View {
        Form {
            permissionSection
            filterSection
            mouseSection
            presetsSection
            sizeSection
            loginSection
            statusSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 480, minHeight: 720)
        .onChange(of: engine.enabled) { _, _ in
            engine.applyZoneToFilter()
        }
        .onChange(of: engine.ignoreMultipleFingers) { _, _ in
            engine.applyZoneToFilter()
        }
        .onChange(of: engine.zone) { _, _ in
            engine.applyZoneToFilter()
        }
    }

    private var permissionSection: some View {
        Section {
            if engine.accessibilityGranted {
                Label("Accessibility access is on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Accessibility access is required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Turn on Magic Mouse Zone in System Settings → Privacy & Security → Accessibility. If the switch is already on, macOS is still tied to an old copy of the app — remove it, add this exact copy, then quit and reopen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Bundle.main.bundlePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack {
                        Button("Open Accessibility Settings") {
                            engine.requestAccess()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Reveal in Finder") {
                            engine.revealAppInFinder()
                        }
                    }
                    Button("Quit & Reopen") {
                        engine.relaunch()
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var filterSection: some View {
        Section {
            Toggle("Limit scrolling to a zone", isOn: $engine.enabled)
            Toggle("Ignore scrolling with multiple fingers", isOn: $engine.ignoreMultipleFingers)
            Picker("Handed", selection: $engine.handedness) {
                Text("Right").tag(Handedness.right)
                Text("Left").tag(Handedness.left)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Clicks still work on the whole mouse. Resting fingers outside the zone are ignored. Two-finger swipes are ignored even if one finger is in the zone.")
        }
    }

    private var mouseSection: some View {
        Section("Active scroll area") {
            HStack {
                Spacer()
                MouseSurfaceView(
                    zone: $engine.zone,
                    fingers: engine.fingers,
                    handedness: engine.handedness
                )
                .padding(.vertical, 8)
                Spacer()
            }
            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("In zone — can scroll")
                Spacer()
                Circle().fill(.orange).frame(width: 8, height: 8)
                Text("Outside — ignored")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var presetsSection: some View {
        Section("Presets") {
            HStack {
                Button("Middle finger") {
                    engine.zone = .middleFinger
                }
                Button("Narrow") {
                    engine.zone = .narrowCenter
                }
                Button("Whole mouse") {
                    engine.zone = .fullSurface
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var sizeSection: some View {
        Section {
            HStack {
                Text("Width")
                Slider(
                    value: Binding(
                        get: { engine.zone.width },
                        set: { engine.zone = engine.zone.settingWidth($0) }
                    ),
                    in: 0.12...0.9
                )
                Text("\(Int(engine.zone.width * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Position")
                Slider(
                    value: Binding(
                        get: { engine.zone.centerX },
                        set: { engine.zone = engine.zone.settingCenterX($0) }
                    ),
                    in: 0.08...0.92
                )
                Text(engine.zone.centerX < 0.45 ? "Left" : engine.zone.centerX > 0.55 ? "Right" : "Center")
                    .frame(width: 52, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Keep a narrow strip in the center if you scroll with your middle finger and rest your ring finger and pinky on the right side.")
        }
    }

    private var loginSection: some View {
        Section {
            Toggle("Open at login", isOn: Binding(
                get: { engine.launchAtLogin },
                set: { engine.setLaunchAtLogin($0) }
            ))
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Magic Mouse") {
                Text(engine.mouseConnected ? "Connected" : "Not found")
                    .foregroundStyle(engine.mouseConnected ? .green : .secondary)
            }
            LabeledContent("Scroll filter") {
                Text(filterStatus)
                    .foregroundStyle(engine.tapRunning && (engine.enabled || engine.ignoreMultipleFingers) ? .green : .secondary)
            }
            Text(engine.deviceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var filterStatus: String {
        if !engine.accessibilityGranted { return "Needs Accessibility" }
        if !engine.tapRunning { return "Not running" }
        if engine.enabled || engine.ignoreMultipleFingers { return "On" }
        return "Paused"
    }
}
