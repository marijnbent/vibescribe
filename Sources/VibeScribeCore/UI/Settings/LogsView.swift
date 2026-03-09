import SwiftUI

struct LogsView: View {
    @ObservedObject var viewModel: LogsViewModel

    var body: some View {
        Form {
            if viewModel.logs.isEmpty {
                Section {
                    Text("No logs yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(viewModel.logs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(MainView.formatter.string(from: entry.timestamp)) \(entry.level.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    viewModel.copyLogEntry(entry)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .help("Copy log entry")
                            }
                            Text(entry.message)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    HStack {
                        Spacer()
                        Button("Clear") {
                            viewModel.clearLogs()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
