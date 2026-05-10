import SwiftUI
import Photos

#if os(macOS)
import QuickLookUI
#endif

struct PreviewSheet: View {
    let node: StorageNode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(node.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Group {
                if let assetId = node.assetIdentifier {
                    PhotoPreviewView(assetIdentifier: assetId)
                } else if let url = node.url {
                    FilePreviewView(url: url)
                } else {
                    unavailableView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No preview available")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Photo preview

struct PhotoPreviewView: View {
    let assetIdentifier: String

    #if os(macOS)
    @State private var loadedImage: NSImage?
    #else
    @State private var loadedImage: UIImage?
    #endif
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Could not load image")
                        .foregroundColor(.secondary)
                }
            } else if let img = loadedImage {
                #if os(macOS)
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
                #else
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
                #endif
            }
        }
        .task { load() }
    }

    private func load() {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier], options: nil
        ).firstObject else {
            isLoading = false
            failed = true
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1400, height: 1400),
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            DispatchQueue.main.async {
                if let img = image { loadedImage = img }
                if !isDegraded {
                    isLoading = false
                    if image == nil { failed = true }
                }
            }
        }
    }
}

// MARK: - File preview via QuickLook

struct FilePreviewView: View {
    let url: URL

    var body: some View {
        #if os(macOS)
        QuickLookView(url: url)
        #else
        VStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(url.lastPathComponent)
                .foregroundColor(.secondary)
        }
        #endif
    }
}

#if os(macOS)
struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView()
        view.previewItem = url as NSURL
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
    }
}
#endif
