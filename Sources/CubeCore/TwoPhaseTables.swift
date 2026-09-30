import Foundation

/// Move and pruning tables for Kociemba's two-phase algorithm.
///
/// Building them takes a moment, so the first build is written to the
/// caches folder and later launches just read it back.
public final class TwoPhaseTables: Sendable {

    static let moveCount = 18
    static let twistCount = 2187
    static let flipCount = 2048
    static let sliceCount = 11880
    static let slice1Count = 495
    static let cornerCount = 20160
    static let udEdgeCount = 20160
    static let halfEdgeCount = 1320

    /// Moves that keep a cube inside phase two's subgroup: U, D and half turns of R F L B.
    static let phase2Moves: [Int] = [0, 1, 2, 4, 7, 9, 10, 11, 13, 16]
    static let isPhase2Move: [Bool] = (0..<18).map { phase2Moves.contains($0) }

    let twistMove: [Int16]
    let flipMove: [Int16]
    let sliceMove: [Int16]
    let cornerMove: [Int16]
    let udEdgeMove: [Int16]
    let urToUlMove: [Int16]
    let ubToDfMove: [Int16]
    let pruneSliceTwist: [UInt8]
    let pruneSliceFlip: [UInt8]
    let pruneCornerSlice: [UInt8]
    let pruneEdgeSlice: [UInt8]

    /// Combination part of the slice coordinate when FR…BR sit in the middle layer.
    let goalSlice1: Int

    private static let fileVersion: UInt32 = 1

    /// Loaded from the cache on first use, or built and cached.
    public static let shared: TwoPhaseTables = {
        let url = cacheURL
        if let url, let cached = TwoPhaseTables(contentsOf: url) { return cached }
        let tables = TwoPhaseTables()
        if let url { tables.write(to: url) }
        return tables
    }()

    /// Warms the tables up in the background so the first solve is instant.
    public static func prepare() async {
        await Task.detached(priority: .utility) { _ = TwoPhaseTables.shared }.value
    }

