import Foundation

enum StorageCategory: String, CaseIterable, Identifiable {
    case drive    = "iCloud Drive"
    case photos   = "Photos"
    case backups  = "Backups"
    case other    = "Other"

    var id: String { rawValue }

    var color: String {
        switch self {
        case .drive:   return "#4A90D9"
        case .photos:  return "#E8A838"
        case .backups: return "#5CB85C"
        case .other:   return "#9B59B6"
        }
    }
}

final class StorageNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let url: URL?
    let category: StorageCategory
    var size: Int64
    var children: [StorageNode]
    var isCloudOnly: Bool
    var assetIdentifier: String?  // PHAsset localIdentifier for photo nodes

    var isLeaf: Bool { children.isEmpty }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    init(name: String, url: URL? = nil, category: StorageCategory, size: Int64 = 0, children: [StorageNode] = [], isCloudOnly: Bool = false, assetIdentifier: String? = nil) {
        self.name = name
        self.url = url
        self.category = category
        self.size = size
        self.children = children
        self.isCloudOnly = isCloudOnly
        self.assetIdentifier = assetIdentifier
    }

    func totalSize() -> Int64 {
        if isLeaf { return size }
        return children.reduce(0) { $0 + $1.totalSize() }
    }
}
