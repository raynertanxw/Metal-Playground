//
//  Utils.swift
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 29/7/25.
//

/// Fast, non-cryptographic random number generator.
/// Uses a Linear Congruential Generator (LCG) internally.
/// - NOTE: Not thread-safe. Designed for single-threaded, high-performance generation.
struct FastRandom {
    private var state: UInt64

    /// Create a new PRNG with a seed
    init(seed: UInt64) {
        self.state = seed
    }

    /// Advance RNG state and return a new UInt32
    private mutating func nextUInt32() -> UInt32 {
        // Constants from Numerical Recipes (LCG)
        state = state &* 6364136223846793005 &+ 1
        return UInt32(truncatingIfNeeded: state >> 32)
    }

    /// Returns a `Float` in the range [0, 1)
    mutating func nextUnitFloat() -> Float {
        return Float(nextUInt32()) / Float(UInt32.max)
    }

    /// Returns a `Float` in the **inclusive** range [min, max]
    mutating func nextFloat(min: Float, max: Float) -> Float {
        precondition(min <= max, "min must be <= max")
        return min + (max - min) * nextUnitFloat()
    }

    /// Returns an `UInt8` in the **inclusive** range [min, max]
    mutating func nextUInt8(min: UInt8 = 0, max: UInt8 = 255) -> UInt8 {
        precondition(min <= max, "min must be <= max")
        let range: UInt32 = UInt32(max - min) + 1
        return min + UInt8(nextUInt32() % range)
    }

    /// Returns an `Int` in the **inclusive** range [min, max]
    mutating func nextInt(min: Int, max: Int) -> Int {
        precondition(min <= max, "min must be <= max")
        let range = UInt32(max - min + 1)
        return min + Int(nextUInt32() % range)
    }
}
