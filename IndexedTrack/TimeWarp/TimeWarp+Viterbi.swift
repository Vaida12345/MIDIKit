//
//  TimeWarp+Viterbi.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Foundation


extension TimeWarp {
    
    /// The constants of the tempo search in single precision, ready for the loops.
    struct TempoCosts: Sendable {
        
        /// What pairs earn and gaps cost.
        var scoring: Scoring
        
        /// The number of tempo states, which is odd.
        var binCount: Int
        
        /// The logarithm of the ratio between the tempos of two neighboring states.
        var binStep: Double
        
        /// The cost of moving the tempo by one state.
        var moveCost: Float
        
        /// The standard deviation of the logarithm of the start tempo.
        var priorSigma: Float
        
        /// See ``Parameters/timingNoise``.
        var noise: Float
        
        /// See ``Parameters/relativeTimingNoise``.
        var relativeNoise: Float
        
        /// See ``Parameters/timingWeight``.
        var weight: Float
        
        /// See ``Parameters/timingCap``.
        var cap: Float
        
        /// See ``Parameters/splitCost``.
        var splitCost: Float
        
        /// See ``Parameters/rollScale``.
        var rollScale: Float
        
        /// The largest step in chords of the sheet between two pairs.
        var maximumSkip: Int
        
        /// The largest number of chords of the performance without a partner between two pairs.
        var maximumExtras: Int
        
        init(_ parameters: Parameters) {
            self.scoring = Scoring(parameters)
            self.binCount = parameters.tempoBinCount
            self.binStep = log(parameters.tempoBinRatio)
            self.moveCost = Float(parameters.tempoMoveCost)
            self.priorSigma = Float(parameters.tempoPriorSigma)
            self.noise = Float(parameters.timingNoise)
            self.relativeNoise = Float(parameters.relativeTimingNoise)
            self.weight = Float(parameters.timingWeight)
            self.cap = Float(parameters.timingCap)
            self.splitCost = Float(parameters.splitCost)
            self.rollScale = Float(parameters.rollScale)
            self.maximumSkip = parameters.maximumSkip
            self.maximumExtras = parameters.maximumExtras
        }
    }
    
    
    /// The result of the tempo search.
    struct TempoAlignment: Sendable {
        
        /// The paired chords, increasing in the index of the performance, and not decreasing in the index of the sheet.
        var pairs: [Pair]
        
        /// The score of the path.
        var score: Float
        
        /// Whether the path came within three chords of an edge of the band that is not the edge of the sheet.
        var touchedEdge: Bool
    }
    
    
    /// The widest half-width the tempo search widens its band to, in chords of the sheet.
    static let maximumBandHalfWidth = 1024
    
