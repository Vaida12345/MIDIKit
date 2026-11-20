//
//  TimeWarp+Fit.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


extension TimeWarp {
    
    /// A time of the first track that is paired with a time of the second, and how much to trust the pair.
    struct Anchor: Sendable {
        
        /// The time in the first track, in beats.
        var source: Double
        
        /// The time in the second track, in beats.
        var target: Double
        
        /// How much the pair counts: the share of the keys of the two chords that they have in common.
        var weight: Double
    }
    
    /// Two sheet times closer than this are one time, in beats.
    static let mergeDistance = 1e-6
    
    /// The least slope of the fitted warp, so that it stays strictly increasing where the pairs stand still.
    static let minimumSlope = 0.02
    
    
    /// Returns the anchors of paired chords: the chord times, weighted by the Dice coefficient of the keys of the two chords.
    ///
    /// - Parameters:
    ///   - pairs: The paired chords.
    ///   - sheet: The events of the first track.
    ///   - performance: The events of the second track.
    ///
    /// - Complexity: O(*p*), where *p* is the number of pairs.
    static func anchors(of pairs: [Pair], sheet: Events, performance: Events) -> [Anchor] {
        var anchors: [Anchor] = []
        anchors.reserveCapacity(pairs.count)
        for pair in pairs {
            let i = Int(pair.sheet)
            let j = Int(pair.performance)
            let shared = Double(sheet.sharedCount(i, with: performance, j))
            let dice = 2 * shared / Double(sheet.sizes[i] + performance.sizes[j])
            anchors.append(Anchor(source: sheet.times[i], target: performance.times[j], weight: dice))
        }
        return anchors
    }
    
    
    /// Fits a warp to the anchors.
    ///
    /// The fit runs in four steps. Anchors at the same source time become one, at the mean of their targets weighted by their weights. A weighted isotonic regression, pooling adjacent violators, makes the targets non-decreasing, and a least slope makes them strictly increasing. Finally the Douglas-Peucker algorithm keeps the knots that are needed to stay within `tolerance` of those targets.
    ///
    /// No anchor is dropped as an outlier: the tempo of a real performance is jagged, and a test that tells a wrong pair from a genuine change of tempo removed more of the right pairs than it kept wrong ones out.
    ///
    /// - Parameters:
    ///   - anchors: The anchors, in any order.
    ///   - tolerance: The most that a knot may be left out and the warp stray from its anchor, in beats. `0` keeps every knot.
    ///
    /// - Returns: The warp, or `nil` if the anchors have fewer than two distinct source times.
    ///
    /// - Complexity: O(*a* log *a*) for sorting, then O(*a*) to merge and pool, and O(*a*²) in the worst case but O(*a* log *a*) typically for the simplification, where *a* is the number of anchors.
    static func fit(_ anchors: [Anchor], tolerance: Double) -> TimeWarp? {
        guard anchors.count >= 2 else { return nil }
        
        // The search returns the pairs in order, so sorting is rarely needed.
        var sorted = anchors
        var isSorted = true
        var index = 1
        while index < sorted.count {
            let previous = sorted[index &- 1]
            let current = sorted[index]
            isSorted = isSorted && (previous.source < current.source || (previous.source == current.source && previous.target <= current.target))
            index &+= 1
        }
        if !isSorted {
            sorted.sort { $0.source != $1.source ? $0.source < $1.source : $0.target < $1.target }
        }
        
        // Merge the anchors of one source time.
        var sources: [Double] = []
        var targets: [Double] = []
        var weights: [Double] = []
        sources.reserveCapacity(sorted.count)
        targets.reserveCapacity(sorted.count)
        weights.reserveCapacity(sorted.count)
        for anchor in sorted {
            let weight = Swift.max(anchor.weight, 1e-6)
            if let last = sources.last, anchor.source - last < Self.mergeDistance {
                let slot = sources.count &- 1
                let total = weights[slot] + weight
                targets[slot] = (targets[slot] * weights[slot] + anchor.target * weight) / total
                weights[slot] = total
            } else {
                sources.append(anchor.source)
                targets.append(anchor.target)
                weights.append(weight)
            }
        }
        guard sources.count >= 2 else { return nil }
        
        // Non-decreasing, then strictly increasing.
        var fitted = Self.isotonic(targets, weights: weights)
        index = 1
        while index < fitted.count {
            fitted[index] = Swift.max(fitted[index], fitted[index &- 1] + Self.minimumSlope * (sources[index] - sources[index &- 1]))
            index &+= 1
        }
        
        guard tolerance > 0, sources.count > 2 else {
            return TimeWarp(validated: zip(sources, fitted).map { Knot(source: $0, target: $1) })
        }
        
        let keep = Self.simplified(sources, fitted, tolerance: tolerance)
        var knots: [Knot] = []
        index = 0
        while index < sources.count {
            if keep[index] {
                knots.append(Knot(source: sources[index], target: fitted[index]))
            }
            index &+= 1
        }
        return TimeWarp(validated: knots)
    }
    
    
    /// Returns the weighted least squares fit of non-decreasing values, by pooling adjacent violators.
    ///
    /// - Parameters:
    ///   - values: The values to fit.
    ///   - weights: The weight of each value, which must be positive and as many as `values`.
    ///
    /// - Complexity: O(*n*), where *n* is the number of values.
    static func isotonic(_ values: [Double], weights: [Double]) -> [Double] {
        // The blocks of pooled values: the weighted sum, the weight and the number of values of each.
        var sums: [Double] = []
        var blockWeights: [Double] = []
        var counts: [Int] = []
        sums.reserveCapacity(values.count)
        blockWeights.reserveCapacity(values.count)
        counts.reserveCapacity(values.count)
        
        var index = 0
        while index < values.count {
            sums.append(values[index] * weights[index])
            blockWeights.append(weights[index])
            counts.append(1)
            while sums.count > 1 {
                let last = sums.count &- 1
                if sums[last &- 1] / blockWeights[last &- 1] <= sums[last] / blockWeights[last] { break }
                sums[last &- 1] += sums[last]
                blockWeights[last &- 1] += blockWeights[last]
                counts[last &- 1] &+= counts[last]
                sums.removeLast()
                blockWeights.removeLast()
                counts.removeLast()
            }
            index &+= 1
        }
        
        var result: [Double] = []
        result.reserveCapacity(values.count)
        var block = 0
        while block < sums.count {
            let value = sums[block] / blockWeights[block]
            var repeated = 0
            while repeated < counts[block] {
                result.append(value)
                repeated &+= 1
            }
            block &+= 1
        }
        return result
    }
    
    
    /// Returns which points to keep so that the polyline through them stays within `tolerance` of every point, by the Douglas-Peucker algorithm. The first and last point are always kept.
    ///
    /// - Parameters:
    ///   - xs: The strictly increasing coordinates, at least two.
    ///   - ys: The values.
    ///   - tolerance: The largest vertical distance of a left out point from the polyline.
    ///
    /// - Complexity: O(*n* log *n*) typically, and O(*n*²) in the worst case, where *n* is the number of points.
    static func simplified(_ xs: [Double], _ ys: [Double], tolerance: Double) -> [Bool] {
        let count = xs.count
        var keep = [Bool](repeating: false, count: count)
        keep[0] = true
        keep[count &- 1] = true
        
        var stack = [(0, count &- 1)]
        while let (left, right) = stack.popLast() {
            if right &- left < 2 { continue }
            let slope = (ys[right] - ys[left]) / (xs[right] - xs[left])
            var farthest = -1
            var deviation = 0.0
            var index = left &+ 1
            while index < right {
                let distance = abs(ys[index] - (ys[left] + slope * (xs[index] - xs[left])))
                if distance > deviation {
                    deviation = distance
                    farthest = index
                }
                index &+= 1
            }
            if deviation > tolerance, farthest >= 0 {
                keep[farthest] = true
                stack.append((left, farthest))
                stack.append((farthest, right))
            }
        }
        return keep
    }
    
}
