import Rosalind

extension RosalindReport {
    static func structuralEqual(lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.app(lhsPath, _, _, lhsChildren), .app(rhsPath, _, _, rhsChildren)), let (
            .directory(lhsPath, _, _, lhsChildren),
            .directory(rhsPath, _, _, rhsChildren)
        ), let (.file(lhsPath, _, _, lhsChildren), .file(rhsPath, _, _, rhsChildren)):
            guard lhsPath == rhsPath, lhsChildren.count == rhsChildren.count else {
                return false
            }
            return zip(lhsChildren, rhsChildren).allSatisfy { lhsChild, rhsChild in
                structuralEqual(lhs: lhsChild, rhs: rhsChild)
            }
        default:
            return false
        }
    }
}
