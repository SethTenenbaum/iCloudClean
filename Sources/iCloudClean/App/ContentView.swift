import SwiftUI

struct ContentView: View {
    @StateObject private var aggregator = StorageAggregator()
    @State private var selected: StorageNode?
    @State private var drillPath: [StorageNode] = []
    @State private var previewNode: StorageNode?
    @State private var confirmDeleteFolder: StorageNode?
    @State private var groupingEnabled = false
    @State private var smallIconMode   = true
    @StateObject private var hoverState = HoverState()
    @State private var showDownloadQueue = false
    @State private var showDeleteQueue   = false
    @State private var showDiskAccessSheet = false

    var currentNodes: [StorageNode] {
        let raw = drillPath.last?.children ?? aggregator.rootNodes
        return groupingEnabled ? Self.groupSmallNodes(raw) : raw
    }

    // Nodes below 3% of the total get rolled up into a single "N smaller items" node.
    // Capped at 50 MB so top-level categories (e.g. Photos at root) are never hidden.
    private static func groupSmallNodes(_ nodes: [StorageNode]) -> [StorageNode] {
        let total = nodes.reduce(Int64(0)) { $0 + $1.totalSize() }
        guard total > 0 else { return nodes }
        let threshold = min(total / 33, 50 * 1024 * 1024)   // 3%, max 50 MB
        let visible   = nodes.filter { $0.totalSize() >= threshold }
        let small     = nodes.filter { $0.totalSize() <  threshold }
        // If ALL nodes are below threshold there's nothing to group them into — show as-is.
        // This prevents infinite recursion when drilling into a virtual group.
        guard small.count >= 2 && !visible.isEmpty else { return nodes }
        let smallSize = small.reduce(Int64(0)) { $0 + $1.totalSize() }
        let group = StorageNode(
            name: "\(small.count) smaller items",
            category: .other,
            size: smallSize,
            children: small
        )
        return visible + [group]
    }

