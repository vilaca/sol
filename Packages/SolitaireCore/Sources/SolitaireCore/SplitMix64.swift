/// Small seeded generator so a seed always produces the same deal on every platform and Swift version.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array {
    /// Fisher–Yates with our own loop: the standard library's `shuffle(using:)` algorithm is not guaranteed stable.
    mutating func deterministicShuffle(using rng: inout SplitMix64) {
        guard count > 1 else { return }
        for i in stride(from: count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            swapAt(i, j)
        }
    }
}
