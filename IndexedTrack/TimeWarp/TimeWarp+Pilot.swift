//
//  TimeWarp+Pilot.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


extension TimeWarp {
    
    /// A chord of the first track and a chord of the second track that are paired.
    struct Pair: Sendable, Hashable {
        
        /// The index of the chord in the first track.
        var sheet: Int32
        
        /// The index of the chord in the second track.
        var performance: Int32
    }
    
    
    /// What pairing two chords by their keys earns and costs, in single precision. The pilot alignment and the tempo search score the same way.
    struct Scoring: Sendable {
        
        /// What each key that both chords hold earns.
        static let matchReward: Float = 2
        
        /// The cost of each key that only one of the two chords holds.
        var mismatch: Float
        
        /// The cost of the first chord of a run that has no partner.
        var gapOpen: Float
        
        /// The cost of each further chord of such a run.
        var gapExtend: Float
        
        init(mismatch: Float, gapOpen: Float, gapExtend: Float) {
            self.mismatch = mismatch
            self.gapOpen = gapOpen
            self.gapExtend = gapExtend
        }
        
        init(_ parameters: Parameters) {
            self.init(mismatch: Float(parameters.mismatchPenalty), gapOpen: Float(parameters.gapOpen), gapExtend: Float(parameters.gapExtend))
        }
    }
    
    
    /// The result of ``pilot(sheet:performance:scoring:halfWidth:)``.
    struct PilotAlignment: Sendable {
        
        /// The paired chords, increasing in both indices.
        var pairs: [Pair]
        
