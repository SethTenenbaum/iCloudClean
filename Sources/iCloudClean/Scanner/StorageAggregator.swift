import Foundation
import Photos

@MainActor
final class StorageAggregator: ObservableObject {
    @Published var rootNodes: [StorageNode] = []
    @Published var isScanning = false
    @Published var scanPhase  = ""
    @Published var totalSize: Int64 = 0
    @Published var deletionQueue: [StorageNode] = []
    @Published var downloadQueue: [StorageNode] = []
    @Published var needsFullDiskAccess = false

    var queuedDeleteSize: Int64   { deletionQueue.reduce(0) { $0 + $1.totalSize() } }
    var queuedDownloadSize: Int64 { downloadQueue.reduce(0) { $0 + $1.totalSize() } }

    private let driveScanner  = iCloudDriveScanner()
    private let photosScanner = PhotosScanner()

    init() {
        checkFullDiskAccess()
    }

    // MARK: - Scan

    func scan() async {
        guard !isScanning else { return }
        checkFullDiskAccess()   // check immediately so banner shows before scan starts
        isScanning = true
        rootNodes  = []
        scanPhase  = "Scanning iCloud Drive…"

        async let driveResult  = timedScan(label: "Drive")  { await self.driveScanner.scan() }
        async let photosResult = timedScan(label: "Photos") { await self.photosScanner.scan() }

        let (drive, photos) = await (driveResult, photosResult)

        rootNodes  = [drive, photos].compactMap { $0 }.filter { $0.totalSize() > 0 }
        totalSize  = rootNodes.reduce(0) { $0 + $1.totalSize() }
        scanPhase  = ""
        isScanning = false
        checkFullDiskAccess()
    }

    // Wraps a scanner with a timeout; returns nil on timeout
    private func timedScan(label: String, work: @escaping @Sendable () async -> StorageNode) async -> StorageNode? {
        await withTaskGroup(of: StorageNode?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes
                print("iCloudClean: \(label) scanner timed out after 120 s")
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Deletion queue

    func isQueued(_ node: StorageNode) -> Bool {
        deletionQueue.contains { $0.id == node.id }
    }

    func toggleQueue(_ node: StorageNode) {
        if let idx = deletionQueue.firstIndex(where: { $0.id == node.id }) {
            deletionQueue.remove(at: idx)
        } else {
            deletionQueue.append(node)
        }
    }

    func clearDeleteQueue() { deletionQueue.removeAll() }

    func executeDeleteQueue() async {
        let toDelete = deletionQueue
        deletionQueue.removeAll()
        for node in toDelete {
            guard let url = node.url else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        await scan()
    }

    // MARK: - Download queue

    func isDownloadQueued(_ node: StorageNode) -> Bool {
        downloadQueue.contains { $0.id == node.id }
    }

    func toggleDownloadQueue(_ node: StorageNode) {
        if let idx = downloadQueue.firstIndex(where: { $0.id == node.id }) {
            downloadQueue.remove(at: idx)
        } else {
            downloadQueue.append(node)
        }
    }

    func clearDownloadQueue() { downloadQueue.removeAll() }

    func executeDownloadQueue() async {
        let toDownload = downloadQueue
        downloadQueue.removeAll()
        for node in toDownload {
            if let assetId = node.assetIdentifier {
                requestPhotoDownload(assetId)
            } else if let url = node.url {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await scan()
    }

    private func requestPhotoDownload(_ identifier: String) {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier], options: nil
        ).firstObject else { return }
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(
            for: asset, options: opts
        ) { _, _, _, _ in }
    }

    // MARK: - Single delete

    func delete(node: StorageNode) async {
        guard let url = node.url else { return }
        try? FileManager.default.removeItem(at: url)
        await scan()
    }

    // MARK: - Full Disk Access

    func checkFullDiskAccess() {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents")
        // isReadableFile returns true even when sandboxed — actually attempt a listing.
        let result = try? FileManager.default.contentsOfDirectory(atPath: probe.path)
        needsFullDiskAccess = (result == nil)
    }
}
