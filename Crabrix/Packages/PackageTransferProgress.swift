import Foundation

struct PackageTransferRow: Identifiable, Sendable, Equatable {
    enum State: Sendable, Equatable {
        case waiting, downloading, verifying, ready, cached
        case failed(String)
    }
    let package: PackageID
    let dependencies: [PackageID]
    var state: State = .waiting
    var id: PackageID { package }
}

enum PackageTransferEvent: Sendable {
    case planned([PackageTransferRow])
    case updated(PackageID, PackageTransferRow.State)
}

struct BuildStageEvent: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let label: String
}
