import Foundation

nonisolated struct SurgeDevice: Identifiable, Decodable, Equatable, Sendable {
    struct DHCP: Equatable, Sendable {
        var assignedIP: String?
        var currentIP: String?
        var hostname: String?
        var lastSeen: String?
        var displayName: String?
        var icon: String?
        var physicalAddress: String
        var handledBySurge: Bool
        var shouldHandledBySurge: Bool
        var waitingToReconnect: Bool

        var lastSeenDate: Date? {
            guard let value = lastSeen?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else {
                return nil
            }

            if let date = try? Date(
                value,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            ) {
                return date
            }
            return try? Date(value, strategy: .iso8601)
        }

        func prefersRelativeLastSeen(referenceDate: Date) -> Bool {
            guard let lastSeenDate else { return false }
            let sevenDays: TimeInterval = 7 * 24 * 60 * 60
            return abs(lastSeenDate.timeIntervalSince(referenceDate)) < sevenDays
        }
    }

    struct Update: Encodable, Equatable, Sendable {
        var physicalAddress: String
        var name: String?
        var address: String?
        var shouldHandledBySurge: Bool?
    }

    var identifier: String
    var name: String
    var displayIPAddress: String
    var sourceIP: String
    var physicalAddress: String?
    var vendor: String?
    var activeConnections: Int
    var totalConnections: Int
    var hasProxyConnection: Bool
    var hasTCPConnection: Bool
    var dhcp: DHCP?

    var id: String { identifier }

    var displayName: String {
        dhcp?.displayName?.nonEmptySurgeDeviceValue
            ?? name.nonEmptySurgeDeviceValue
            ?? displayIPAddress.nonEmptySurgeDeviceValue
            ?? sourceIP
    }

    var editablePhysicalAddress: String? {
        dhcp?.physicalAddress.nonEmptySurgeDeviceValue
    }

    var modeDescription: String {
        let isGateway = hasTCPConnection || dhcp?.shouldHandledBySurge == true
        switch (hasProxyConnection, isGateway) {
        case (true, true):
            return "Proxy + Gateway"
        case (true, false):
            return "Proxy"
        case (false, true):
            return "Gateway"
        case (false, false):
            return "Not Handled"
        }
    }

    func matches(sourceAddress: String?) -> Bool {
        guard let normalizedSource = Self.normalizedIPAddress(sourceAddress) else { return false }
        return Self.normalizedIPAddress(sourceIP) == normalizedSource
            || Self.normalizedIPAddress(displayIPAddress) == normalizedSource
            || Self.normalizedIPAddress(dhcp?.assignedIP) == normalizedSource
            || Self.normalizedIPAddress(dhcp?.currentIP) == normalizedSource
    }

    init(from decoder: Decoder) throws {
        self.init(value: try JSONValue(from: decoder))
    }

    fileprivate init(value: JSONValue) {
        let dhcpValue = value.objectValue["dhcpDevice"]
        let decodedDHCP = dhcpValue.flatMap(Self.dhcp(from:))
        let decodedSourceIP = value.string(for: "sourceIP", "sourceIp") ?? ""
        let decodedDisplayIPAddress =
            value.string(for: "displayIPAddress", "displayIpAddress")
            ?? decodedDHCP?.assignedIP
            ?? decodedDHCP?.currentIP
            ?? decodedSourceIP
        let decodedPhysicalAddress =
            value.string(for: "physicalAddress") ?? decodedDHCP?.physicalAddress
        let decodedName =
            value.string(for: "name")
            ?? decodedDHCP?.displayName
            ?? decodedDisplayIPAddress
        identifier =
            value.string(for: "identifier")
            ?? decodedPhysicalAddress
            ?? "\(decodedDisplayIPAddress)|\(decodedName)"
        name = decodedName
        displayIPAddress = decodedDisplayIPAddress
        sourceIP = decodedSourceIP
        physicalAddress = decodedPhysicalAddress
        vendor = value.string(for: "vendor")
        activeConnections = value.int(for: "activeConnections") ?? 0
        totalConnections = value.int(for: "totalConnections") ?? 0
        hasProxyConnection = value.bool(for: "hasProxyConnection") ?? false
        hasTCPConnection = value.bool(for: "hasTCPConnection") ?? false
        dhcp = decodedDHCP
    }

    static func normalizedIPAddress(_ value: String?) -> String? {
        var address = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !address.isEmpty else { return nil }

        if address.hasPrefix("["),
            let closingBracket = address.firstIndex(of: "]") {
            address = String(address[address.index(after: address.startIndex)..<closingBracket])
        } else if address.count(where: { $0 == ":" }) == 1,
            let portSeparator = address.lastIndex(of: ":"),
            Int(address[address.index(after: portSeparator)...]) != nil {
            address = String(address[..<portSeparator])
        }

        return address.lowercased()
    }

    private static func dhcp(from value: JSONValue) -> DHCP? {
        guard
            let macAddress = value.string(for: "physicalAddress"),
            !macAddress.isEmpty
        else {
            return nil
        }
        return DHCP(
            assignedIP: value.string(for: "assignedIP"),
            currentIP: value.string(for: "currentIP"),
            hostname: value.string(for: "dhcpHostname"),
            lastSeen: value.string(for: "dhcpLastSeen"),
            displayName: value.string(for: "displayName"),
            icon: value.string(for: "icon"),
            physicalAddress: macAddress,
            handledBySurge: value.bool(for: "handledBySurge") ?? false,
            shouldHandledBySurge: value.bool(for: "shouldHandledBySurge") ?? false,
            waitingToReconnect: value.bool(for: "waitingToReconnect") ?? false
        )
    }
}

nonisolated struct SurgeDevicesPayload: Decodable, Equatable, Sendable {
    var devices: [SurgeDevice]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let rawDevices = value.array(for: "devices")
        devices = rawDevices.map(SurgeDevice.init(value:))
    }
}

private extension String {
    nonisolated var nonEmptySurgeDeviceValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
