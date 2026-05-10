import SwiftUI

struct ActionQueueBar: View {
    @ObservedObject var aggregator: StorageAggregator
    @Binding var showDownloadList: Bool
    @Binding var showDeleteList: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 0) {
                if !aggregator.downloadQueue.isEmpty {
                    downloadRow
                }
                if !aggregator.deletionQueue.isEmpty {
                    if !aggregator.downloadQueue.isEmpty { Divider() }
                    deleteRow
                }
            }
            .background(.regularMaterial)
        }
    }

    private var downloadRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.title2).foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 1) {
                let n = aggregator.downloadQueue.count
                Text("\(n) item\(n == 1 ? "" : "s") queued to download")
                    .font(.subheadline).fontWeight(.medium)
                Text(ByteFormatter.string(from: aggregator.queuedDownloadSize))
                    .font(.caption).foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { showDownloadList = true }

            Spacer()

            Button("Clear") { aggregator.clearDownloadQueue() }
                .buttonStyle(.bordered)

            Button("Download All") {
                Task { await aggregator.executeDownloadQueue() }
            }
            .buttonStyle(.borderedProminent).tint(.blue)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private var deleteRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .font(.title2).foregroundColor(.red)

            VStack(alignment: .leading, spacing: 1) {
                let n = aggregator.deletionQueue.count
                Text("\(n) item\(n == 1 ? "" : "s") queued to delete")
                    .font(.subheadline).fontWeight(.medium)
                Text(ByteFormatter.string(from: aggregator.queuedDeleteSize))
                    .font(.caption).foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { showDeleteList = true }

            Spacer()

            Button("Clear") { aggregator.clearDeleteQueue() }
                .buttonStyle(.bordered)

            Button("Delete All") {
                Task { await aggregator.executeDeleteQueue() }
            }
            .buttonStyle(.borderedProminent).tint(.red)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }
}

// MARK: - Queue sheet

struct QueueSheet: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    let nodes: [StorageNode]
    let totalSize: Int64
    let onRemove: (StorageNode) -> Void
    let onAction: () -> Void
    let actionLabel: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2).foregroundColor(accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(ByteFormatter.string(from: totalSize))
                    .font(.subheadline).foregroundColor(.secondary)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // List
            List {
                ForEach(nodes) { node in
                    HStack(spacing: 10) {
                        Image(systemName: node.children.isEmpty ? "doc" : "folder.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name).lineLimit(1)
                            Text(node.formattedSize)
                                .font(.caption).foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            onRemove(node)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)

            Divider()

            // Footer actions
            HStack {
                Spacer()
                Button("Clear All") {
                    for node in nodes { onRemove(node) }
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(actionLabel, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
