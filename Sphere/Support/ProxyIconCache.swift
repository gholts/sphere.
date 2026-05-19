import CryptoKit
import Foundation
import ImageIO

actor ProxyIconDiskCache {
    static let shared = ProxyIconDiskCache()

    private let directory: URL
    private let maxIconBytes = 1_048_576
    private static let hexadecimalRadix = 16
    private static let singleHexDigitLength = 1

    init(directory: URL? = nil) {
        let cachesDirectory =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let root =
            directory
            ?? cachesDirectory
            .appendingPathComponent("ProxyIconCache", isDirectory: true)
        self.directory = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func data(for icon: String) -> Data? {
        try? Data(contentsOf: fileURL(for: icon), options: [.mappedIfSafe])
    }

    func save(_ data: Data, for icon: String) {
        guard data.count <= maxIconBytes else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: icon), options: .atomic)
    }

    private func fileURL(for icon: String) -> URL {
        let digest = SHA256.hash(data: Data(icon.utf8))
        let name = digest.map(Self.hexByte).joined()
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    private static func hexByte(_ byte: UInt8) -> String {
        let value = String(byte, radix: hexadecimalRadix)
        return value.count == singleHexDigitLength ? "0\(value)" : value
    }
}

actor ProxyIconCache {
    static let shared = ProxyIconCache()

    private let images = NSCache<NSString, CGImageBox>()
    private var misses: Set<String> = []
    private var tasks: [String: Task<CGImage?, Never>] = [:]
    private let maxIconBytes = 1_048_576

    func image(for icon: String) async -> CGImage? {
        if let image = cachedImage(for: icon) {
            return image
        }
        guard !misses.contains(icon) else {
            return nil
        }
        if let task = tasks[icon] {
            return await task.value
        }
        let maxIconBytes = maxIconBytes
        let task = Task {
            await Self.loadImage(for: icon, maxIconBytes: maxIconBytes)
        }
        tasks[icon] = task
        let image = await task.value
        tasks[icon] = nil
        if let image {
            images.setObject(CGImageBox(image), forKey: icon as NSString)
        } else {
            misses.insert(icon)
        }
        return image
    }

    private func cachedImage(for icon: String) -> CGImage? {
        let key = icon as NSString
        return images.object(forKey: key)?.image
    }

    nonisolated private static func loadImage(for icon: String, maxIconBytes: Int) async -> CGImage? {
        if let image = await diskImage(for: icon, maxIconBytes: maxIconBytes) {
            return image
        }
        if let image = await decodeDataImage(icon, maxIconBytes: maxIconBytes) {
            return image
        }
        guard let url = remoteURL(for: icon) else { return nil }
        do {
            let request = URLRequest(
                url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard isSuccessful(response),
                let image = await decodeImageData(data, maxIconBytes: maxIconBytes)
            else { return nil }
            await ProxyIconDiskCache.shared.save(data, for: icon)
            return image
        } catch {
            return nil
        }
    }

    nonisolated private static func diskImage(for icon: String, maxIconBytes: Int) async -> CGImage? {
        guard let data = await ProxyIconDiskCache.shared.data(for: icon) else { return nil }
        return await decodeImageData(data, maxIconBytes: maxIconBytes)
    }

    nonisolated private static func remoteURL(for icon: String) -> URL? {
        guard let url = URL(string: icon),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    nonisolated private static func isSuccessful(_ response: URLResponse) -> Bool {
        guard let response = response as? HTTPURLResponse else { return true }
        return 200..<300 ~= response.statusCode
    }

    nonisolated private static func decodeDataImage(_ icon: String, maxIconBytes: Int) async
        -> CGImage? {
        guard icon.hasPrefix("data:image/"),
            let commaIndex = icon.firstIndex(of: ",")
        else { return nil }
        let header = icon[..<commaIndex]
        let payload = icon[icon.index(after: commaIndex)...]
        let data: Data?
        if header.contains(";base64") {
            data = Data(base64Encoded: String(payload))
        } else {
            data = String(payload).removingPercentEncoding.flatMap { Data($0.utf8) }
        }
        guard let data else { return nil }
        return await decodeImageData(data, maxIconBytes: maxIconBytes)
    }

    @Sendable
    nonisolated private static func decodeImageData(_ data: Data, maxIconBytes: Int) async
        -> CGImage? {
        guard data.count <= maxIconBytes,
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options = [kCGImageSourceShouldCache: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}

nonisolated private final class CGImageBox {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
