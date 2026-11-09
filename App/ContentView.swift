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
        .alert("Errore", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Ripristina configurazione", isPresented: $model.showRestoreDialog, titleVisibility: .visible) {
            ForEach(RestoreFrequency.allCases) { frequency in
                Button("Rimuovi scheduler e imposta TM su «\(frequency.label)»") {
                    model.restore(frequency: frequency)
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Lo scheduler e il suo log verranno rimossi. Time Machine tornerà alla frequenza scelta.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time Machine Scheduler")
                    .font(.title2.bold())
                Text(model.installed ? "Daemon installato" : "Daemon non installato")
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
                Text("Time Machine ha una frequenza automatica attiva (\(model.tmFrequencyText)).")
                    .font(.callout)
                Text("Apri Impostazioni e scegli «Manualmente» per evitare backup doppi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apri Impostazioni Time Machine") {
                model.openTimeMachineSettings()
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Pianificazione attiva", isOn: $model.config.enabled)
                .toggleStyle(.switch)

            HStack {
                Text("Ora di avvio")
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
            Text("Opzioni")
                .font(.headline)
            Toggle("Avvia solo se la destinazione è raggiungibile", isOn: $model.config.requireDestination)
            Toggle("Impedisci il sonno durante il backup", isOn: $model.config.preventSleep)
            Toggle("Salta se il Mac è a batteria", isOn: $model.config.skipOnBattery)
            Toggle("Notifica a fine backup", isOn: $model.config.notify)
        }
    }

    private var statusSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            statusRow("Ultimo backup", model.lastRunText)
            statusRow("Prossimo backup", model.nextRunText)
            statusRow("Destinazione Time Machine", model.destinationText)
            statusRow("Stato Time Machine", model.tmStatusText)
            statusRow("Frequenza Time Machine", model.tmFrequencyText)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.logLines.isEmpty {
                        Text("Nessun evento")
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
            Button("Backup ora") { model.backupNow() }
                .disabled(model.tmStatus.running || model.busy)
            Button("Apri log") { model.openLog() }
            Spacer()
            Button("Ripristina…") { model.showRestoreDialog = true }
                .disabled(model.busy)
            Button("Salva pianificazione") { model.apply() }
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

    private func statusRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
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
