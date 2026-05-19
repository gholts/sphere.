import Foundation

enum ByteFormat {
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "n/a" }
        return value.formatted(.byteCount(style: .binary))
    }

    static func memoryBytes(_ value: Int?) -> String {
        guard let value else { return "n/a" }
        return iecBytes(Int64(value))
    }

    static func speedBytes(_ value: Int?) -> String {
        guard let value else { return "n/a" }
        return "\(Int64(value).formatted(.byteCount(style: .file)))/s"
    }

    private static func iecBytes(_ value: Int64) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var amount = Double(value)
        var unitIndex = 0
        while abs(amount) >= 1024, unitIndex < units.count - 1 {
            amount /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(value) B"
        }
        let fractionLength = amount >= 10 || amount.rounded() == amount ? 0 : 1
        let number = amount.formatted(.number.precision(.fractionLength(fractionLength)))
        return "\(number) \(units[unitIndex])"
    }
}

enum DateFormat {
    static func short(_ date: Date?) -> String {
        guard let date else { return "n/a" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func expire(_ date: Date?) -> String {
        guard let date else { return "No expiry" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
