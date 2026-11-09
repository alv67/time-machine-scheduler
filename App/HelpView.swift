import AppKit
import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(nsImage: AppIcon.image)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time Machine Scheduler")
                            .font(.title2.bold())
                        Text("Pianificazione dei backup di Time Machine")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                section("Pianificazione", [
                    "Scegli l'ora di avvio e i giorni, poi premi «Salva pianificazione». L'installazione del daemon richiede la password di amministratore.",
                    "Se Time Machine ha una frequenza automatica attiva, il banner in alto apre le Impostazioni di Sistema: scegli «Manualmente» per evitare backup doppi.",
                ])

                section("Opzioni", [
                    "«Avvia solo se la destinazione è raggiungibile» controlla l'host della destinazione configurata in Time Machine (letta da tmutil), non un indirizzo fisso.",
                    "«Impedisci il sonno» usa caffeinate -i durante il backup.",
                    "«Salta se il Mac è a batteria» evita il backup quando il Mac non è collegato alla corrente.",
                    "«Notifica a fine backup» mostra una notifica di sistema.",
                ])

                section("Backup e log", [
                    "«Backup ora» avvia subito un backup fuori pianificazione.",
                    "Il log mostra gli ultimi 200 eventi e ruota automaticamente a 1 MB (3 file).",
                ])

                section("Ripristino", [
                    "«Ripristina…» rimuove daemon, script e log e riporta Time Machine alla frequenza scelta. Se macOS non applica la modifica, l'app apre le Impostazioni e lo segnala.",
                ])

                section("Limiti", [
                    "Un Mac spento non può essere acceso da nessuna pianificazione (Apple Silicon).",
                    "caffeinate non impedisce il sonno con il coperchio chiuso.",
                    "La finestra dell'app può essere chiusa: il daemon continua a funzionare.",
                ])

                Divider()

                Link("Pagina GitHub del progetto", destination: ProjectLinks.repository)
                    .font(.callout)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(width: 620, height: 560)
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