    /// The most memory in bytes the tempo search may need to trace its best path back, which decides how far it widens its band: 4 bytes for each cell of the band that has states, and 2 bytes for each of its tempo states.
    static let maximumTraceBytes = 1 << 28
    
    
    /// Pairs the chords of two tracks along a path that follows a smoothly changing tempo.
    ///
    /// This runs ``tempoPass(sheet:performance:rate:costs:halfWidth:centers:)`` in a band of chords of the sheet around `centers`, and widens the band, as far as the limits of ``maximumBandHalfWidth`` and ``maximumTraceBytes`` allow, while the best path touches its edge.
    ///
    /// - Parameters:
    ///   - sheet: The events of the first track.
    ///   - performance: The events of the second track.
    ///   - rate: The tempo of the middle tempo state: the ratio of the performance's length to the sheet's.
    ///   - costs: The constants of the search.
    ///   - centers: For each chord of the performance, the index of the chord of the sheet around which the band is placed. See ``bandCenters(pairs:sheetCount:performanceCount:)``.
    ///   - halfWidth: The half-width of the band to start with, in chords of the sheet.
    ///
    /// - Complexity: See ``tempoPass(sheet:performance:rate:costs:halfWidth:centers:)``, once for each width tried, which is at most 6.
    static func tempoSearch(sheet: Events, performance: Events, rate: Double, costs: TempoCosts, centers: [Int32], halfWidth: Int) -> TempoAlignment {
        let n = sheet.count
        let m = performance.count
        let lanes = (costs.binCount &+ 7) & ~7
        
        var width = Swift.max(1, Swift.min(halfWidth, n))
        let ceiling = Swift.max(width, Swift.min(Self.maximumBandHalfWidth, n))
        var result = Self.tempoPass(sheet: sheet, performance: performance, rate: rate, costs: costs, halfWidth: width, centers: centers)
        while result.touchedEdge, width < ceiling {
            let wider = Swift.min(ceiling, width &* 2)
            let cells = Self.tempoRowStarts(sheet: sheet, performance: performance, halfWidth: wider, centers: centers)[m]
            guard cells &* (4 &+ 2 &* lanes) <= Self.maximumTraceBytes else { break }
            width = wider
            result = Self.tempoPass(sheet: sheet, performance: performance, rate: rate, costs: costs, halfWidth: width, centers: centers)
        }
        return result
    }
    
    
    /// Returns where the cells of each row of the band start among the cells that have states.
    ///
    /// A cell is a chord of the sheet in the band of a chord of the performance, and it has states if the two chords share a key. Only those cells are ever reached, so the search stores what it needs to trace the path back for them alone: a small share of the band.
    ///
    /// - Parameters:
    ///   - sheet: The events of the first track.
    ///   - performance: The events of the second track.
    ///   - halfWidth: The half-width of the band, in chords of the sheet.
    ///   - centers: For each chord of the performance, the index of the chord of the sheet that its band is centered on.
    ///
    /// - Returns: For each chord of the performance the number of cells that have states in the rows before it, and in the last element the number of all of them.
    ///
    /// - Complexity: O(*m* · *w*), where *m* is the number of chords of the performance and *w* the width of the band.
    static func tempoRowStarts(sheet: Events, performance: Events, halfWidth w: Int, centers: [Int32]) -> [Int] {
        let n = sheet.count
        let m = performance.count
        let width = 2 &* w &+ 1
        var starts = [Int](repeating: 0, count: m &+ 1)
        sheet.withUnsafeBuffers { sheetEvents in
            performance.withUnsafeBuffers { performanceEvents in
                var total = 0
                var j = 0
                while j < m {
                    starts[j] = total
                    let base = Int(centers[j]) &- w
                    let lowKeys = performanceEvents.low[j]
                    let highKeys = performanceEvents.high[j]
                    var local = Swift.max(0, -base)
                    let end = Swift.min(width, n &- base)
                    while local < end {
                        let i = base &+ local
                        let shared = (sheetEvents.low[i] & lowKeys).nonzeroBitCount &+ (sheetEvents.high[i] & highKeys).nonzeroBitCount
                        total &+= shared >= 1 ? 1 : 0
                        local &+= 1
                    }
                    j &+= 1
                }
                starts[m] = total
            }
        }
        return starts
    }
    
    
    /// Pairs the chords of two tracks along the best path through the states of a hidden tempo, in the spirit of Nakamura's temporal hidden Markov model.
    ///
    /// The path visits chords of the performance in order. A visit is a state: a chord of the sheet within `halfWidth` chords of the chord's center, and one of the tempo states, which are `costs.binCount` rates spaced by a constant ratio around `rate`. It scores what pairing the two chords earns. Getting there from the previous visit costs
    ///
    /// - a gap for each chord of the performance in between, up to `costs.maximumExtras`, which are extra,
    /// - a gap for the chords of the sheet that are skipped, up to `costs.maximumSkip - 1`, which the performance misses, or `costs.splitCost` if the two visits are to one chord of the sheet, which the performance plays rolled,
    /// - `costs.moveCost` if the tempo moves by one state, and
    /// - the timing: how far the interval between the two chords of the performance is from the interval between the chords of the sheet, times the tempo, in units of a spread that grows with the interval, squared and capped so that a pause costs a constant.
    ///
    /// A path may also start anywhere, at the cost of the tempo prior, and may restart after any visit it has passed, across any stretch of chords that has no partner, for the cost of two gap openings and a gap extension for each chord skipped. That is what lets it cross extra material. The path ends where it scores best.
    ///
    /// The best score of each state is found by dynamic programming, with the tempo states handled as the lanes of a vector: the work is for each visit and each way of arriving a few vector operations. Visits whose chords share no key with the chord of the performance are skipped.
    ///
    /// - Parameters:
    ///   - sheet: The events of the first track.
    ///   - performance: The events of the second track.
    ///   - rate: The tempo of the middle tempo state: the ratio of the performance's length to the sheet's.
    ///   - costs: The constants of the search.
    ///   - halfWidth: The half-width of the band, in chords of the sheet.
    ///   - centers: For each chord of the performance, the index of the chord of the sheet that its band is centered on. The centers must not decrease.
    ///
    /// - Returns: The path, which is empty if no chord of the performance shares a key with a chord in its band.
    ///
    /// - Complexity: O(*m* · *w* · *b* · (*e* + 1)(*d* + 1) / 8), where *m* is the number of chords of the performance, *w* the width of the band, *b* the number of tempo states, *e* the largest number of extra chords and *d* the largest skip. The memory to trace the path back is 4 + 2 *b* bytes for each cell of the band that shares a key, which is a few in ten.
    static func tempoPass(sheet: Events, performance: Events, rate: Double, costs q: TempoCosts, halfWidth w: Int, centers: [Int32]) -> TempoAlignment {
        let n = sheet.count
        let m = performance.count
        guard n > 0, m > 0 else { return TempoAlignment(pairs: [], score: 0, touchedEdge: false) }
        precondition(centers.count == m, "There must be a center for each chord of the performance.")
        
        let bins = q.binCount
        let middleBin = bins >> 1
        // Each cell has a lane for each tempo state, padded to whole vectors. `bins` is odd, so at least one lane is padding, which also keeps the right neighbor of the last state in the buffer.
        let lanes = (bins &+ 7) & ~7
        let chunks = lanes >> 3
        let width = 2 &* w &+ 1
        let rowStride = width &* lanes
        let extras = q.maximumExtras
        let skips = q.maximumSkip
        // A row of states reads from at most `extras + 1` rows before it, so that many and itself are alive.
        let ring = extras &+ 2
        let negInf: Float = -1e30
        let gapOpen = q.scoring.gapOpen
        let gapExtend = q.scoring.gapExtend
        let mismatch = q.scoring.mismatch
        let noiseSquared = q.noise * q.noise
        let relativeNoise = q.relativeNoise
        let weight = q.weight
        let cap = q.cap
        let moveCost = q.moveCost
        
        // Per tempo state: the rate, and what starting there costs, which is the log of a Gaussian prior on the log of the tempo. Padding lanes get a rate of 1 to keep the arithmetic finite, and a start that is never taken.
        let rates = Self.allocate(lanes, 1 as Float)
        let priors = Self.allocate(lanes, negInf)
        var bin = 0
        while bin < bins {
            let offset = Double(bin &- middleBin) * q.binStep
            rates[bin] = Float(rate * exp(offset))
            let z = Float(offset) / q.priorSigma
            priors[bin] = -0.5 * z * z
            bin &+= 1
        }
        
        // The cost of the chords of the performance and the chords of the sheet that are skipped between two visits.
        let extraCosts = Self.allocate(extras &+ 1, 0 as Float)
        var skipped = 1
        while skipped <= extras {
            extraCosts[skipped] = gapOpen + gapExtend * Float(skipped &- 1)
            skipped &+= 1
        }
        let skipCosts = Self.allocate(skips &+ 1, 0 as Float)
        skipped = 2
        while skipped <= skips {
            skipCosts[skipped] = gapOpen + gapExtend * Float(skipped &- 2)
            skipped &+= 1
        }
        
        // The best score of each state, as arrived at (`values`) and after a tempo move (`smooth`), for the rows of the ring. A flag says whether a cell of a row has states.
        let values = Self.allocate(ring &* rowStride, negInf)
        let smooth = Self.allocate(ring &* rowStride, negInf)
        let flags = Self.allocate(ring &* width, 0 as UInt8)
        
        // What it takes to trace the path back, for the cells that have states, in the order of the rows: the position of each cell in its row; for each of its states, how it was arrived at, which is the code `extra + (extras + 1) * skip` of the previous visit, `0xFE` for a restart and `0xFF` for a start; and whether the tempo moved down, stayed or moved up (0, 1, 2) from the state of the previous visit. Only what was written is ever read, so these are not initialized.
        let rowStarts = Self.tempoRowStarts(sheet: sheet, performance: performance, halfWidth: w, centers: centers)
        let cellCount = rowStarts[m]
        let cellLocals = UnsafeMutablePointer<Int32>.allocate(capacity: Swift.max(cellCount, 1))
        let codes = UnsafeMutablePointer<UInt8>.allocate(capacity: Swift.max(cellCount &* lanes, 1))
        let moves = UnsafeMutablePointer<UInt8>.allocate(capacity: Swift.max(cellCount &* lanes, 1))
        // For each row, the state a restart in that row comes from: its row, sheet chord and tempo state.
        let restarts = Self.allocate(3 &* m, -1 as Int32)
        
        // The ways of arriving at one cell, and the rows they come from.
        let transitions = UnsafeMutablePointer<Transition>.allocate(capacity: (extras &+ 1) &* (skips &+ 1))
        let reachSlots = Self.allocate(extras &+ 1, 0 as Int)
        let reachBases = Self.allocate(extras &+ 1, 0 as Int)
        let reachGaps = Self.allocate(extras &+ 1, 0 as Float)
        
        defer {
            rates.deallocate()
            priors.deallocate()
            extraCosts.deallocate()
            skipCosts.deallocate()
            values.deallocate()
            smooth.deallocate()
            flags.deallocate()
            cellLocals.deallocate()
            codes.deallocate()
            moves.deallocate()
            restarts.deallocate()
            transitions.deallocate()
            reachSlots.deallocate()
            reachBases.deallocate()
            reachGaps.deallocate()
        }
        
        // The best state of the rows before the current one. A path may restart from it, and the path that ends the search is the one that scores best.
        var prefixValue = negInf
        var prefixJ = -1
        var prefixI = -1
        var prefixK = -1
        
        sheet.withUnsafeBuffers { sheetEvents in
            performance.withUnsafeBuffers { performanceEvents in
                centers.withUnsafeBufferPointer { centers in
                    var j = 0
                    while j < m {
                        restarts[3 &* j] = Int32(truncatingIfNeeded: prefixJ)
                        restarts[3 &* j &+ 1] = Int32(truncatingIfNeeded: prefixI)
                        restarts[3 &* j &+ 2] = Int32(truncatingIfNeeded: prefixK)
                        
                        let slot = j % ring
                        let base = Int(centers[j]) &- w
                        let rowFlags = flags + slot &* width
                        rowFlags.update(repeating: 0, count: width)
                        let rowValues = values + slot &* rowStride
                        let firstCell = rowStarts[j]
                        var cell = firstCell
                        let time = performanceEvents.times[j]
                        let performanceLowKeys = performanceEvents.low[j]
                        let performanceHighKeys = performanceEvents.high[j]
                        let performanceSize = performanceEvents.sizes[j]
                        
                        // The rows before this one that a path may come from.
                        var reach = 0
                        while reach <= extras, j &- 1 &- reach >= 0 {
                            let earlier = j &- 1 &- reach
                            reachSlots[reach] = earlier % ring
                            reachBases[reach] = Int(centers[earlier]) &- w
                            reachGaps[reach] = Float(time - performanceEvents.times[earlier])
                            reach &+= 1
                        }
                        
                        var rowValue = negInf
                        var rowI = -1
                        var rowK = -1
                        
                        // The cells of the band that are chords of the sheet.
                        var local = Swift.max(0, -base)
                        let localEnd = Swift.min(width, n &- base)
                        while local < localEnd {
                            let i = base &+ local
                            let shared = (sheetEvents.low[i] & performanceLowKeys).nonzeroBitCount &+ (sheetEvents.high[i] & performanceHighKeys).nonzeroBitCount
                            
                            if shared >= 1 {
                                let sharedKeys = Float(shared)
                                let emission = Scoring.matchReward * sharedKeys - mismatch * ((sheetEvents.sizes[i] - sharedKeys) + (performanceSize - sharedKeys))
                                
                                // The ways to arrive here, in the order that ties are broken in: by the extra chords, then by the skip.
                                var count = 0
                                var extra = 0
                                while extra < reach {
                                    var skip = 0
                                    while skip <= skips, i &- skip >= 0 {
                                        let earlierLocal = (i &- skip) &- reachBases[extra]
                                        if earlierLocal >= 0, earlierLocal < width, flags[reachSlots[extra] &* width &+ earlierLocal] != 0 {
                                            let gapB = reachGaps[extra]
                                            let leftOut = extraCosts[extra] + skipCosts[skip]
                                            var transition = Transition(
                                                offset: reachSlots[extra] &* rowStride &+ earlierLocal &* lanes,
                                                code: Int32(truncatingIfNeeded: extra &+ (extras &+ 1) &* skip),
                                                gapA: 0,
                                                gapB: gapB,
                                                cost: leftOut,
                                                isSplit: skip == 0
                                            )
                                            if skip == 0 {
                                                // Two chords of the performance for one chord of the sheet: a roll, which costs more the farther apart the two are.
                                                transition.cost = leftOut + (q.splitCost + weight * Swift.min(cap, gapB / q.rollScale))
                                            } else {
                                                transition.gapA = Float(sheetEvents.times[i] - sheetEvents.times[i &- skip])
                                            }
                                            transitions[count] = transition
                                            count &+= 1
                                        }
                                        skip &+= 1
                                    }
                                    extra &+= 1
                                }
                                
                                // A restart from the best state of the rows before, across the chords that are skipped on both sides.
                                let canRestart = prefixJ >= 0 && i > prefixI
                                let restartBase = canRestart ? prefixValue - (2 * gapOpen + gapExtend * Float((j &- prefixJ &- 1) &+ (i &- prefixI &- 1))) : negInf
                                
                                // The states are lanes: all tempo states of this cell are scored together, a vector at a time.
                                var chunk = 0
                                while chunk < chunks {
                                    let lane = chunk &<< 3
                                    let stateRates = UnsafeRawPointer(rates + lane).loadUnaligned(as: SIMD8<Float>.self)
                                    let prior = UnsafeRawPointer(priors + lane).loadUnaligned(as: SIMD8<Float>.self)
                                    
                                    // Start here, or arrive from the best way. A way wins only when it is strictly better, so ties go to starting, then to the first way.
                                    var best = prior
                                    var code = SIMD8<Int32>(repeating: 0xFF)
                                    var way = 0
                                    while way < count {
                                        let transition = transitions[way]
                                        let carried = UnsafeRawPointer(smooth + (transition.offset &+ lane)).loadUnaligned(as: SIMD8<Float>.self)
                                        var cost = SIMD8<Float>(repeating: transition.cost)
                                        if !transition.isSplit {
                                            // How far the interval of the performance is from the interval of the sheet at this tempo, in units of a spread that grows with the interval.
                                            let expected = stateRates * transition.gapA
                                            let spread = ((relativeNoise * expected) * relativeNoise) * expected
                                            let sigma = (noiseSquared + spread).squareRoot()
                                            let z = (transition.gapB - expected) / sigma
                                            let penalty = pointwiseMin(SIMD8<Float>(repeating: cap), (0.5 * z) * z)
                                            cost += weight * penalty
                                        }
                                        let candidate = carried - cost
                                        let better = candidate .> best
                                        best.replace(with: candidate, where: better)
                                        code.replace(with: SIMD8<Int32>(repeating: transition.code), where: better)
                                        way &+= 1
                                    }
                                    
                                    if canRestart {
                                        let candidate = restartBase + prior
                                        let better = candidate .> best
                                        best.replace(with: candidate, where: better)
                                        code.replace(with: 0xFE, where: better)
                                    }
                                    
                                    var value = best + emission
                                    let isPadding = (SIMD8<Int32>(0, 1, 2, 3, 4, 5, 6, 7) &+ Int32(truncatingIfNeeded: lane)) .>= Int32(truncatingIfNeeded: bins)
                                    value.replace(with: negInf, where: isPadding)
                                    
                                    UnsafeMutableRawPointer(rowValues + (local &* lanes &+ lane)).storeBytes(of: value, as: SIMD8<Float>.self)
                                    UnsafeMutableRawPointer(codes + (cell &* lanes &+ lane)).storeBytes(of: SIMD8<UInt8>(truncatingIfNeeded: code), as: SIMD8<UInt8>.self)
                                    chunk &+= 1
                                }
                                
                                // The best state of the row, the first when states tie.
                                var state = 0
                                while state < bins {
                                    let value = rowValues[local &* lanes &+ state]
                                    let isBetter = value > rowValue
                                    rowValue = isBetter ? value : rowValue
                                    rowI = isBetter ? i : rowI
                                    rowK = isBetter ? state : rowK
                                    state &+= 1
                                }
                                rowFlags[local] = 1
                                cellLocals[cell] = Int32(truncatingIfNeeded: local)
                                cell &+= 1
                            }
                            local &+= 1
                        }
                        assert(cell == rowStarts[j &+ 1], "The cells that have states are not the ones that were counted.")
                        
                        if rowValue > prefixValue {
                            prefixValue = rowValue
                            prefixJ = j
                            prefixI = rowI
                            prefixK = rowK
                        }
                        
                        // Let the tempo move by one state: a state is as good as the best of itself and its two neighbors less the cost of the move. Lane `bins` is padding, so the right neighbor of the last state reads as unreachable.
                        var smoothed = firstCell
                        while smoothed < cell {
                            let cellOffset = Int(cellLocals[smoothed]) &* lanes
                            let source = rowValues + cellOffset
                            let target = smooth + (slot &* rowStride &+ cellOffset)
                            let moved = moves + smoothed &* lanes
                            // What the neighbor state below offers, and the one above.
                            var fromBelow = negInf
                            var state = 0
                            while state < bins {
                                let value = source[state]
                                let fromAbove = source[state &+ 1] - moveCost
                                var best = value
                                var move: UInt8 = 1
                                let usesBelow = fromBelow > best
                                best = usesBelow ? fromBelow : best
                                move = usesBelow ? 0 : move
                                let usesAbove = fromAbove > best
                                best = usesAbove ? fromAbove : best
                                move = usesAbove ? 2 : move
                                target[state] = best
                                moved[state] = move
                                fromBelow = value - moveCost
                                state &+= 1
                            }
                            smoothed &+= 1
                        }
                        
                        j &+= 1
                    }
                }
            }
        }
        
        guard prefixJ >= 0 else { return TempoAlignment(pairs: [], score: 0, touchedEdge: false) }
        
        /// The index among the cells that have states of the cell of a row at a position in its band. The row has it, as the path only visits cells that have states.
        func cellIndex(row: Int, local: Int) -> Int {
            var low = rowStarts[row]
            var high = rowStarts[row &+ 1]
            while low < high {
                let middle = low &+ (high &- low) &>> 1
                if Int(cellLocals[middle]) < local {
                    low = middle &+ 1
                } else {
                    high = middle
                }
            }
            assert(low < rowStarts[row &+ 1] && Int(cellLocals[low]) == local, "The path left the cells that have states.")
            return low
        }
        
        // Trace the best path back to where it started, hopping over the stretch of a restart.
        var pairs: [Pair] = []
        var touchedEdge = false
        var j = prefixJ
        var i = prefixI
        var k = prefixK
        while true {
            let center = Int(centers[j])
            let local = i &- (center &- w)
            assert(local >= 0 && local < width, "The path left its band.")
            if (local <= 2 && center &- w > 0) || (local >= width &- 3 && center &+ w < n &- 1) {
                touchedEdge = true
            }
            pairs.append(Pair(sheet: Int32(truncatingIfNeeded: i), performance: Int32(truncatingIfNeeded: j)))
            
            let code = codes[cellIndex(row: j, local: local) &* lanes &+ k]
            if code == 0xFF { break }
            if code == 0xFE {
                let restart = 3 &* j
                j = Int(restarts[restart])
                i = Int(restarts[restart &+ 1])
                k = Int(restarts[restart &+ 2])
                continue
            }
            
            let extra = Int(code) % (extras &+ 1)
            let skip = Int(code) / (extras &+ 1)
            let earlierJ = j &- 1 &- extra
            let earlierI = i &- skip
            let earlierLocal = earlierI &- (Int(centers[earlierJ]) &- w)
            let move = Int(moves[cellIndex(row: earlierJ, local: earlierLocal) &* lanes &+ k]) &- 1
            k &+= move
            i = earlierI
            j = earlierJ
        }
        pairs.reverse()
        return TempoAlignment(pairs: pairs, score: prefixValue, touchedEdge: touchedEdge)
    }
    
    
    /// A way to arrive at a cell of the tempo search, from a cell of an earlier row.
    private struct Transition {
        
        /// Where the tempo states of the cell it comes from start in the smoothed rows.
        var offset: Int
        
        /// The code of the way, `extra + (extras + 1) * skip`.
        var code: Int32
        
        /// The interval between the two chords of the sheet, which a split does not use.
        var gapA: Float
        
        /// The interval between the two chords of the performance.
        var gapB: Float
        
        /// What the chords left out cost, and for a split everything it costs.
        var cost: Float
        
        /// Whether both visits are to one chord of the sheet.
        var isSplit: Bool
    }
    
    
    /// Allocates and initializes memory for `count` values.
    private static func allocate<Element>(_ count: Int, _ value: Element) -> UnsafeMutablePointer<Element> {
        let pointer = UnsafeMutablePointer<Element>.allocate(capacity: Swift.max(count, 1))
        pointer.initialize(repeating: value, count: count)
        return pointer
    }
    
}
