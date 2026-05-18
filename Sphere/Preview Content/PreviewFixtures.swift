import Foundation

@MainActor
enum PreviewFixtures {
    static func app() -> AppModel {
        let defaults = UserDefaults(suiteName: "sphere.preview.\(UUID().uuidString)")!
        let app = AppModel(defaults: defaults)
        app.addProfile(APIProfile(name: "Local Mihomo", baseURL: "http://127.0.0.1:9090", secret: ""))
        app.overview = BackendOverview(
            version: "Mihomo 1.19",
            uptime: nil,
            memoryBytes: 64_000,
            uploadBytesPerSecond: 120,
            downloadBytesPerSecond: 940,
            activeConnections: 2
        )
        app.proxyCollection = ProxyCollection(
            proxies: [
                ProxyItem(name: "DIRECT", type: "Direct"),
                ProxyItem(name: "Japan", type: "Shadowsocks", udp: true, delay: 64),
                ProxyItem(name: "GLOBAL", type: "Selector", now: "Japan", all: ["DIRECT", "Japan"]),
            ],
            groups: [
                ProxyItem(name: "GLOBAL", type: "Selector", now: "Japan", all: ["DIRECT", "Japan"])
            ]
        )
        app.proxyProviders = [
            ProxyProvider(name: "main", vehicleType: "HTTP", expireAt: Date().addingTimeInterval(86_400 * 30), usedBytes: 10 * 1024 * 1024 * 1024, totalBytes: 100 * 1024 * 1024 * 1024)
        ]
        app.rules = [
            RuleItem(type: "DOMAIN-SUFFIX", payload: "example.com", proxy: "GLOBAL")
        ]
        app.connections = ConnectionsSnapshot(
            uploadTotal: 2048,
            downloadTotal: 8192,
            connections: [
                ConnectionInfo(
                    id: "1",
                    metadata: ConnectionMetadata(
                        network: "tcp",
                        type: "HTTP",
                        sourceIP: "192.168.1.20",
                        destinationIP: "93.184.216.34",
                        host: "example.com",
                        process: nil
                    ),
                    upload: 2048,
                    download: 8192,
                    start: nil,
                    chains: ["GLOBAL", "Japan"],
                    rule: "DOMAIN-SUFFIX",
                    rulePayload: "example.com"
                ),
            ]
        )
        return app
    }
}
