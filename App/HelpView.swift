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
                        Text("help.subtitle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                section("help.schedule.title", [
                    "help.schedule.1",
                    "help.schedule.2",
                ])

                section("help.options.title", [
                    "help.options.1",
                    "help.options.2",
                    "help.options.3",
                    "help.options.4",
                    "help.options.5",
                    "help.options.6",
                ])

                section("help.backup.title", [
                    "help.backup.1",
                    "help.backup.2",
                ])

                section("help.restore.title", [
                    "help.restore.1",
                ])

                section("help.limits.title", [
                    "help.limits.1",
                    "help.limits.2",
                    "help.limits.3",
                    "help.limits.4",
                    "help.limits.5",
                ])

                Divider()

                Link("help.github", destination: ProjectLinks.repository)
                    .font(.callout)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(width: 620, height: 560)
    }

    private func section(_ title: LocalizedStringKey, _ items: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(items[index])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
