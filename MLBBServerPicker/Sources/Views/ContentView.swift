import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var scanner: ServerScanner
    @State private var showingImporter = false
    @State private var showingHelp = false

    private var reachable: [HostResult] { scanner.sortedResults().filter(\.reachable) }
    private var unreachable: [HostResult] { scanner.sortedResults().filter { !$0.reachable } }

    var body: some View {
        NavigationStack {
            List {
                verdictSection
                if !reachable.isEmpty { reachableSection }
                if !unreachable.isEmpty { unreachableSection }
                actionsSection
            }
            .navigationTitle("MLBB Server Picker")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await scanner.scan() }
                    } label: {
                        if scanner.isScanning {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(scanner.isScanning)
                }
            }
            .sheet(isPresented: $showingImporter) { HostImporterView() }
            .sheet(isPresented: $showingHelp) { HowItWorksView() }
            .task {
                if scanner.results.isEmpty {
                    await scanner.scan()
                }
            }
        }
    }

    // MARK: - Verdict

    private var verdictSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if scanner.isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Проверяю хосты…")
                    }
                    .font(.headline)
                } else {
                    Text(scanner.verdict.headline)
                        .font(.headline)
                        .foregroundStyle(verdictColor)
                }

                Text(scanner.verdict.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if bestReachable != nil {
                Button {
                    GameLauncher.launch()
                } label: {
                    Label("Запустить MLBB", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var bestReachable: HostResult? {
        scanner.sortedResults().first { $0.reachable && $0.host.origin == .verified }
    }

    private var verdictColor: Color {
        switch scanner.verdict {
        case .verifiedHostReachable: return .green
        case .noVerifiedHosts, .nothingResponded: return .orange
        }
    }

    // MARK: - Lists

    private var reachableSection: some View {
        Section("Отвечают") {
            ForEach(reachable) { result in
                HostRow(result: result)
            }
        }
    }

    private var unreachableSection: some View {
        Section {
            ForEach(unreachable) { result in
                HostRow(result: result)
            }
        } header: {
            Text("Не отвечают (\(unreachable.count))")
        } footer: {
            Text("Это нормально. Встроенные адреса — заглушки; настоящие гейтвеи надо взять из сетевого лога MLBB.")
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                showingImporter = true
            } label: {
                Label("Импортировать хосты из логов", systemImage: "square.and.arrow.down")
            }

            if !HostStore.imported.isEmpty {
                Button(role: .destructive) {
                    HostStore.removeAll()
                    Task { await scanner.scan() }
                } label: {
                    Label("Удалить импортированные (\(HostStore.imported.count))", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Row

private struct HostRow: View {
    let result: HostResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.reachable ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(result.reachable ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.host.host)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(result.host.origin.label)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())

                    if let region = result.host.regionHint {
                        Text(region)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let note = result.host.note, result.host.regionHint == nil {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            if let latency = result.latencyMS {
                Text(String(format: "%.0f ms", latency))
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(latencyColor(latency))
            } else {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func latencyColor(_ value: Double) -> Color {
        switch value {
        case ..<60:  return .green
        case ..<120: return .orange
        default:     return .red
        }
    }
}

#Preview {
    ContentView().environmentObject(ServerScanner())
}