    var body: some View {
        VStack(spacing: 0) {
            if aggregator.needsFullDiskAccess {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Disk Access required")
                            .font(.headline).foregroundColor(.white)
                        Text("iCloudClean can only see locally cached files without it. Grant access to scan your full iCloud Drive.")
                            .font(.caption).foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    Button("Open Privacy Settings") {
                        // Try the modern URL first, fall back to the legacy pref pane
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundColor(.orange)
                }
                .padding(12)
                .background(Color.orange)
            }
            StorageSummaryBar(aggregator: aggregator) { node in
                drillPath = [node]
                selected = nil
            }
            Divider()
            BreadcrumbBar(
                path: drillPath,
                hoverState: hoverState,
                onNavigate: { depth in
                    drillPath = Array(drillPath.prefix(depth))
                    selected = nil
                },
                onDeleteCurrent: drillPath.last.map { folder in
                    { confirmDeleteFolder = folder }
                }
            )

            if aggregator.isScanning {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(aggregator.scanPhase.isEmpty ? "Scanning iCloud…" : aggregator.scanPhase)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if aggregator.rootNodes.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No iCloud data found")
                        .foregroundColor(.secondary)
                    Button("Scan Again") { Task { await aggregator.scan() } }
                }
                Spacer()
            } else {
                HSplitView {
                    TreemapView(
                        nodes: currentNodes,
                        selectedId: selected?.id,
                        enforceMinSize: !smallIconMode,
                        onTap: { node in
                            // Single tap always selects — double tap drills or previews
                            selected = node
                        },
                        onDoubleTap: { node in
                            if !node.children.isEmpty {
                                drillPath.append(node)
                                selected = nil
                            } else {
                                previewNode = node
                            }
                        },
                        onHover: { hoverState.node = $0 }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    if let node = selected {
                        DetailPanel(
                            node: node,
                            isQueued: aggregator.isQueued(node),
                            isDownloadQueued: aggregator.isDownloadQueued(node),
                            onDelete: {
                                Task { await aggregator.delete(node: node) }
                                selected = nil
                            },
                            onToggleQueue: {
                                aggregator.toggleQueue(node)
                            },
                            onToggleDownloadQueue: {
                                aggregator.toggleDownloadQueue(node)
                            },
                            onDrillIn: node.children.isEmpty ? nil : {
                                drillPath.append(node)
                                selected = nil
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            }

            if !aggregator.deletionQueue.isEmpty || !aggregator.downloadQueue.isEmpty {
                ActionQueueBar(
                    aggregator: aggregator,
                    showDownloadList: $showDownloadQueue,
                    showDeleteList: $showDeleteQueue
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    groupingEnabled.toggle()
                } label: {
                    Label(
                        groupingEnabled ? "Grouping On" : "Grouping Off",
                        systemImage: groupingEnabled ? "square.stack" : "square.stack.fill"
                    )
                }
                .help(groupingEnabled ? "Small items are grouped — click to show all" : "Showing all items — click to group small ones")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    smallIconMode.toggle()
                } label: {
                    Label(
                        smallIconMode ? "Small Icons" : "Boosted Icons",
                        systemImage: smallIconMode ? "rectangle.grid.3x2" : "rectangle.grid.1x2"
                    )
                }
                .help(smallIconMode ? "True proportional sizes — click to boost small items" : "Small items boosted to minimum size — click for true proportions")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await aggregator.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(aggregator.isScanning)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showDiskAccessSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.orange)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
                .help("Full Disk Access needed to see all iCloud Drive files")
            }
        }
        .task { await aggregator.scan() }
        .sheet(isPresented: $showDownloadQueue) {
            QueueSheet(
                title: "Download Queue",
                systemImage: "icloud.and.arrow.down",
                accentColor: .blue,
                nodes: aggregator.downloadQueue,
                totalSize: aggregator.queuedDownloadSize,
                onRemove: { aggregator.toggleDownloadQueue($0) },
                onAction: {
                    Task { await aggregator.executeDownloadQueue() }
                    showDownloadQueue = false
                },
                actionLabel: "Download All"
            )
        }
        .sheet(isPresented: $showDeleteQueue) {
            QueueSheet(
                title: "Delete Queue",
                systemImage: "trash.circle.fill",
                accentColor: .red,
                nodes: aggregator.deletionQueue,
                totalSize: aggregator.queuedDeleteSize,
                onRemove: { aggregator.toggleQueue($0) },
                onAction: {
                    Task { await aggregator.executeDeleteQueue() }
                    showDeleteQueue = false
                },
                actionLabel: "Delete All"
            )
        }
        .sheet(item: $previewNode) { node in
            PreviewSheet(node: node)
        }
        .sheet(isPresented: $showDiskAccessSheet) {
            DiskAccessInstructionSheet()
        }
        .confirmationDialog(
            "Delete \"\(confirmDeleteFolder?.name ?? "")\"?",
            isPresented: Binding(
                get: { confirmDeleteFolder != nil },
                set: { if !$0 { confirmDeleteFolder = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(ByteFormatter.string(from: confirmDeleteFolder?.totalSize() ?? 0))", role: .destructive) {
                if let folder = confirmDeleteFolder {
                    confirmDeleteFolder = nil
                    // Navigate up first, then delete
                    drillPath = drillPath.filter { $0.id != folder.id }
                    selected = nil
                    Task { await aggregator.delete(node: folder) }
                }
            }
            Button("Cancel", role: .cancel) { confirmDeleteFolder = nil }
        } message: {
            Text("This will permanently delete the folder and all its contents.")
        }
    }
}

struct DiskAccessInstructionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("Full Disk Access Required")
                        .font(.title2).bold()
                    Text("Without this, iCloudClean can only see locally cached files.")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                step(n: "1", text: "Click the button below to open System Settings")
                step(n: "2", text: "In the left sidebar go to  Privacy & Security")
                step(n: "3", text: "Scroll down and click  Full Disk Access  — NOT Files & Folders")
                step(n: "4", text: "Click the  +  button, then add iCloudClean\n(or drag it from Xcode's Products folder)")
                step(n: "5", text: "Toggle iCloudClean  ON")
                step(n: "6", text: "Come back here and click  Scan Again")
            }

            Divider()

            HStack {
                Button("Open System Settings → Privacy & Security") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func step(n: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.orange)
                .clipShape(Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Isolated ObservableObject so hover changes only re-render BreadcrumbBar,/// not the entire ContentView.
final class HoverState: ObservableObject {
    @Published var node: StorageNode?
}

struct BreadcrumbBar: View {
    let path: [StorageNode]
    @ObservedObject var hoverState: HoverState
    let onNavigate: (Int) -> Void
    var onDeleteCurrent: (() -> Void)? = nil

    private var hasContent: Bool { !path.isEmpty || hoverState.node != nil }

    var body: some View {
        // Always render at a fixed height to avoid layout shifts that cause
        // the hover-bar flutter (bar appears → treemap shifts → hover lost → repeat).
        HStack(spacing: 0) {
                if !path.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Button("Home") { onNavigate(0) }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)

                            ForEach(Array(path.enumerated()), id: \.offset) { index, node in
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if index == path.count - 1 {
                                    Text(node.name)
                                        .fontWeight(.semibold)
                                } else {
                                    Button(node.name) { onNavigate(index + 1) }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                } else {
                    Spacer()
                }

                if let node = hoverState.node {
                    Divider().frame(height: 20)
                    HStack(spacing: 5) {
                        Image(systemName: node.children.isEmpty ? "doc" : "folder.fill")
                            .font(.caption2)
                        Text(node.name)
                            .lineLimit(1)
                        Text("·")
                        Text(node.formattedSize)
                        if node.isCloudOnly {
                            Image(systemName: "cloud")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }

                if let onDelete = onDeleteCurrent {
                    Divider().frame(height: 20)
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Folder", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .help("Delete \"\(path.last?.name ?? "")\" and all its contents")
                }
            }
        }
        .frame(minHeight: 28)
        .background(hasContent ? Color.secondary.opacity(0.08) : Color.clear)
        .opacity(hasContent ? 1 : 0)
        Divider()
    }
}
