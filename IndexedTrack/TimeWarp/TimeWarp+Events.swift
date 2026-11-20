//
//  TimeWarp+Events.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


extension TimeWarp {
    
    /// The chords of a track as the flat arrays the search reads: for each chord its time, the keys it holds, and how many notes it has.
    ///
    /// The search compares the keys of two chords with the population count of a bit mask, so each chord keeps its 88 keys in two words.
    struct Events: Sendable {
        
        /// The time of each chord in beats: the median onset of its notes.
        var times: [Double]
        
        /// The keys `21...84` of each chord, one bit each, with the lowest key in the lowest bit.
        var low: [UInt64]
        
        /// The keys `85...108` of each chord, one bit each, with the lowest key in the lowest bit.
        var high: [UInt64]
        
        /// The number of notes of each chord.
        var sizes: [Float]
        
        /// The number of chords.
        var count: Int { self.times.count }
        
        
        /// Creates events from their arrays, which must have the same length.
        init(times: [Double], low: [UInt64], high: [UInt64], sizes: [Float]) {
            precondition(times.count == low.count && times.count == high.count && times.count == sizes.count, "The arrays must have the same length.")
            self.times = times
            self.low = low
            self.high = high
            self.sizes = sizes
        }
        
        /// Creates the events of the chords of a track.
        ///
        /// The time of a chord is the median onset of its notes: the onset of the middle note, or the mean of the two middle ones. It is steadier than the first onset when the notes of a chord are rolled, and than the mean when a transcriber adds a stray note.
        ///
        /// - Parameter track: The track whose ``IndexedTrack/chords`` are read.
        ///
        /// - Complexity: O(*n*), where *n* is the number of notes, in addition to forming the chords on first use.
        init(of track: IndexedTrack) {
            let chords = track.chords
            let count = chords.count
            var times = [Double](repeating: 0, count: count)
            var low = [UInt64](repeating: 0, count: count)
            var high = [UInt64](repeating: 0, count: count)
            var sizes = [Float](repeating: 0, count: count)
            
            track.notes.withUnsafeBufferPointer { notes in
                chords.members.withUnsafeBufferPointer { members in
                    chords.starts.withUnsafeBufferPointer { starts in
                        var chord = 0
                        while chord < count {
                            let start = starts[chord]
                            let end = starts[chord &+ 1]
                            let size = end &- start
                            
                            // One bit per key. The shifts do not mask their amount, so a key of the other word shifts out.
                            var lowKeys: UInt64 = 0
                            var highKeys: UInt64 = 0
                            var position = start
                            while position < end {
                                let bit = UInt64(truncatingIfNeeded: Int(notes[members[position]].pitch) &- 21)
                                lowKeys |= 1 << bit
                                highKeys |= 1 << (bit &- 64)
                                position &+= 1
                            }
                            
                            // The notes are sorted by onset, so the middle member has the median onset. For an odd size both indices are the same member.
                            let upperMiddle = start &+ size &>> 1
                            let lowerMiddle = upperMiddle &- (1 &- size & 1)
                            times[chord] = (notes[members[lowerMiddle]].onset + notes[members[upperMiddle]].onset) * 0.5
                            low[chord] = lowKeys
                            high[chord] = highKeys
                            sizes[chord] = Float(size)
                            chord &+= 1
                        }
                    }
                }
            }
            
            self.times = times
            self.low = low
            self.high = high
            self.sizes = sizes
        }
        
        
        /// Returns the number of keys that chord `index` of these events and chord `otherIndex` of `other` both hold.
        func sharedCount(_ index: Int, with other: Events, _ otherIndex: Int) -> Int {
            (self.low[index] & other.low[otherIndex]).nonzeroBitCount &+ (self.high[index] & other.high[otherIndex]).nonzeroBitCount
        }
        
        
        /// The arrays of events as buffers, for the loops that read them. They are valid in the closure of ``withUnsafeBuffers(_:)`` only.
        struct Buffers {
            
            /// See ``Events/times``.
            let times: UnsafeBufferPointer<Double>
            
            /// See ``Events/low``.
            let low: UnsafeBufferPointer<UInt64>
            
            /// See ``Events/high``.
            let high: UnsafeBufferPointer<UInt64>
            
            /// See ``Events/sizes``.
            let sizes: UnsafeBufferPointer<Float>
        }
        
        /// Calls `body` with the arrays of these events as buffers.
        ///
        /// - Parameter body: A closure that reads the buffers. They are not valid after it returns.
        ///
        /// - Complexity: O(1), in addition to `body`.
        func withUnsafeBuffers<Result>(_ body: (Buffers) throws -> Result) rethrows -> Result {
            try self.times.withUnsafeBufferPointer { times in
                try self.low.withUnsafeBufferPointer { low in
                    try self.high.withUnsafeBufferPointer { high in
                        try self.sizes.withUnsafeBufferPointer { sizes in
                            try body(Buffers(times: times, low: low, high: high, sizes: sizes))
                        }
                    }
                }
            }
        }
    }
    
}
