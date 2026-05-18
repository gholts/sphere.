import CryptoKit
import Foundation
import UIKit

actor ProxyIconDiskCache {
    static let shared = ProxyIconDiskCache()

    private let directory: URL
    private let maxIconBytes = 1_048_576
    private static let hexadecimalRadix = 16
    private static let singleHexDigitLength = 1

    init(directory: URL? = nil) {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let root = directory ?? cachesDirectory
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

@MainActor
enum ProxyIconCache {
    private static let images = NSCache<NSString, UIImage>()
    private static var misses: Set<String> = []
    private static var tasks: [String: Task<UIImage?, Never>] = [:]
    private static let maxIconBytes = 1_048_576

    static func cachedImage(for icon: String) -> UIImage? {
        let key = icon as NSString
        if let image = images.object(forKey: key) {
            return image
        }
        guard let image = decodeDataImage(icon) else {
            return nil
        }
        images.setObject(image, forKey: key)
        return image
    }

    static func image(for icon: String) async -> UIImage? {
        if let image = cachedImage(for: icon) {
            return image
        }
        if let task = tasks[icon] {
            return await task.value
        }
        let task = Task { await loadImage(for: icon) }
        tasks[icon] = task
        let image = await task.value
        tasks[icon] = nil
        return image
    }

    private static func loadImage(for icon: String) async -> UIImage? {
        if let image = await diskImage(for: icon) {
            return image
        }
        guard !misses.contains(icon), let url = remoteURL(for: icon) else {
            misses.insert(icon)
            return nil
        }
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard isSuccessful(response), data.count <= maxIconBytes, let image = UIImage(data: data) else {
                misses.insert(icon)
                return nil
            }
            images.setObject(image, forKey: icon as NSString)
            await ProxyIconDiskCache.shared.save(data, for: icon)
            return image
        } catch {
            misses.insert(icon)
            return nil
        }
    }

    private static func diskImage(for icon: String) async -> UIImage? {
        guard let data = await ProxyIconDiskCache.shared.data(for: icon),
              data.count <= maxIconBytes,
              let image = UIImage(data: data)
        else { return nil }
        images.setObject(image, forKey: icon as NSString)
        return image
    }

    private static func remoteURL(for icon: String) -> URL? {
        guard let url = URL(string: icon),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private static func isSuccessful(_ response: URLResponse) -> Bool {
        guard let response = response as? HTTPURLResponse else { return true }
        return 200..<300 ~= response.statusCode
    }

    private static func decodeDataImage(_ icon: String) -> UIImage? {
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
        return data.flatMap(UIImage.init(data:))
    }
}
