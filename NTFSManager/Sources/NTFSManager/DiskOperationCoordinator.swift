import Foundation

/// 由 MainActor 上的 Store 持有。整盘操作会影响兄弟分区，因此按整盘互斥。
struct DiskOperationCoordinator {
    private(set) var activeDisks: Set<String> = []

    mutating func begin(_ wholeDisk: String) -> Bool {
        activeDisks.insert(wholeDisk).inserted
    }

    mutating func finish(_ wholeDisk: String) {
        activeDisks.remove(wholeDisk)
    }
}
