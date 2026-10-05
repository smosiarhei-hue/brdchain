import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var scanner: ServerScanner
    @State private var selectedRegionID: String?
    @State private var showingCustomHost = false

    private var regions: [Region] { RegionCatalog.all }

    /// Manual choice always wins; otherwise the lowest-ping region is used.
    private var effectiveRegion: Region? {
        if let selectedRegionID,
           let match = regions.first(where: { $0.id == selectedRegionID }) {
            return match
        }
        return scanner.ranking.first?.region
    }

    var body: some View {
        NavigationStack {
            List {
                if let best = scanner.ranking.first {
                    bestSection(best)
                }

                statusSection

                regionsSection
            }
            .navigationTitle("MLBB Server Ping")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await scanner.scan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(scanner.isScanning)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCustomHost = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCustomHost) {
                CustomHostView()
            }
        }
    }

    // MARK: - Sections

    private func bestSection(_ best: (region: Region, latencyMS: Double)) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(best.region.displayName)
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.0f ms", best.latencyMS))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(color(for: best.latencyMS))
                }
                Text("Выбирай этот регион на стартовом экране MLBB: **\(best.region.inGameLabel)**")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button {
                if GameLauncher.launch() {
                    // launched
                } else if let region = effectiveRegion {
                    GameLauncher.openStore(for: region)
                }
            } label: {
                Label(GameLauncher.isInstalled() ? "Запустить MLBB" : "MLBB не найдена — открыть стор",
                      systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } header: {
            Text("Лучший вариант")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let scannedAt = scanner.scannedAt {
            Section {
                HStack {
                    Text(scanner.isScanning ? "Сканирую…" : "Просканировано")
                    Spacer()
                    Text(scannedAt, style: .time)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }
    }

    private var regionsSection: some View {
        Section {
            ForEach(regions) { region in
                row(for: region)
            }
        } header: {
            Text("Все серверы")
        } footer: {
            Text("Регион выбирается один раз при первом входе в игру. Смена возможна только сбросом данных приложения.")
        }
    }

    private func row(for region: Region) -> some View {
        let entry = scanner.ranking.first { $0.region.id == region.id }
        let isSelected = effectiveRegion?.id == region.id
        let isCustom = region.id.hasPrefix("custom-")

        return Button {
            selectedRegionID = region.id
        } label: {
            HStack(spacing: 12) {
                Text(region.flag)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(region.title)
                        .foregroundStyle(.primary)
                    Text(region.inGameLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let entry {
                    Text(String(format: "%.0f ms", entry.latencyMS))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(color(for: entry.latencyMS))
                } else if scanner.scannedAt != nil {
                    Text("нет ответа")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .swipeActions {
            if isCustom {
                Button(role: .destructive) {
                    RegionCatalog.removeCustom(id: region.id)
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Helpers

    private func color(for latency: Double) -> Color {
        switch latency {
        case ..<60:  return .green
        case ..<120: return .orange
        default:     return .red
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerScanner())
}