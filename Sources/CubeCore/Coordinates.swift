import Foundation

/// Compact integer coordinates of a `CubieCube`, used by the two-phase
/// solver's move and pruning tables.
extension CubieCube {

    static func binomial(_ n: Int, _ k: Int) -> Int {
        guard k >= 0, n >= k else { return 0 }
        var result = 1
        for i in 0..<min(k, n - k) {
            result = result * (n - i) / (i + 1)
        }
        return result
    }

    static func factorial(_ n: Int) -> Int { n <= 1 ? 1 : (2...n).reduce(1, *) }

    // MARK: Orientation

    /// Corner twist, 0..<2187. The last corner follows from the other seven.
    public var twist: Int {
        get { (0..<7).reduce(0) { 3 * $0 + co[$1] } }
        set {
            var value = newValue
            var sum = 0
            for i in stride(from: 6, through: 0, by: -1) {
                co[i] = value % 3
                sum += co[i]
                value /= 3
            }
            co[7] = (3 - sum % 3) % 3
        }
    }

    /// Edge flip, 0..<2048. The last edge follows from the other eleven.
    public var flip: Int {
        get { (0..<11).reduce(0) { 2 * $0 + eo[$1] } }
        set {
            var value = newValue
            var sum = 0
            for i in stride(from: 10, through: 0, by: -1) {
                eo[i] = value % 2
                sum += eo[i]
                value /= 2
            }
            eo[11] = (2 - sum % 2) % 2
        }
    }

    // MARK: Ordered subsets

    /// Where the pieces `pieces` are (a combination of positions) and in which
    /// order (a permutation), packed into one number.
    static func orderedCoordinate(_ perm: [Int], pieces: ClosedRange<Int>) -> Int {
        let k = pieces.count
        var a = 0
        var found: [Int] = []
        found.reserveCapacity(k)
        for j in perm.indices where pieces.contains(perm[j]) {
            a += binomial(j, found.count + 1)
            found.append(perm[j])
        }
        var b = 0
        for j in stride(from: k - 1, to: 0, by: -1) {
            var shifts = 0
            while found[j] != pieces.lowerBound + j {
                rotateLeft(&found, upTo: j)
                shifts += 1
            }
            b = (j + 1) * b + shifts
        }
        return a * factorial(k) + b
    }

    /// Inverse of `orderedCoordinate`; untracked positions are `-1`.
    static func positions(forOrderedCoordinate index: Int, pieces: ClosedRange<Int>, count n: Int) -> [Int] {
        let k = pieces.count
        var b = index % factorial(k)
        var a = index / factorial(k)
        var order = Array(pieces)
        for j in 1..<k {
            var shifts = b % (j + 1)
            b /= j + 1
            while shifts > 0 {
                rotateRight(&order, upTo: j)
                shifts -= 1
            }
        }
        var perm = [Int](repeating: -1, count: n)
        var x = k - 1
        for j in stride(from: n - 1, through: 0, by: -1) where x >= 0 {
            let c = binomial(j, x + 1)
            if a >= c {
                perm[j] = order[x]
                a -= c
                x -= 1
            }
        }
        return perm
    }

    /// Fills the untracked slots with the remaining pieces in order.
    static func completed(_ partial: [Int]) -> [Int] {
        let used = Set(partial.filter { $0 >= 0 })
        var spare = (0..<partial.count).filter { !used.contains($0) }.makeIterator()
        return partial.map { $0 >= 0 ? $0 : (spare.next() ?? 0) }
    }

    private static func rotateLeft(_ array: inout [Int], upTo r: Int) {
        let first = array[0]
        for i in 0..<r { array[i] = array[i + 1] }
        array[r] = first
    }

    private static func rotateRight(_ array: inout [Int], upTo r: Int) {
        let last = array[r]
        for i in stride(from: r, to: 0, by: -1) { array[i] = array[i - 1] }
        array[0] = last
    }

    // MARK: Named coordinates

    /// FR, FL, BL and BR edges: position and order, 0..<11880.
    public var sliceCoordinate: Int {
        get { Self.orderedCoordinate(ep, pieces: 8...11) }
        set { ep = Self.completed(Self.positions(forOrderedCoordinate: newValue, pieces: 8...11, count: 12)) }
    }

    /// URF…DLF corners: position and order, 0..<20160.
    public var cornerCoordinate: Int {
        get { Self.orderedCoordinate(cp, pieces: 0...5) }
        set { cp = Self.completed(Self.positions(forOrderedCoordinate: newValue, pieces: 0...5, count: 8)) }
    }

    /// UR…DF edges: position and order. Below 20160 once in phase two.
    public var udEdgeCoordinate: Int {
        get { Self.orderedCoordinate(ep, pieces: 0...5) }
        set { ep = Self.completed(Self.positions(forOrderedCoordinate: newValue, pieces: 0...5, count: 12)) }
    }

    /// UR, UF, UL edges: 0..<1320.
    public var urToUl: Int {
        get { Self.orderedCoordinate(ep, pieces: 0...2) }
        set { ep = Self.completed(Self.positions(forOrderedCoordinate: newValue, pieces: 0...2, count: 12)) }
    }

    /// UB, DR, DF edges: 0..<1320.
    public var ubToDf: Int {
        get { Self.orderedCoordinate(ep, pieces: 3...5) }
        set { ep = Self.completed(Self.positions(forOrderedCoordinate: newValue, pieces: 3...5, count: 12)) }
    }

    /// Combines `urToUl` and `ubToDf` into `udEdgeCoordinate`, or `nil` if
    /// the two overlap.
    static func mergedUDEdges(urToUl: Int, ubToDf: Int) -> Int? {
        let first = positions(forOrderedCoordinate: urToUl, pieces: 0...2, count: 12)
        let second = positions(forOrderedCoordinate: ubToDf, pieces: 3...5, count: 12)
        var merged = [Int](repeating: -1, count: 12)
        for j in 0..<12 {
            if first[j] >= 0 && second[j] >= 0 { return nil }
            merged[j] = max(first[j], second[j])
        }
        return orderedCoordinate(merged, pieces: 0...5)
    }
}
