import SwiftUI

struct ImageInfo {
    var filename: String
    var pixelSize: CGSize?
    var fileSize: Int?
    var dateModified: Date?

    static func load(for url: URL) async -> ImageInfo {
        let pixelSize = await ImageLoader.pixelSize(for: url)
        let values    = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ImageInfo(
            filename:     url.lastPathComponent,
            pixelSize:    pixelSize,
            fileSize:     values?.fileSize,
            dateModified: values?.contentModificationDate
        )
    }
}

struct InfoOverlayView: View {
    let info: ImageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.filename)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let ps = info.pixelSize {
                infoRow(icon: "aspectratio", text: "\(Int(ps.width)) × \(Int(ps.height)) px")
            }

            if let size = info.fileSize {
                infoRow(icon: "doc", text: formatBytes(size))
            }

            if let date = info.dateModified {
                infoRow(icon: "calendar", text: date.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding(12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .padding(16)
    }

    @ViewBuilder
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1  { return String(format: "%.1f MB", mb) }
        if kb >= 1  { return String(format: "%.0f KB", kb) }
        return "\(bytes) bytes"
    }
}
