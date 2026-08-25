import Foundation

enum BorrowRepair {
    static func apply(to source: String, diagnostic: RustDiagnostic) -> String? {
        guard diagnostic.code == "E0502" else { return nil }

        let mutableBorrow = diagnostic.spans.first {
            $0.label?.contains("mutable borrow occurs") == true
        }
        let laterUse = diagnostic.spans.first {
            $0.label?.contains("later used") == true
        }
        guard let mutableBorrow, let laterUse,
              mutableBorrow.lineStart < laterUse.lineStart
        else {
            return nil
        }

        var lines = source.components(separatedBy: "\n")
        let mutationIndex = mutableBorrow.lineStart - 1
        let useIndex = laterUse.lineStart - 1
        guard lines.indices.contains(mutationIndex), lines.indices.contains(useIndex) else {
            return nil
        }

        lines.swapAt(mutationIndex, useIndex)
        return lines.joined(separator: "\n")
    }
}
