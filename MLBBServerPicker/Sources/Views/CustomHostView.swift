import SwiftUI

struct CustomHostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scanner: ServerScanner

    @State private var title = ""
    @State private var flag = ""
    @State private var host = ""
    @State private var port = "443"
    @State private var probeResult: String?

    private var hostValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !host.contains(" ")
    }

    private var portValue: UInt16? { UInt16(port) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Мой сервер", text: $title)
                    TextField("Флаг (необязательно)", text: $flag)
                }

                Section {
                    TextField("gateway.example.com", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Порт", text: $port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Хост и порт")
                } footer: {
                    Text("Реальный гейтвей можно узнать только из трафика на устройстве. Скопируй его сюда и проверь пинг.")
                }

                if let probeResult {
                    Section("Проверка") {
                        Text(probeResult).font(.callout)
                    }
                }

                Section {
                    Button("Проверить пинг") {
                        Task { await probe() }
                    }
                    .disabled(!hostValid || portValue == nil)

                    Button("Сохранить сервер") {
                        RegionCatalog.addCustom(title: title.isEmpty ? host : title,
                                                flag: flag,
                                                host: host.trimmingCharacters(in: .whitespaces))
                        Task { await scanner.scan() }
                        dismiss()
                    }
                    .disabled(!hostValid)
                }
            }
            .navigationTitle("Свой сервер")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func probe() async {
        guard let portValue else { return }
        probeResult = "Проверяю…"
        let measurement = await PingService.measure(
            host: host.trimmingCharacters(in: .whitespaces),
            port: portValue
        )
        probeResult = measurement.summary
    }
}

#Preview {
    CustomHostView()
        .environmentObject(ServerScanner())
}