import Foundation
import Observation

@Observable
@MainActor
final class ConfigStore {
    var rules: [RuleItem] = []
    var ruleProviders: [RuleProvider] = []
    var configs: [String: JSONValue] = [:]
    var clashMode: ClashMode = .rule

    func reset() {
        rules = []
        ruleProviders = []
        configs = [:]
        clashMode = .rule
    }

    func applyConfigs(_ values: [String: JSONValue]) {
        configs = values
        if case .string(let mode)? = values["mode"],
            let decodedMode = ClashMode(mihomoValue: mode) {
            clashMode = decodedMode
        }
    }
}
