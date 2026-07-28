import Foundation

enum ConnectionsSheetPresentation: Identifiable {
    case connections
    case device(SurgeDevice)

    var id: String {
        switch self {
        case .connections:
            return "connections"
        case .device(let device):
            return "device:\(device.id)"
        }
    }
}
