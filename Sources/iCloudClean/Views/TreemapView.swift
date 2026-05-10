import SwiftUI

struct TreemapRect: Identifiable {
    let id   = UUID()
    let node: StorageNode
    let rect: CGRect
}

// MARK: - View

struct TreemapView: View {
    let nodes:           [StorageNode]
    var selectedId:      UUID?
    var enforceMinSize:  Bool = true
    var onTap:           (StorageNode) -> Void
    var onDoubleTap:     ((StorageNode) -> Void)? = nil
    var onHover:         ((StorageNode?) -> Void)? = nil

    @State private var infoNode: StorageNode?

    var body: some View {
        GeometryReader { geo in
            let sorted = nodes
                .filter { $0.totalSize() > 0 }
                .sorted { $0.totalSize() > $1.totalSize() }

            let realTotal   = sorted.reduce(Int64(0)) { $0 + $1.totalSize() }
            let layoutSizes = makeLayoutSizes(sorted: sorted, realTotal: realTotal)

            let rects = squarify(
                nodes: sorted,
                sizes: layoutSizes,
                rect: CGRect(origin: .zero, size: geo.size)
            )

            Canvas { ctx, _ in
                for item in rects {
                    let fill = item.rect.insetBy(dx: 1, dy: 1)
                    guard fill.width > 0, fill.height > 0 else { continue }

                    let path       = Path(fill)
                    let base       = categoryColor(item.node)
                    let opacity    = item.node.isCloudOnly ? 0.4 : 0.85
                    ctx.fill(path, with: .color(base.opacity(opacity)))

                    let isSelected = item.node.id == selectedId
                    let isInfo     = item.node.id == infoNode?.id
                    ctx.stroke(path,
                               with: .color(isSelected ? .white : isInfo ? .white.opacity(0.55) : .black.opacity(0.15)),
                               lineWidth: isSelected ? 2 : isInfo ? 1.5 : 0.5)

                    guard fill.width > 28, fill.height > 16 else { continue }

                    ctx.draw(
                        Text(item.node.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white),
                        in: CGRect(x: fill.minX + 3, y: fill.minY + 3,
                                   width: fill.width - 6,
                                   height: max(fill.height / 2 - 3, 1))
                    )

                    guard fill.height > 28 else { continue }
                    ctx.draw(
                        Text(item.node.formattedSize)    // always real size, not boosted
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8)),
                        in: CGRect(x: fill.minX + 3,
                                   y: fill.minY + fill.height / 2,
                                   width: fill.width - 6,
                                   height: max(fill.height / 2 - 3, 1))
                    )
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc):
                    let node = rects.first(where: { $0.rect.contains(loc) })?.node
                    // Only update state when the hovered node changes — avoids
                    // re-rendering the Canvas on every mouse-move pixel.
                    if node?.id != infoNode?.id {
                        infoNode = node
                        onHover?(node)
                    }
                case .ended:
                    if infoNode != nil {
                        infoNode = nil
                        onHover?(nil)
                    }
                }
            }
            #endif
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                guard let hit = rects.first(where: { $0.rect.contains(location) }) else { return }
                onDoubleTap?(hit.node)
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                guard let hit = rects.first(where: { $0.rect.contains(location) }) else { return }
                infoNode = hit.node
                onTap(hit.node)
            }
            .animation(.easeInOut(duration: 0.12), value: infoNode?.id)
            .clipped()
        }
        .onChange(of: nodes.map(\.id)) { _ in infoNode = nil }
    }

    // MARK: - Helpers

    private func makeLayoutSizes(sorted: [StorageNode], realTotal: Int64) -> [Int64] {
        guard enforceMinSize else { return sorted.map { $0.totalSize() } }
        // Give every node at least (20% / n) of the layout area so small
        // siblings are always a clickable size. Floor at 2%.
        let minFraction = max(0.02, 0.20 / Double(max(sorted.count, 1)))
        let minSize     = Int64(Double(realTotal) * minFraction)
        return sorted.map { max($0.totalSize(), minSize) }
    }

    private func categoryColor(_ node: StorageNode) -> Color {
        switch node.category {
        case .drive:   return Color(hex: "#4A90D9")
        case .photos:  return Color(hex: "#E8A838")
        case .backups: return Color(hex: "#5CB85C")
        case .other:   return Color(hex: "#9B59B6")
        }
    }

    // MARK: - Squarified treemap (sizes array separate from nodes for min-size boosting)

    private func squarify(nodes: [StorageNode], sizes: [Int64], rect: CGRect) -> [TreemapRect] {
        guard !nodes.isEmpty, rect.width > 0.5, rect.height > 0.5 else { return [] }
        let total = sizes.reduce(Int64(0), +)
        guard total > 0 else { return [] }

        let shortSide = min(rect.width, rect.height)
        var rowNodes: [StorageNode] = []
        var rowSizes: [Int64]       = []
        var rowTotal: Int64         = 0

        for (node, size) in zip(nodes, sizes) {
            let testNodes = rowNodes + [node]
            let testSizes = rowSizes + [size]
            let testTotal = rowTotal + size
            let add = rowNodes.isEmpty
                || worstAspect(testSizes, rowTotal: testTotal, grandTotal: total,
                               side: shortSide, area: rect.width * rect.height)
                <= worstAspect(rowSizes, rowTotal: rowTotal, grandTotal: total,
                               side: shortSide, area: rect.width * rect.height)
            if add {
                rowNodes.append(node); rowSizes.append(size); rowTotal += size
            } else { break }
        }

        let placed   = placeRow(rowNodes, sizes: rowSizes, rowTotal: rowTotal, grandTotal: total, in: rect)
        let nextRect = advanceRect(rect, rowTotal: rowTotal, grandTotal: total)
        return placed + squarify(nodes: Array(nodes.dropFirst(rowNodes.count)),
                                 sizes: Array(sizes.dropFirst(rowNodes.count)),
                                 rect: nextRect)
    }

    private func worstAspect(_ sizes: [Int64], rowTotal: Int64, grandTotal: Int64,
                              side: CGFloat, area: CGFloat) -> CGFloat {
        guard rowTotal > 0, grandTotal > 0, side > 0 else { return .infinity }
        let rowArea   = CGFloat(rowTotal) / CGFloat(grandTotal) * area
        let thickness = rowArea / side
        guard thickness > 0 else { return .infinity }
        return sizes.reduce(CGFloat(0)) { worst, size in
            let len = CGFloat(size) / CGFloat(rowTotal) * side
            guard len > 0 else { return .infinity }
            return max(worst, max(thickness / len, len / thickness))
        }
    }

    private func placeRow(_ nodes: [StorageNode], sizes: [Int64], rowTotal: Int64,
                          grandTotal: Int64, in rect: CGRect) -> [TreemapRect] {
        guard rowTotal > 0, grandTotal > 0 else { return [] }
        let area        = rect.width * rect.height
        let rowArea     = CGFloat(rowTotal) / CGFloat(grandTotal) * area
        let isLandscape = rect.width >= rect.height
        let side        = isLandscape ? rect.height : rect.width
        let thickness   = side > 0 ? rowArea / side : 0

        var result: [TreemapRect] = []
        var offset: CGFloat = 0
        for (node, size) in zip(nodes, sizes) {
            let len = side * CGFloat(size) / CGFloat(rowTotal)
            let r: CGRect = isLandscape
                ? CGRect(x: rect.minX,          y: rect.minY + offset, width: thickness, height: len)
                : CGRect(x: rect.minX + offset, y: rect.minY,          width: len,       height: thickness)
            result.append(TreemapRect(node: node, rect: r))
            offset += len
        }
        return result
    }

    private func advanceRect(_ rect: CGRect, rowTotal: Int64, grandTotal: Int64) -> CGRect {
        guard rowTotal > 0, grandTotal > 0 else { return rect }
        let area        = rect.width * rect.height
        let rowArea     = CGFloat(rowTotal) / CGFloat(grandTotal) * area
        let isLandscape = rect.width >= rect.height
        let side        = isLandscape ? rect.height : rect.width
        let thickness   = side > 0 ? rowArea / side : 0
        return isLandscape
            ? CGRect(x: rect.minX + thickness, y: rect.minY,
                     width: max(rect.width - thickness, 0), height: rect.height)
            : CGRect(x: rect.minX, y: rect.minY + thickness,
                     width: rect.width, height: max(rect.height - thickness, 0))
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >>  8) & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}
