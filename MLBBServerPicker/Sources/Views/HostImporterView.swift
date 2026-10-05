import SwiftUI

/// Paste-in for hosts pulled out of MLBB's network log.
///
/// Accepts anything host-shaped: one per line, comma or space separated, with
/// or without a scheme or port. Every entry is normalised before it is stored.
struct HostImporterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scanner: ServerScanner

    @State private var input = ""
    @State private var regionHint = ""
    @State private var result: String?

    private var parsedCount: Int {
        let tokens = input
            .components(separatedBy: CharacterSet(charactersIn: " \n\t,;"))
            .filter { $0.contains(".") }
        return Set(tokens).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $input)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Хосты из лога")
                } footer: {
                    Text("По одному на строку. Можно с портом (host:port) и с https:// — лишнее отбросится.")
                }

                Section("Регион") {
                    TextField("например Singapore", text: $regionHint)
                }

                if let result {
                    Section {
                        Text(result).font(.callout)
                    }
                }

                Section {
                    Button("Импортировать и просканировать") {
                        Task { await importAndScan() }
                    }
                    .disabled(parsedCount == 0)

                    if !HostStore.imported.isEmpty {
                        Button("Очистить всё импортированное", role: .destructive) {
                            HostStore.removeAll()
                            result = "Список очищен."
                        }
                    }
                }
            }
            .navigationTitle("Импорт хостов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func importAndScan() async {
        let tokens = input
            .components(separatedBy: CharacterSet(charactersIn: " \n\t,;"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let added = HostStore.merge(tokens)

        if !regionHint.isEmpty {
            for host in HostStore.imported where host.regionHint == nil {
                HostStore.setRegionHint(regionHint, for: host.id)
            }
        }

        result = added == 0
            ? "Новых хостов не добавилось — все уже были в списке."
            : "Добавлено \(added). Измеряю…"

        await scanner.scan()
        result = "Добавлено \(added). Отвечающих: \(scanner.sortedResults().filter(\.reachable).count)."
        dismiss()
    }
}

#Preview {
    HostImporterView().environmentObject(ServerScanner())
}