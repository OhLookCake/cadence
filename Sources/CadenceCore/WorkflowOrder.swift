import Foundation

public enum WorkflowOrder {
    /// An insertion position is a gap in the original array, from zero through count.
    @discardableResult
    public static func move(_ id: UUID, in steps: inout [TaskStep], toInsertion insertion: Int) -> Bool {
        guard (0...steps.count).contains(insertion), let source = steps.firstIndex(where: { $0.id == id }) else { return false }
        let destination = insertion > source ? insertion - 1 : insertion
        if source != destination {
            let step = steps.remove(at: source)
            steps.insert(step, at: destination)
        }
        return true
    }
}
