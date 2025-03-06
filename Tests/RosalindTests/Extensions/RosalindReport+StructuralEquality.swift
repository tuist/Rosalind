import Rosalind

extension RosalindReport {
    static func structuralEqual(lhs: Self, rhs: Self) -> Bool {
        guard lhs.path == rhs.path, lhs.children?.count == rhs.children?.count else {
            return false
        }
        return zip(lhs.children ?? [], rhs.children ?? []).allSatisfy { lhsChild, rhsChild in
            structuralEqual(lhs: lhsChild, rhs: rhsChild)
        }
    }
}
