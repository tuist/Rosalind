import Foundation

extension Sequence {
    func asyncMap<T>(_ transform: @escaping (Element) async throws -> T) async throws -> [T] {
        let elements = Array(self)

        if elements.isEmpty {
            return []
        }

        // Pre-allocate the results array and use indices directly
        var results = [T?](repeating: nil, count: elements.count)

        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            // Create a task for each element with its index
            for (index, element) in elements.enumerated() {
                group.addTask {
                    let result = try await transform(element)
                    return (index, result)
                }
            }

            // Place each result directly in its final position
            for try await (index, result) in group {
                results[index] = result
            }
        }

        // Unwrap the results (safe because we filled every position)
        return results.compactMap { $0 }
    }
}
