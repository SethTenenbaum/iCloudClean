import SwiftUI

struct DetailPanel: View {
    let node: StorageNode
    let isQueued: Bool
    let isDownloadQueued: Bool
    let onDelete: () -> Void
    let onToggleQueue: () -> Void
    let onToggleDownloadQueue: () -> Void
    var onDrillIn: (() -> Void)? = nil   // non-nil only for folder nodes

    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: node.children.isEmpty ? "doc" : "folder.fill")
                    .foregroundColor(node.children.isEmpty ? .secondary : .accentColor)
                Text(node.name)
                    .font(.headline)
                    .lineLimit(2)
            }

            Divider()

            row(label: "Size", value: node.formattedSize)
            if !node.children.isEmpty {
                row(label: "Items", value: "\(node.children.count)")
            }
            row(label: "Category", value: node.category.rawValue)
            if node.children.isEmpty {
                row(label: "Status", value: node.isCloudOnly ? "Cloud only" : "Downloaded")
            }
            if let url = node.url {
                row(label: "Path", value: url.path)
            }

            Spacer()

            // Open folder button
            if let drill = onDrillIn {
                Button(action: drill) {
                    Label("Open Folder", systemImage: "folder.badge.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            // Show download for cloud-only files (any category) and all folders
            if node.isCloudOnly || !node.isLeaf {
                Button {
                    onToggleDownloadQueue()
                } label: {
                    Label(
                        isDownloadQueued ? "Remove from Downloads" : "Queue for Download",
                        systemImage: isDownloadQueued ? "minus.circle" : "icloud.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isDownloadQueued ? .secondary : .blue)
            }

            Button {
                onToggleQueue()
            } label: {
                Label(
                    isQueued ? "Remove from Queue" : "Queue for Deletion",
                    systemImage: isQueued ? "minus.circle" : "trash.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isQueued ? .secondary : .orange)

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Now", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .confirmationDialog(
                "Delete \"\(node.name)\"?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete \(node.formattedSize)", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
        .padding()
        .frame(minWidth: 220, maxWidth: 260)
    }

    private func row(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(3)
        }
    }
}
