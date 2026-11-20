//
//  VelocityTransfer+Fill.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit
import Foundation


extension VelocityTransfer {
    
    /// Estimates the velocity of a note that has no partner in a performance, from the performance's notes around it.
    ///
    /// The estimate is the mean velocity of the performance's notes, weighted by a Gaussian of how far each is in time and in pitch, so a missing note of the melody takes after the melody around it rather than after the bass. As a transcriber misses mostly quiet notes, ``missedNoteOffset`` is subtracted.
    struct Fill {
        
        /// The notes of the performance, by key.
        let lanes: IndexedTrack.Lanes
        
        /// The median velocity of the performance, the last resort.
        let median: Double
        
        
        /// Creates the estimator for the given performance.
        ///
        /// - Complexity: O(*m*), where *m* is the number of notes of the performance, once its ``IndexedTrack/lanes`` exist.
        init(performance: IndexedTrack) {
            self.lanes = performance.lanes
            self.median = Self.median(of: performance.notes)
        }
        
        
        /// Returns the median velocity of `notes`: the middle value, or the mean of the two middle ones. `64` without notes.
        ///
        /// - Complexity: O(*n*), by a histogram of the velocities.
        static func median(of notes: [MIDINote]) -> Double {
            guard !notes.isEmpty else { return 64 }
            // `UInt8` can hold velocities above 127, so the histogram covers every value it can hold.
            var histogram = [Int](repeating: 0, count: Int(UInt8.max) &+ 1)
            for note in notes {
                histogram[Int(note.velocity)] &+= 1
            }
            
            // the values at the sorted positions `(count - 1) / 2` and `count / 2`
            let lowerRank = (notes.count &- 1) / 2
            let upperRank = notes.count / 2
            var lower = -1
            var upper = -1
            var seen = 0
            var velocity = 0
            while velocity < histogram.count {
                seen &+= histogram[velocity]
                if lower < 0 && seen > lowerRank { lower = velocity }
                if seen > upperRank { upper = velocity; break }
                velocity &+= 1
            }
            return Double(lower &+ upper) / 2
        }
        
        
        /// Returns the weighted mean velocity of the performance's notes around (`time`, `pitch`), or `nil` when none weighs in.
        ///
        /// Only the notes within three spreads count: keys within `3 * pitchScale` semitones, onsets within `3 * timeScale` beats.
        ///
        /// - Complexity: O(*k* log *m* + *w*), where *k* is the number of keys in reach, *m* the number of notes of the performance, and *w* the number of notes in reach.
        func estimate(time: Double, pitch: UInt8, timeScale: Double, pitchScale: Double) -> Double? {
            let pitchReach = Int((3 * pitchScale).rounded(.up))
            let lowestLane = Swift.max(0, Int(pitch) &- 21 &- pitchReach)
            let highestLane = Swift.min(87, Int(pitch) &- 21 &+ pitchReach)
            guard lowestLane <= highestLane else { return nil }
            let earliest = time - 3 * timeScale
            let latest = time + 3 * timeScale
            
            var totalWeight = 0.0
            var weightedSum = 0.0
            self.lanes.members.withUnsafeBufferPointer { members in
                self.lanes.notes.withUnsafeBufferPointer { notes in
                    var lane = lowestLane
                    while lane <= highestLane {
                        defer { lane &+= 1 }
                        var low = self.lanes.starts[lane]
                        var high = self.lanes.starts[lane &+ 1]
                        guard low < high else { continue }
                        
                        let semitones = Double(lane &- (Int(pitch) &- 21)) / pitchScale
                        let pitchWeight = exp(-0.5 * semitones * semitones)
                        
                        // the first note of the lane whose onset is not before `earliest`
                        let end = high
                        while low < high {
                            let middle = Int(UInt(bitPattern: low &+ high) >> 1)
                            if notes[members[middle]].onset < earliest { low = middle &+ 1 } else { high = middle }
                        }
                        
                        var position = low
                        while position < end {
                            let note = notes[members[position]]
                            if note.onset > latest { break }
                            let offset = (note.onset - time) / timeScale
                            let weight = pitchWeight * exp(-0.5 * offset * offset)
                            totalWeight += weight
                            weightedSum += weight * Double(note.velocity)
                            position &+= 1
                        }
                    }
                }
            }
            
            return totalWeight > VelocityTransfer.minimumWeight ? weightedSum / totalWeight : nil
        }
        
        
        /// Returns the velocity for a note at `time`, in the beats of the performance, on `pitch`, that has no partner.
        ///
        /// It is the estimate with ``timeScale`` and ``pitchScale``, or with both widened by ``fallbackFactor`` when no note is in reach, or the median velocity of the performance; less ``missedNoteOffset``, rounded, and kept within `1...127`.
        ///
        /// - Complexity: The complexity of ``estimate(time:pitch:timeScale:pitchScale:)``, twice at most.
        func velocity(time: Double, pitch: UInt8) -> UInt8 {
            let estimate = self.estimate(time: time, pitch: pitch, timeScale: VelocityTransfer.timeScale, pitchScale: VelocityTransfer.pitchScale)
                ?? self.estimate(time: time, pitch: pitch, timeScale: VelocityTransfer.timeScale * VelocityTransfer.fallbackFactor, pitchScale: VelocityTransfer.pitchScale * VelocityTransfer.fallbackFactor)
                ?? self.median
            let value = (estimate - VelocityTransfer.missedNoteOffset).rounded()
            return UInt8(Swift.min(127, Swift.max(1, value)))
        }
        
    }
    
}
