import SwiftUI

struct StorageBar: View {
    let nodes: [StorageNode]
    let total: Int64
    var onSelect: ((StorageNode) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(nodes) { node in
                    let fraction = total > 0 ? CGFloat(node.totalSize()) / CGFloat(total) : 0
                    Color(hex: node.category.color)
                        .frame(width: max(geo.size.width * fraction, 0))
                        .onTapGesture { onSelect?(node) }
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
    }
}

struct StorageSummaryBar: View {
    @ObservedObject var aggregator: StorageAggregator
    var onSelect: ((StorageNode) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("iCloud Storage")
                    .font(.headline)
                Spacer()
                Text(ByteFormatter.string(from: aggregator.totalSize))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            StorageBar(nodes: aggregator.rootNodes, total: aggregator.totalSize, onSelect: onSelect)

            HStack(spacing: 12) {
                ForEach(aggregator.rootNodes) { node in
                    Button {
                        onSelect?(node)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: node.category.color))
                                .frame(width: 9, height: 9)
                            Text(node.category.rawValue)
                                .font(.caption).fontWeight(.medium)
                            Text(node.formattedSize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: node.category.color).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}

// MARK: - Cursor modifier (macOS only)

extension View {
    @ViewBuilder
    func cursor(_ cursor: NSCursor) -> some View {
        #if os(macOS)
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
        #else
        self
        #endif
    }
}