        /// The score of the alignment: what the pairs earn, less what the chords without a partner cost.
        var score: Float
    }
    
    
    /// The half-width of the band of the pilot alignment, in chords of the second track. It caps the memory of the alignment at 8193 bytes for each chord of the first track.
    static let pilotHalfWidth = 4096
    
    
    /// Aligns the chords of two tracks by the keys they hold alone, with no regard for time.
    ///
    /// This is the rough alignment that the tempo search is centered on, a semi-global alignment with affine gap costs, in the way of Needleman-Wunsch and Gotoh. Pairing a chord of `sheet` with a chord of `performance` earns 2 for each shared key and costs `scoring.mismatch` for each key that only one of them holds, and chords that share no key are never paired. A run of chords of either track that have no partner costs `scoring.gapOpen` for the first chord and `scoring.gapExtend` for each further one. The chords before the first pair cost nothing, and neither do those after the last pair on one of the two tracks, so extra material at the ends of either track is free.
    ///
    /// Each cell of the matrix scores three states: a pair, a chord of `sheet` without a partner, and a chord of `performance` without a partner. Only the cells within `halfWidth` columns of the diagonal of the matrix are scored, which makes the work and the memory proportional to the number of chords of `sheet` times the width of the band.
    ///
    /// - Parameters:
    ///   - sheet: The events of the first track.
    ///   - performance: The events of the second track.
    ///   - scoring: What pairs earn and gaps cost.
    ///   - halfWidth: The number of columns either side of the diagonal that are scored. A value of at least the larger number of chords scores the whole matrix.
    ///
    /// - Returns: The best alignment, which has no pairs if the two tracks share no chord keys or if either has no chords.
    ///
    /// - Complexity: O(*n* · min(*m*, *w*)), where *n* and *m* are the numbers of chords of `sheet` and `performance`, and *w* is `halfWidth`.
    static func pilot(sheet: Events, performance: Events, scoring: Scoring, halfWidth: Int = TimeWarp.pilotHalfWidth) -> PilotAlignment {
        let n = sheet.count
        let m = performance.count
        guard n > 0, m > 0, halfWidth >= 1 else { return PilotAlignment(pairs: [], score: 0) }
        
        let negInf: Float = -1e30
        let reward = Scoring.matchReward
        let mismatch = scoring.mismatch
        let gapOpen = scoring.gapOpen
        let gapExtend = scoring.gapExtend
        let band = Swift.min(halfWidth, Swift.max(n, m))
        
        // Row `r` holds the cells with `r` chords of the sheet and `c` chords of the performance consumed. Its band is the columns `lows[r]...highs[r]`, within `band` of the diagonal, and its pointers start at `bases[r]` of the packed pointer buffer. The bands only move to the right.
        var lows = [Int](repeating: 0, count: n &+ 1)
        var highs = [Int](repeating: 0, count: n &+ 1)
        var bases = [Int](repeating: 0, count: n &+ 2)
        var row = 0
        while row <= n {
            let center = Int((Double(row) * Double(m) / Double(n)).rounded())
            lows[row] = Swift.max(0, center &- band)
            highs[row] = Swift.min(m, center &+ band)
            bases[row &+ 1] = bases[row] &+ (highs[row] &- lows[row] &+ 1)
            row &+= 1
        }
        
        // For each cell, where each of its three states came from, two bits each: 0 a pair, 1 a chord of the sheet without a partner, 2 a chord of the performance without a partner. Every cell of a band is written before it is read.
        let pointers = UnsafeMutablePointer<UInt8>.allocate(capacity: bases[n &+ 1])
        defer { pointers.deallocate() }
        
        // Two rows of the three states, indexed by the column plus one so that the column left of the band is in the buffer. A cell outside the band of a row reads as unreachable: the cells to its right were never written, and the one to its left is reset.
        let rowLength = m &+ 2
        let scores = UnsafeMutablePointer<Float>.allocate(capacity: 6 &* rowLength)
        scores.initialize(repeating: negInf, count: 6 &* rowLength)
        defer { scores.deallocate() }
        
        var bestScore = negInf
        var bestRow = -1
        var bestColumn = -1
        var bestState = 0
        
        sheet.withUnsafeBuffers { sheetEvents in
            performance.withUnsafeBuffers { performanceEvents in
                var previousM = scores
                var previousX = scores + rowLength
                var previousY = scores + 2 &* rowLength
                var currentM = scores + 3 &* rowLength
                var currentX = scores + 4 &* rowLength
                var currentY = scores + 5 &* rowLength
                
                // Row 0: no chord of the sheet is consumed. The leading chords of the performance are free.
                previousM[1] = 0
                var leading = 1
                while leading <= highs[0] {
                    previousY[leading &+ 1] = 0
                    leading &+= 1
                }
                
                var r = 1
                while r <= n {
                    let i = r &- 1
                    let sheetLowKeys = sheetEvents.low[i]
                    let sheetHighKeys = sheetEvents.high[i]
                    let sheetSize = sheetEvents.sizes[i]
                    let lowest = lows[r]
                    let highest = highs[r]
                    let base = bases[r]
                    
                    // The cell left of the band is unreachable.
                    currentM[lowest] = negInf
                    currentX[lowest] = negInf
                    currentY[lowest] = negInf
                    
                    var leftM = negInf
                    var leftX = negInf
                    var leftY = negInf
                    var c = lowest
                    
                    if c == 0 {
                        // No chord of the performance is consumed: the leading chords of the sheet are free.
                        currentM[1] = negInf
                        currentX[1] = 0
                        currentY[1] = negInf
                        pointers[base] = 0
                        leftX = 0
                        c = 1
                    }
                    
                    while c <= highest {
                        let j = c &- 1
                        let shared = (sheetLowKeys & performanceEvents.low[j]).nonzeroBitCount &+ (sheetHighKeys & performanceEvents.high[j]).nonzeroBitCount
                        let sharedKeys = Float(shared)
                        let score = reward * sharedKeys - mismatch * ((sheetSize - sharedKeys) + (performanceEvents.sizes[j] - sharedKeys))
                        
                        // A pair, from the cell up and to the left. Ties go to a pair, then to a chord of the sheet without a partner.
                        let pairedM = previousM[c]
                        let pairedX = previousX[c]
                        let pairedY = previousY[c]
                        var pairedBest = pairedM
                        var pairedFrom: UInt8 = 0
                        let pairedFromX = pairedX > pairedBest
                        pairedBest = pairedFromX ? pairedX : pairedBest
                        pairedFrom = pairedFromX ? 1 : pairedFrom
                        let pairedFromY = pairedY > pairedBest
                        pairedBest = pairedFromY ? pairedY : pairedBest
                        pairedFrom = pairedFromY ? 2 : pairedFrom
                        let canPair = shared >= 1 && pairedBest > negInf / 2
                        let newM = canPair ? pairedBest + score : negInf
                        let pointerM: UInt8 = canPair ? pairedFrom : 0
                        
                        // A chord of the sheet without a partner, from the cell above.
                        let aboveM = previousM[c &+ 1] - gapOpen
                        let aboveX = previousX[c &+ 1] - gapExtend
                        let aboveY = previousY[c &+ 1] - gapOpen
                        var aboveBest = aboveM
                        var aboveFrom: UInt8 = 0
                        let aboveFromX = aboveX > aboveBest
                        aboveBest = aboveFromX ? aboveX : aboveBest
                        aboveFrom = aboveFromX ? 1 : aboveFrom
                        let aboveFromY = aboveY > aboveBest
                        aboveBest = aboveFromY ? aboveY : aboveBest
                        aboveFrom = aboveFromY ? 2 : aboveFrom
                        let canSkipSheet = aboveBest > negInf / 2
                        let newX = canSkipSheet ? aboveBest : negInf
                        let pointerX: UInt8 = canSkipSheet ? aboveFrom : 0
                        
                        // A chord of the performance without a partner, from the cell to the left.
                        let sideM = leftM - gapOpen
                        let sideX = leftX - gapOpen
                        let sideY = leftY - gapExtend
                        var sideBest = sideM
                        var sideFrom: UInt8 = 0
                        let sideFromX = sideX > sideBest
                        sideBest = sideFromX ? sideX : sideBest
                        sideFrom = sideFromX ? 1 : sideFrom
                        let sideFromY = sideY > sideBest
                        sideBest = sideFromY ? sideY : sideBest
                        sideFrom = sideFromY ? 2 : sideFrom
                        let canSkipPerformance = sideBest > negInf / 2
                        let newY = canSkipPerformance ? sideBest : negInf
                        let pointerY: UInt8 = canSkipPerformance ? sideFrom : 0
                        
                        currentM[c &+ 1] = newM
                        currentX[c &+ 1] = newX
                        currentY[c &+ 1] = newY
                        pointers[base &+ (c &- lowest)] = pointerM | pointerX << 2 | pointerY << 4
                        
                        leftM = newM
                        leftX = newX
                        leftY = newY
                        c &+= 1
                    }
                    
                    // The alignment may end on the last row, or in the last column: what follows is free.
                    var end = r == n ? lowest : (highest == m ? highest : highest &+ 1)
                    while end <= highest {
                        var value = currentM[end &+ 1]
                        var state = 0
                        let endsInX = currentX[end &+ 1] > value
                        value = endsInX ? currentX[end &+ 1] : value
                        state = endsInX ? 1 : state
                        let endsInY = currentY[end &+ 1] > value
                        value = endsInY ? currentY[end &+ 1] : value
                        state = endsInY ? 2 : state
                        if value > bestScore {
                            bestScore = value
                            bestRow = r
                            bestColumn = end
                            bestState = state
                        }
                        end &+= 1
                    }
                    
                    swap(&previousM, &currentM)
                    swap(&previousX, &currentX)
                    swap(&previousY, &currentY)
                    r &+= 1
                }
            }
        }
        
        guard bestRow > 0 else { return PilotAlignment(pairs: [], score: 0) }
        
        // Trace the best alignment back until a row or a column runs out.
        var pairs: [Pair] = []
        var r = bestRow
        var c = bestColumn
        var state = bestState
        while r > 0, c > 0 {
            assert(c >= lows[r] && c <= highs[r], "The alignment left its band.")
            let pointer = pointers[bases[r] &+ (c &- lows[r])]
            switch state {
            case 0:
                pairs.append(Pair(sheet: Int32(truncatingIfNeeded: r &- 1), performance: Int32(truncatingIfNeeded: c &- 1)))
                state = Int(pointer & 3)
                r &-= 1
                c &-= 1
            case 1:
                state = Int(pointer >> 2 & 3)
                r &-= 1
            default:
                state = Int(pointer >> 4 & 3)
                c &-= 1
            }
        }
        pairs.reverse()
        return PilotAlignment(pairs: pairs, score: bestScore)
    }
    
    
    /// Returns, for each chord of the performance, the index of the chord of the sheet around which the tempo search looks for its partner.
    ///
    /// The centers follow the pairs of the pilot alignment: between two pairs they are interpolated, and before the first and after the last they continue one chord of the sheet for each chord of the performance. The centers never decrease and stay in the sheet. Without two pairs, they follow the diagonal.
    ///
    /// - Parameters:
    ///   - pairs: The pairs of the pilot alignment.
    ///   - sheetCount: The number of chords of the sheet.
    ///   - performanceCount: The number of chords of the performance.
    ///
    /// - Complexity: O(*m*), where *m* is the number of chords of the performance.
    static func bandCenters(pairs: [Pair], sheetCount n: Int, performanceCount m: Int) -> [Int32] {
        var centers = [Int32](repeating: 0, count: m)
        guard pairs.count >= 2 else {
            var j = 0
            while j < m {
                centers[j] = Int32(truncatingIfNeeded: Int((Double(j) * Double(n &- 1) / Double(Swift.max(m &- 1, 1))).rounded()))
                j &+= 1
            }
            return centers
        }
        
        var cursor = 0
        var j = 0
        while j < m {
            while cursor &+ 1 < pairs.count, Int(pairs[cursor &+ 1].performance) <= j {
                cursor &+= 1
            }
            let a = pairs[cursor]
            let aSheet = Int(a.sheet)
            let aPerformance = Int(a.performance)
            var center: Int
            if cursor &+ 1 < pairs.count, j > aPerformance {
                let b = pairs[cursor &+ 1]
                let fraction = Double(j &- aPerformance) / Double(Swift.max(1, Int(b.performance) &- aPerformance))
                center = Int((Double(aSheet) + fraction * Double(Int(b.sheet) &- aSheet)).rounded())
            } else if j <= aPerformance {
                center = aSheet &- (aPerformance &- j)
            } else {
                center = aSheet &+ (j &- aPerformance)
            }
            center = Swift.min(Swift.max(center, 0), n &- 1)
            if j > 0 {
                center = Swift.max(center, Int(centers[j &- 1]))
            }
            centers[j] = Int32(truncatingIfNeeded: center)
            j &+= 1
        }
        return centers
    }
    
}
