import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var statusMessage = ""
    @State private var dbDate: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Datenbank") {
                    if !dbDate.isEmpty {
                        HStack {
                            Text("Stand")
                            Spacer()
                            Text(dbDate)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        downloadDatabase()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Interaktions-DB aktualisieren")
                        }
                    }
                    .disabled(isDownloading)

                    if isDownloading {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: downloadProgress)
                            Text("Herunterladen...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(statusMessage.contains("Fehler") ? .red : .green)
                    }
                }

                Section("Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Quelle")
                        Spacer()
                        Text("pillbox.oddb.org")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear { loadDbDate() }
        }
    }

    private func loadDbDate() {
        let path = DatabaseManager.documentsDbPath
        if FileManager.default.fileExists(atPath: path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attrs[.modificationDate] as? Date {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            fmt.locale = Locale(identifier: "de_CH")
            dbDate = fmt.string(from: date)
        } else if Bundle.main.path(forResource: "interactions", ofType: "db") != nil {
            dbDate = "Mitgeliefert"
        }
    }

    private func downloadDatabase() {
        isDownloading = true
        downloadProgress = 0
        statusMessage = ""

        guard let url = URL(string: "http://pillbox.oddb.org/interactions.db") else {
            statusMessage = "Fehler: Ungültige URL"
            isDownloading = false
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            DispatchQueue.main.async {
                isDownloading = false

                if let error = error {
                    statusMessage = "Fehler: \(error.localizedDescription)"
                    return
                }

                guard let tempURL = tempURL else {
                    statusMessage = "Fehler: Keine Daten erhalten"
                    return
                }

                let destURL = URL(fileURLWithPath: DatabaseManager.documentsDbPath)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    DatabaseManager.shared.reloadDatabase()
                    statusMessage = "Erfolgreich aktualisiert"
                    loadDbDate()
                } catch {
                    statusMessage = "Fehler: \(error.localizedDescription)"
                }
            }
        }
        task.resume()
    }
}
