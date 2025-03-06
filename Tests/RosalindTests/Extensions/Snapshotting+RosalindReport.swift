import Foundation
import Rosalind
import SnapshotTesting
import XCTest

extension Diffing {
    fileprivate static func rosalind() -> Diffing<RosalindReport> {
        let jsonEncoder = JSONEncoder()
        let jsonDecoder = JSONDecoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return Diffing<RosalindReport>.init(toData: { value in
            try! jsonEncoder.encode(value)
        }, fromData: { data in
            try! jsonDecoder.decode(RosalindReport.self, from: data)
        }, diff: { (lhs: RosalindReport, rhs: RosalindReport) -> (String, [XCTAttachment])? in
            if RosalindReport.structuralEqual(lhs: lhs, rhs: rhs) {
                return nil
            } else {
                return Snapshotting<String, String>.json.diffing.diff(
                    try! String(decoding: jsonEncoder.encode(lhs), as: UTF8.self),
                    try! String(decoding: jsonEncoder.encode(rhs), as: UTF8.self)
                )
            }
        })
    }
}

extension Snapshotting {
    static func rosalind() -> Snapshotting<RosalindReport, RosalindReport> {
        Snapshotting<RosalindReport, RosalindReport>.init(pathExtension: nil, diffing: .rosalind())
    }
}