    static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TwoPhaseTables-v\(fileVersion).bin")
    }

    // MARK: Building

    init() {
        let moves = CubieCube.moves
        let goal = CubieCube.solved.sliceCoordinate / 24

        func moveTable(count: Int, only: Set<Int>? = nil,
                       set: (inout CubieCube, Int) -> Void,
                       get: (CubieCube) -> Int,
                       multiply: (inout CubieCube, CubieCube) -> Void) -> [Int16] {
            var table = [Int16](repeating: 0, count: count * Self.moveCount)
            var cube = CubieCube.solved
            for i in 0..<count {
                set(&cube, i)
                for face in 0..<6 {
                    for power in 0..<4 {
                        multiply(&cube, moves[face])
                        guard power < 3 else { continue }
                        let m = face * 3 + power
                        if let only, !only.contains(m) { continue }
                        table[i * Self.moveCount + m] = Int16(get(cube))
                    }
                }
            }
            return table
        }

        let twistMove = moveTable(count: Self.twistCount, set: { $0.twist = $1 }, get: \.twist,
                                  multiply: { $0.cornerMultiply($1) })
        let flipMove = moveTable(count: Self.flipCount, set: { $0.flip = $1 }, get: \.flip,
                                 multiply: { $0.edgeMultiply($1) })
        let sliceMove = moveTable(count: Self.sliceCount, set: { $0.sliceCoordinate = $1 }, get: \.sliceCoordinate,
                                  multiply: { $0.edgeMultiply($1) })
        let cornerMove = moveTable(count: Self.cornerCount, set: { $0.cornerCoordinate = $1 }, get: \.cornerCoordinate,
                                   multiply: { $0.cornerMultiply($1) })
        let udEdgeMove = moveTable(count: Self.udEdgeCount, only: Set(Self.phase2Moves),
                                   set: { $0.udEdgeCoordinate = $1 }, get: \.udEdgeCoordinate,
                                   multiply: { $0.edgeMultiply($1) })

        let slice1Count = Self.slice1Count
        let pruneSliceTwist = Self.breadthFirst(size: slice1Count * Self.twistCount,
                                                start: goal, moves: Array(0..<18)) { index, m in
            let slice = index % slice1Count
            let twist = index / slice1Count
            let nextSlice = Int(sliceMove[(slice * 24) * 18 + m]) / 24
            return Int(twistMove[twist * 18 + m]) * slice1Count + nextSlice
        }
        let pruneSliceFlip = Self.breadthFirst(size: slice1Count * Self.flipCount,
                                               start: goal, moves: Array(0..<18)) { index, m in
            let slice = index % slice1Count
            let flip = index / slice1Count
            let nextSlice = Int(sliceMove[(slice * 24) * 18 + m]) / 24
            return Int(flipMove[flip * 18 + m]) * slice1Count + nextSlice
        }

        let base = goal * 24
        let parityFlip = Self.parityFlip
        func phase2Step(_ table: [Int16]) -> (Int, Int) -> Int {
            { index, m in
                let parity = index & 1
                let rest = index >> 1
                let coordinate = rest % 20160
                let slice2 = rest / 20160
                let nextSlice = Int(sliceMove[(base + slice2) * 18 + m]) - base
                let next = Int(table[coordinate * 18 + m])
                return ((nextSlice * 20160 + next) << 1) | (parity ^ parityFlip[m])
            }
        }

        goalSlice1 = goal
        self.twistMove = twistMove
        self.flipMove = flipMove
        self.sliceMove = sliceMove
        self.cornerMove = cornerMove
        self.udEdgeMove = udEdgeMove
        urToUlMove = moveTable(count: Self.halfEdgeCount, set: { $0.urToUl = $1 }, get: \.urToUl,
                               multiply: { $0.edgeMultiply($1) })
        ubToDfMove = moveTable(count: Self.halfEdgeCount, set: { $0.ubToDf = $1 }, get: \.ubToDf,
                               multiply: { $0.edgeMultiply($1) })
        self.pruneSliceTwist = pruneSliceTwist
        self.pruneSliceFlip = pruneSliceFlip
        pruneCornerSlice = Self.breadthFirst(size: 24 * 20160 * 2, start: 0, moves: Self.phase2Moves,
                                             step: phase2Step(cornerMove))
        pruneEdgeSlice = Self.breadthFirst(size: 24 * 20160 * 2, start: 0, moves: Self.phase2Moves,
                                           step: phase2Step(udEdgeMove))
    }

    /// Quarter turns change the permutation parity; half turns do not.
    static let parityFlip: [Int] = (0..<18).map { $0 % 3 == 1 ? 0 : 1 }

    private static func breadthFirst(size: Int, start: Int, moves: [Int],
                                     step: (Int, Int) -> Int) -> [UInt8] {
        var table = [UInt8](repeating: 0xFF, count: size)
        table[start] = 0
        var frontier = [start]
        var depth: UInt8 = 0
        while !frontier.isEmpty {
            var next: [Int] = []
            for index in frontier {
                for m in moves {
                    let target = step(index, m)
                    if table[target] == 0xFF {
                        table[target] = depth + 1
                        next.append(target)
                    }
                }
            }
            frontier = next
            depth += 1
        }
        return table
    }

    // MARK: Cache file

    private var arrays16: [[Int16]] { [twistMove, flipMove, sliceMove, cornerMove, udEdgeMove, urToUlMove, ubToDfMove] }
    private var arrays8: [[UInt8]] { [pruneSliceTwist, pruneSliceFlip, pruneCornerSlice, pruneEdgeSlice] }

    private func write(to url: URL) {
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        append(Self.fileVersion)
        append(UInt32(goalSlice1))
        for array in arrays16 {
            append(UInt32(array.count))
            array.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        for array in arrays8 {
            append(UInt32(array.count))
            array.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var offset = 0

        func readUInt32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            offset += 4
            return value
        }
        func read<T>(_ type: T.Type, expected: Int) -> [T]? {
            guard let count = readUInt32(), Int(count) == expected else { return nil }
            let bytes = expected * MemoryLayout<T>.stride
            guard offset + bytes <= data.count else { return nil }
            let array = [T](unsafeUninitializedCapacity: expected) { buffer, initialized in
                data.withUnsafeBytes { raw in
                    let source = UnsafeRawBufferPointer(rebasing: raw[offset..<(offset + bytes)])
                    UnsafeMutableRawBufferPointer(buffer).copyMemory(from: source)
                }
                initialized = expected
            }
            offset += bytes
            return array
        }

        guard readUInt32() == Self.fileVersion, let goal = readUInt32(),
              let twist = read(Int16.self, expected: Self.twistCount * 18),
              let flip = read(Int16.self, expected: Self.flipCount * 18),
              let slice = read(Int16.self, expected: Self.sliceCount * 18),
              let corner = read(Int16.self, expected: Self.cornerCount * 18),
              let udEdge = read(Int16.self, expected: Self.udEdgeCount * 18),
              let urToUl = read(Int16.self, expected: Self.halfEdgeCount * 18),
              let ubToDf = read(Int16.self, expected: Self.halfEdgeCount * 18),
              let pst = read(UInt8.self, expected: Self.slice1Count * Self.twistCount),
              let psf = read(UInt8.self, expected: Self.slice1Count * Self.flipCount),
              let pcs = read(UInt8.self, expected: 24 * 20160 * 2),
              let pes = read(UInt8.self, expected: 24 * 20160 * 2),
              offset == data.count
        else { return nil }

        goalSlice1 = Int(goal)
        twistMove = twist
        flipMove = flip
        sliceMove = slice
        cornerMove = corner
        udEdgeMove = udEdge
        urToUlMove = urToUl
        ubToDfMove = ubToDf
        pruneSliceTwist = pst
        pruneSliceFlip = psf
        pruneCornerSlice = pcs
        pruneEdgeSlice = pes
    }
}
