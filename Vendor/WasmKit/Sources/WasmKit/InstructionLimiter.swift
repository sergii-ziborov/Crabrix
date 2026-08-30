/// Called from the token-threaded dispatch loop after a bounded instruction
/// batch. A limiter can implement fuel, wall-clock deadlines, or cooperative
/// interruption by throwing an error.
///
/// This Crabrix extension is deliberately per-Store: compiler and user-program
/// executions can use different budgets without sharing mutable engine state.
public protocol InstructionLimiter: Sendable {
    func consume(instructionCount: UInt64) throws
}
