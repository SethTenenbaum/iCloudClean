import Foundation


actor iCloudDriveScanner {

    func scan() async -> StorageNode {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.performScan())
            }
        }
    }

    // MARK: - Static helpers

    private struct ScanTask {
        let node: StorageNode
        let url: URL
        let category: StorageCategory
        let skipPaths: Set<String>
        var alwaysInclude: Bool = false
    }

    private static func performScan() -> StorageNode {
        let root = StorageNode(name: "iCloud Drive", category: .drive)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocsURL = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")

        // Phase 1 (sequential): register known home-level paths and build the task list.
        var homelevelPaths = Set<String>()
        var tasks: [ScanTask] = []

        // Hoist Documents, Desktop, and Downloads from com~apple~CloudDocs root as
        // named top-level nodes. We always use the com~apple~CloudDocs path as the
        // authoritative source — whether or not Desktop & Documents Folders sync is
        // enabled, the content is always there. We also register ~/Documents and
        // ~/Desktop in homelevelPaths so they're skipped if encountered elsewhere.
        for name in ["Documents", "Desktop", "Downloads"] {
            let cloudURL = cloudDocsURL.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: cloudURL.path) else { continue }
            homelevelPaths.insert(cloudURL.resolvingSymlinksInPath().path)
            // Also register the home-level path (e.g. ~/Documents) so it's skipped
            // if the scanner encounters it through a different route.
            let homeEquiv = home.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: homeEquiv.path) {
                homelevelPaths.insert(homeEquiv.resolvingSymlinksInPath().path)
            }
            tasks.append(ScanTask(
                node: StorageNode(name: name, url: cloudURL, category: .drive),
                url: cloudURL, category: .drive, skipPaths: [], alwaysInclude: true
            ))
        }

        // All app containers inside ~/Library/Mobile Documents
        let mobileDocs = home.appendingPathComponent("Library/Mobile Documents")
        if let containers = try? FileManager.default.contentsOfDirectory(
            at: mobileDocs, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
        ) {
            print("iCloudClean [scan] Mobile Documents containers=\(containers.count)")
            for containerURL in containers {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
                guard let res = try? containerURL.resourceValues(forKeys: keys),
                      res.isDirectory == true, res.isSymbolicLink != true else { continue }
                let id   = containerURL.lastPathComponent
                let name = id == "com~apple~CloudDocs" ? "Drive Files" : prettyContainerName(id)
                let cat: StorageCategory = id == "com~apple~CloudDocs" ? .drive : .other
                tasks.append(ScanTask(
                    node: StorageNode(name: name, url: containerURL, category: cat),
                    url: containerURL, category: cat, skipPaths: homelevelPaths
                ))
            }
        }

        // Phase 2 (concurrent): scan all top-level nodes in parallel.
        // Each task owns a unique StorageNode so there are no data races.
        DispatchQueue.concurrentPerform(iterations: tasks.count) { i in
            let t = tasks[i]
            scanDirectory(t.url, into: t.node, category: t.category, depth: 0, skip: t.skipPaths)
        }

        // Phase 3 (sequential): assemble root, preserving task order.
        for task in tasks {
            if task.alwaysInclude || task.node.totalSize() > 0 {
                root.children.append(task.node)
            }
        }

        // ~/Library/CloudStorage — Ventura+ mount for third-party cloud providers.
        // Usually empty or tiny; keep sequential.
        let cloudStorage = home.appendingPathComponent("Library/CloudStorage")
        if FileManager.default.fileExists(atPath: cloudStorage.path),
           let providers = try? FileManager.default.contentsOfDirectory(
               at: cloudStorage, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
           ) {
            for providerURL in providers {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
                guard let res = try? providerURL.resourceValues(forKeys: keys),
                      res.isDirectory == true else { continue }
                let canonical = providerURL.resolvingSymlinksInPath().path
                if canonical.contains("Mobile Documents") { continue }
                if homelevelPaths.contains(canonical) { continue }
                let id   = providerURL.lastPathComponent
                let name = prettyProviderName(id)
                let cat: StorageCategory = id.contains("iCloud") ? .drive : .other
                let node = StorageNode(name: name, url: providerURL, category: cat)
                scanDirectory(providerURL, into: node, category: cat, depth: 0, skip: homelevelPaths)
                if node.totalSize() > 0 { root.children.append(node) }
            }
        }

        sortAndSum(root)
        print("iCloudClean [scan] Final drive total: \(ByteCountFormatter.string(fromByteCount: root.totalSize(), countStyle: .file)), children: \(root.children.count)")
        return root
    }

    private static let maxDepth = 4
    private static let itemKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]

    private static func scanDirectory(_ url: URL, into parent: StorageNode,
                                      category: StorageCategory, depth: Int,
                                      skip: Set<String>) {
        guard depth < maxDepth else { return }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(itemKeys), options: []
        ) else { return }

        for itemURL in contents {
            guard let res = try? itemURL.resourceValues(forKeys: itemKeys) else { continue }

            let isSymlink = res.isSymbolicLink ?? false
            let isDir     = res.isDirectory ?? false
            if isSymlink && !isDir { continue }

            let rawName = itemURL.lastPathComponent
            let isStub  = rawName.hasPrefix(".") && rawName.hasSuffix(".icloud")
            if rawName.hasPrefix(".") && !isStub { continue }

            let displayName: String
            let nodeURL: URL
            if isStub {
                displayName = String(rawName.dropFirst().dropLast(".icloud".count))
                nodeURL = itemURL.deletingLastPathComponent().appendingPathComponent(displayName)
            } else {
                displayName = rawName
                nodeURL     = itemURL
            }

            if isDir {
                if !skip.isEmpty {
                    let canonical = nodeURL.resolvingSymlinksInPath().path
                    if skip.contains(canonical) { continue }
                }
                let child = StorageNode(name: displayName, url: nodeURL, category: category)
                scanDirectory(nodeURL, into: child, category: category, depth: depth + 1, skip: skip)
                parent.children.append(child)
            } else {
                let size = Int64(res.fileSize ?? 0)
                parent.children.append(
                    StorageNode(name: displayName, url: nodeURL, category: category,
                                size: size, isCloudOnly: isStub)
                )
            }
        }
    }

    private static func prettyProviderName(_ id: String) -> String {
        // e.g. "iCloud~com~apple~CloudDocs" -> "iCloud Drive"
        //      "OneDrive-Personal"          -> "OneDrive"
        if id.contains("CloudDocs") { return "iCloud Drive" }
        let trimmed = id
            .replacingOccurrences(of: "-Personal", with: "")
            .replacingOccurrences(of: "-Business", with: "")
        return trimmed
    }

    private static func prettyContainerName(_ id: String) -> String {
        let cleaned = id
            .replacingOccurrences(of: "iCloud~", with: "")
            .replacingOccurrences(of: "~", with: ".")
        return cleaned.split(separator: ".").last.map(String.init) ?? cleaned
    }

    private static func sortAndSum(_ node: StorageNode) {
        for child in node.children { sortAndSum(child) }
        node.children.sort { $0.totalSize() > $1.totalSize() }
        if !node.isLeaf {
            let computed = node.totalSize()
            // Keep real directories visible even when all children have zero size
            // (e.g. a cloud-only dir whose listing hasn't been synced locally).
            node.size = (computed == 0 && node.url != nil) ? 1 : computed
        }
    }
}
