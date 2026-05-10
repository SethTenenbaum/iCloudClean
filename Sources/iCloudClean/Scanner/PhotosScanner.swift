import Photos
import Foundation

actor PhotosScanner {

    func scan() async -> StorageNode {
        let root = StorageNode(name: "Photos", category: .photos)

        // Check status synchronously first — requestAuthorization on an undetermined
        // status can show a dialog that appears behind the window and stalls forever.
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return root }

        // Move all synchronous Photos I/O off the cooperative thread pool
        let (photoNode, videoNode) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let photos = Self.fetchAssets(for: .image)
                let videos = Self.fetchAssets(for: .video)
                continuation.resume(returning: (photos, videos))
            }
        }

        root.children = [photoNode, videoNode]
        root.size = root.totalSize()
        return root
    }

    // MARK: - Private (static = no actor isolation, safe to call from DispatchQueue)

    private static func fetchAssets(for mediaType: PHAssetMediaType) -> StorageNode {
        let label = mediaType == .video ? "Videos" : "Photos"
        let node  = StorageNode(name: label, category: .photos)

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: mediaType, options: fetchOptions)

        var totalSize: Int64 = 0
        var children: [StorageNode] = []

        assets.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let size = resources.reduce(Int64(0)) { sum, r in
                sum + ((r.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
            }
            totalSize += size

            let name = resources.first?.originalFilename ?? asset.localIdentifier
            children.append(StorageNode(
                name: name,
                category: .photos,
                size: size,
                isCloudOnly: !asset.isDownloaded,
                assetIdentifier: asset.localIdentifier
            ))
        }

        node.children = children.sorted { $0.size > $1.size }
        node.size = totalSize
        return node
    }
}

private extension PHAsset {
    var isDownloaded: Bool {
        PHAssetResource.assetResources(for: self)
            .contains { $0.value(forKey: "locallyAvailable") as? Bool == true }
    }
}
