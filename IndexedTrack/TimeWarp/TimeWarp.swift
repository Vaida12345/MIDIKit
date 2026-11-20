//
//  TimeWarp.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


/// A monotone mapping from the times of one ``IndexedTrack`` to the times of another, as a piecewise linear function.
///
/// ``IndexedTrack/timeWarp(to:parameters:)`` estimates the warp between two tracks of the same piece, such as a sheet and a performance of it, and ``IndexedTrack/warped(by:minimumConsecutiveNotesGap:)`` applies it. All times are in beats at 120 BPM, like the times of an ``IndexedTrack``.
///
/// The warp is made of its ``knots``. Between two knots it is linear, and it is strictly increasing as a whole, so no two times map to the same time and the order of events never changes. Before the first knot and after the last, it continues with the slope of the nearest segment, limited to `0.3...3` so that the few chords at an end do not stretch or squeeze everything beyond them. A warp of a single knot continues with a slope of 1, which makes it a shift.
public struct TimeWarp: Sendable, Hashable {
    
    /// A point of the warp: `source` in the time of one track is `target` in the time of the other.
    public struct Knot: Sendable, Hashable, BitwiseCopyable {
        
        /// The time in the track the warp starts from, in beats at 120 BPM.
        public var source: Double
        
        /// The time in the track the warp leads to, in beats at 120 BPM.
        public var target: Double
        
        /// Creates a knot.
        ///
        /// - Parameters:
        ///   - source: The time in the track the warp starts from, in beats at 120 BPM.
        ///   - target: The time in the track the warp leads to, in beats at 120 BPM.
        public init(source: Double, target: Double) {
            self.source = source
            self.target = target
        }
    }
    
    
    /// The points the warp passes through, strictly increasing in both ``Knot/source`` and ``Knot/target``.
    public let knots: [Knot]
    
    
    /// The slopes the warp may continue with beyond its first and last knots.
    static let endSlopeRange: ClosedRange<Double> = 0.3...3
    
    
    /// The warp that changes no time.
    public static let identity = TimeWarp(validated: [Knot(source: 0, target: 0)])
    
    
    /// Creates a warp through the given knots.
    ///
    /// The result is `nil` if `knots` is empty, if a time is not finite, or if the sources or the targets do not strictly increase, as then the knots do not describe a monotone mapping.
    ///
    /// - Parameter knots: The knots, in order.
    ///
    /// - Complexity: O(*k*), where *k* is the number of knots.
    public init?(knots: [Knot]) {
        guard Self.isValid(knots) else { return nil }
        self.knots = knots
    }
    
    /// Creates a warp through knots that are already valid, without checking them in release builds.
    ///
    /// - Precondition: `knots` meet the requirements of ``init(knots:)``, checked with an `assert`.
    init(validated knots: [Knot]) {
        assert(Self.isValid(knots), "The knots must be non-empty, finite, and strictly increasing in both coordinates.")
        self.knots = knots
    }
    
    /// Returns whether the knots are non-empty, finite, and strictly increasing in both coordinates.
    ///
    /// - Complexity: O(*k*), where *k* is the number of knots.
    static func isValid(_ knots: [Knot]) -> Bool {
        guard let first = knots.first, first.source.isFinite, first.target.isFinite else { return false }
        var index = 1
        while index < knots.count {
            let previous = knots[index &- 1]
            let current = knots[index]
            guard current.source.isFinite, current.target.isFinite, previous.source < current.source, previous.target < current.target else { return false }
            index &+= 1
        }
        return true
    }
    
    
    /// Returns the time the warp leads to for a time.
    ///
    /// The result increases with `time`: for times at or between two knots it is interpolated linearly, and beyond the first and last knot the nearest segment's slope is continued, limited to `0.3...3`, or `1` for a single knot. A time that is not a number gives not a number.
    ///
    /// - Parameter time: The time to map, in beats at 120 BPM.
    ///
    /// - Returns: The mapped time, in beats at 120 BPM.
    ///
    /// - Complexity: O(log *k*), where *k* is the number of knots.
    public func map(_ time: Double) -> Double {
        self.knots.withUnsafeBufferPointer { knots in
            let count = knots.count
            
            // `after` is the number of knots that are not after `time`, found by bisection: the knots are sorted.
            var after = 0
            var upper = count
            while after < upper {
                let middle = after &+ (upper &- after) &>> 1
                if knots[middle].source <= time {
                    after = middle &+ 1
                } else {
                    upper = middle
                }
            }
            
            if after == 0 {
                // Before the first knot, or not a number.
                let first = knots[0]
                let slope = count == 1 ? 1 : Self.endSlope(from: first, to: knots[1])
                return first.target + slope * (time - first.source)
            } else if after == count {
                // At or after the last knot.
                let last = knots[count &- 1]
                let slope = count == 1 ? 1 : Self.endSlope(from: knots[count &- 2], to: last)
                return last.target + slope * (time - last.source)
            } else {
                // Inside a segment. The result is kept between the knots, as the rounding of the interpolation may leave it by one ulp.
                let lower = knots[after &- 1]
                let higher = knots[after]
                let fraction = (time - lower.source) / (higher.source - lower.source)
                return Swift.min(higher.target, Swift.max(lower.target, lower.target + (higher.target - lower.target) * fraction))
            }
        }
    }
    
    /// The slope of the segment between two knots, limited to ``endSlopeRange``.
    private static func endSlope(from lower: Knot, to higher: Knot) -> Double {
        Swift.min(Swift.max((higher.target - lower.target) / (higher.source - lower.source), Self.endSlopeRange.lowerBound), Self.endSlopeRange.upperBound)
    }
    
}
