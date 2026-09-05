import Foundation

/// All score-sized storage lives here. The mutable filter holds offsets into this value.
struct EngravingScoreIndex {
    struct Moment {
        let beat: Double
        let notes: [EngravingReference.Note]
        let pitches: UInt128
        let left: UInt128
        let right: UInt128
        let rolled: Bool
        let measure: Int
        let line: Int
        var previousLeft: Int?
        var previousRight: Int?
        var nextLeft: Int?
        var nextRight: Int?
        var leftGap: Double?
        var rightGap: Double?
        var bassMotion: Int?
        var melodyMotion: Int?
        var rhythmRatio: Double?
        var lowestPitch: Int { pitches.trailingZeroBitCount }
        var highestPitch: Int { 127 - pitches.leadingZeroBitCount }
    }

    struct Line {
        let id: Int
        let extent: ClosedRange<Double>
    }

    struct Context: Hashable {
        let first: UInt128
        let second: UInt128
        let third: UInt128
    }

    let moments: [Moment]
    let lines: [Line]
    let domain: ClosedRange<Double>
    let postings: [[Int]]
    let contexts: [Context: [Int]]
    private let tree: [UInt128]
    private let treeBase: Int
    private let chordPrefix: [Int]
    private let monoBounds: [[Double]]

    init(_ reference: EngravingReference) {
        // Line identifiers and beat-range sorting are not musical order.
        let orderedLines = reference.lines.sorted { $0.measureRange.lowerBound < $1.measureRange.lowerBound }
        var ownership: [Int: Int] = [:]
        var compiledLines: [Line] = []
        var measureCursor = 0
        for (offset, line) in orderedLines.enumerated() {
            let start = measureCursor
            while measureCursor < reference.measures.count,
                  line.measureRange.contains(reference.measures[measureCursor].index) {
                ownership[reference.measures[measureCursor].index] = offset
                measureCursor += 1
            }
            let first = reference.measures[start]
            let last = reference.measures[measureCursor - 1]
            compiledLines.append(Line(id: line.index, extent: first.onset...(last.onset + last.duration)))
        }
        lines = compiledLines
        domain = reference.measures[0].onset...(reference.measures.last!.onset + reference.measures.last!.duration)
        var compiled: [Moment] = []
        var pitchPostings = Array(repeating: [Int](), count: 128)
        for source in reference.moments {
            let owner = reference.measures[EngravingReference.measureOffset(containing: source.beat, in: reference.measures)!]
            var left: UInt128 = 0
            var right: UInt128 = 0
            for note in source.notes {
                if note.hand == .left { left |= Self.mask(note.pitch) }
                else { right |= Self.mask(note.pitch) }
            }
            let offset = compiled.count
            var pitches = left | right
            while pitches != 0 {
                let pitch = pitches.trailingZeroBitCount
                pitchPostings[pitch].append(offset)
                pitches &= pitches - 1
            }
            compiled.append(Moment(beat: source.beat, notes: source.notes, pitches: left | right,
                                   left: left, right: right, rolled: source.attack == .rolled,
                                   measure: owner.index, line: ownership[owner.index]!))
        }
        var left: Int?
        var right: Int?
        for i in compiled.indices {
            compiled[i].previousLeft = left
            compiled[i].previousRight = right
            if let left { compiled[i].leftGap = compiled[i].beat - compiled[left].beat }
            if let right { compiled[i].rightGap = compiled[i].beat - compiled[right].beat }
            if i > 0 {
                compiled[i].bassMotion = compiled[i].lowestPitch - compiled[i - 1].lowestPitch
                compiled[i].melodyMotion = compiled[i].highestPitch - compiled[i - 1].highestPitch
                if i + 1 < compiled.count {
                    compiled[i].rhythmRatio = (compiled[i + 1].beat - compiled[i].beat) / (compiled[i].beat - compiled[i - 1].beat)
                }
            }
            if compiled[i].left != 0 { left = i }
            if compiled[i].right != 0 { right = i }
        }
        left = nil
        right = nil
        for i in compiled.indices.reversed() {
            compiled[i].nextLeft = left
            compiled[i].nextRight = right
            if compiled[i].left != 0 { left = i }
            if compiled[i].right != 0 { right = i }
        }
        moments = compiled
        chordPrefix = compiled.reduce(into: [0]) { $0.append($0.last! + ($1.pitches.nonzeroBitCount > 1 ? 1 : 0)) }
        postings = pitchPostings
        var contextIndex: [Context: [Int]] = [:]
        for i in compiled.indices {
            let key = Context(first: compiled[i].pitches,
                              second: i + 1 < compiled.count ? compiled[i + 1].pitches : 0,
                              third: i + 2 < compiled.count ? compiled[i + 2].pitches : 0)
            contextIndex[key, default: []].append(i)
        }
        contexts = contextIndex
        var base = 1
        while base < compiled.count { base *= 2 }
        treeBase = base
        var masks = Array(repeating: UInt128(0), count: base * 2)
        for i in compiled.indices { masks[base + i] = compiled[i].pitches }
        for i in stride(from: base - 1, through: 1, by: -1) { masks[i] = masks[2 * i] | masks[2 * i + 1] }
        tree = masks
        // Repeated monophonic families can be bounded by their normalized transition rows
        // without enumerating their occurrence postings during consumption.
        if compiled.allSatisfy({ $0.pitches.nonzeroBitCount == 1 }) {
            var bounds = Array(repeating: Array(repeating: 0.0, count: 128 * 128), count: 2)
            for (row, reach) in [8, 16].enumerated() {
                for source in compiled.indices {
                    let sourcePitch = compiled[source].lowestPitch
                    for hand in 0..<3 {
                        func audible(_ i: Int, _ lane: Int) -> UInt128 {
                            lane == 0 ? compiled[i].left : lane == 1 ? compiled[i].right : compiled[i].pitches
                        }
                        guard audible(source, hand) != 0 else { continue }
                        var weights: [Int: Double] = [:]
                        var total = 0.0, omissions = 0
                        let last = min(compiled.count - 1, source + reach)
                        if last > source {
                            for target in (source + 1)...last {
                                let baseWeight = 0.86 * pow(0.12, Double(omissions))
                                for nextHand in 0..<3 where audible(target, nextHand) != 0 {
                                    let contribution = baseWeight * (hand == nextHand ? 0.98 : 0.01)
                                    total += contribution
                                    weights[compiled[target].lowestPitch, default: 0] += contribution
                                }
                                if audible(target, hand) != 0 { omissions += 1 }
                            }
                        }
                        weights[sourcePitch, default: 0] += 0
                        for (pitch, matching) in weights {
                            let numerator = matching + (pitch == sourcePitch ? 0.12 : 0)
                            let denominator = 0.12 + matching + 0.90 * (total - matching)
                            let slot = sourcePitch * 128 + pitch
                            bounds[row][slot] = max(bounds[row][slot], 0.975 * numerator / denominator)
                        }
                    }
                }
            }
            monoBounds = bounds
        } else { monoBounds = [] }
    }

