import Combine
import SwiftUI

struct ContentView: View {
    @ObservedObject private var model = SchedulerModel.shared

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.tmAutoBackup {
                banner
            }

            scheduleSection
            optionsSection

            Divider()
            statusSection

            Divider()
            logSection

            actionBar
        }
        .padding(20)
        .frame(width: 600)
        .onReceive(timer) { _ in model.refresh() }
        .alert("error.title", isPresented: errorBinding) {
            Button("error.ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("restore.title", isPresented: $model.showRestoreDialog, titleVisibility: .visible) {
            ForEach(RestoreFrequency.allCases) { frequency in
                Button(L("restore.option", frequency.label)) {
                    model.restore(frequency: frequency)
                }
            }
            Button("restore.cancel", role: .cancel) {}
        } message: {
            Text("restore.message")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time Machine Scheduler")
                    .font(.title2.bold())
                Text(model.installed ? L("app.subtitle.installed") : L("app.subtitle.notInstalled"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("banner.title", model.tmFrequencyText))
                    .font(.callout)
                Text("banner.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("banner.button") {
                model.openTimeMachineSettings()
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("schedule.enabled", isOn: $model.config.enabled)
                .toggleStyle(.switch)

            HStack {
                Text("schedule.time")
                Spacer()
                DatePicker("", selection: hourBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 100)
            }

            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { iso in
                    Toggle(ScheduleLogic.weekdayNames[iso - 1], isOn: dayBinding(iso))
                        .toggleStyle(.checkbox)
                }
            }
            .disabled(!model.config.enabled)
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("options.title")
                .font(.headline)
            Toggle("options.requireDestination", isOn: $model.config.requireDestination)
            Toggle("options.preventSleep", isOn: $model.config.preventSleep)
            Toggle("options.keepAwake", isOn: $model.config.keepAwake)
            Toggle("options.limitedBackup", isOn: $model.config.limitedBackup)
            Toggle("options.skipOnBattery", isOn: $model.config.skipOnBattery)
            Toggle("options.notify", isOn: $model.config.notify)
        }
    }

    private var statusSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            statusRow("status.lastBackup", model.lastRunText)
            statusRow("status.nextBackup", model.nextRunText)
            statusRow("status.destination", model.destinationText)
            statusRow("status.tmStatus", model.tmStatusText)
            statusRow("status.frequency", model.tmFrequencyText)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("log.title")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.logLines.isEmpty {
                        Text("log.empty")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(logColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var actionBar: some View {
        HStack {
            Button("button.backupNow") { model.backupNow() }
                .disabled(model.tmStatus.running || model.busy)
            Button("button.openLog") { model.openLog() }
            Spacer()
            Button("button.restore") { model.showRestoreDialog = true }
                .disabled(model.busy)
            Button("button.save") { model.apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var hourBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: model.config.hour,
                    minute: model.config.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.config.hour = components.hour ?? model.config.hour
                model.config.minute = components.minute ?? model.config.minute
            }
        )
    }

    private func dayBinding(_ iso: Int) -> Binding<Bool> {
        Binding(
            get: { model.config.weekdays.contains(iso) },
            set: { enabled in
                if enabled {
                    if !model.config.weekdays.contains(iso) {
                        model.config.weekdays.append(iso)
                        model.config.weekdays.sort()
                    }
                } else {
                    model.config.weekdays.removeAll { $0 == iso }
                }
            }
        )
    }

    private func statusRow(_ labelKey: String, _ value: String) -> some View {
        GridRow {
            Text(L(labelKey))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
        }
    }

    private func logColor(_ line: String) -> Color {
        if line.contains("end: success") { return .green }
        if line.contains("end: failed") { return .red }
        if line.contains("skip:") { return .orange }
        return .primary
    }
}
