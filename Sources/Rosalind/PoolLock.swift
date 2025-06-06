actor PoolLock {
    private let capacity: Int
    private var inUse: Int = 0
    private var waitQueue: [CheckedContinuation<Void, Never>] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    func acquire() async {
        if inUse < capacity {
            inUse += 1
            return
        }

        await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
    }

    func release() {
        guard inUse > 0 else { return }

        if waitQueue.isEmpty {
            inUse -= 1
        } else {
            let continuation = waitQueue.removeFirst()
            continuation.resume()
        }
    }
}