    static func mask(_ pitch: UInt8) -> UInt128 { UInt128(1) << UInt128(pitch) }

    func monophonicBound(from pitch: UInt128, to next: UInt8, reach: Int) -> Double? {
        guard !monoBounds.isEmpty, pitch.nonzeroBitCount == 1, reach == 8 || reach == 16 else { return nil }
        return monoBounds[reach == 8 ? 0 : 1][pitch.trailingZeroBitCount * 128 + Int(next)]
    }

    func hasChords(in range: ClosedRange<Int>) -> Bool {
        chordPrefix[min(moments.count, range.upperBound + 1)] > chordPrefix[max(0, range.lowerBound)]
    }

    func matchingRange(pitch: UInt8, within range: ClosedRange<Int>) -> ClosedRange<Int>? {
        let values = postings[Int(pitch)]
        func bound(_ value: Int) -> Int {
            var low = 0, high = values.count
            while low < high {
                let mid = (low + high) / 2
                if values[mid] < value { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let low = bound(range.lowerBound), high = bound(range.upperBound + 1)
        return low < high ? values[low]...values[high - 1] : nil
    }

    func lowerBound(_ beat: Double) -> Int {
        var low = 0
        var high = moments.count
        while low < high {
            let mid = (low + high) / 2
            if moments[mid].beat < beat { low = mid + 1 } else { high = mid }
        }
        return low
    }

    func visibleOffsets(_ range: ClosedRange<Double>?) -> Range<Int> {
        guard let range = usable(range) else { return 0..<0 }
        let end = range.upperBound == domain.upperBound ? moments.count : lowerBound(range.upperBound)
        return lowerBound(range.lowerBound)..<end
    }

    func usable(_ range: ClosedRange<Double>?) -> ClosedRange<Double>? {
        guard let range, range.lowerBound.isFinite, range.upperBound.isFinite,
              range.lowerBound < range.upperBound else { return nil }
        let low = max(domain.lowerBound, range.lowerBound)
        let high = min(domain.upperBound, range.upperBound)
        return low < high ? low...high : nil
    }

    func contains(_ beat: Double, in range: ClosedRange<Double>) -> Bool {
        beat >= range.lowerBound && (beat < range.upperBound || beat == domain.upperBound && beat == range.upperBound)
    }

    /// Conservative union query, logarithmic in the number of moments.
    func pitches(in range: ClosedRange<Int>) -> UInt128 {
        var low = max(0, range.lowerBound) + treeBase
        var high = min(moments.count - 1, range.upperBound) + treeBase + 1
        var result: UInt128 = 0
        while low < high {
            if low & 1 == 1 { result |= tree[low]; low += 1 }
            if high & 1 == 1 { high -= 1; result |= tree[high] }
            low /= 2
            high /= 2
        }
        return result
    }
}

/// Engineering budgets, not musical thresholds. Tests can use a larger exact-search budget.
struct EngravingLimits {
    var hypotheses = 128
    var perDestination = 8
    var destinations = 64
    var expansions = 4_096
    var history = 256
    var residuals = 128
    var localReach = 8
}
