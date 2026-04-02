//
//  VelocityProvider.swift
//  MIDIKit
//
//  Created by Vaida on 2026-04-02.
//


extension IndexedContainer {
    
    /// Use this to cache & infer velocity for a pitch & onset.
    public struct VelocityProvider {
        
        // 88
        let full: [UInt8 : [VelocityDataPoint]]
        
        // 12
        let chroma: [UInt8 : [VelocityDataPoint]]
        
        let single: [VelocityDataPoint]
        
        
        /// Returns the most appropriate velocity at the given time and pitch.
        ///
        /// - Returns: `0` if source is empty.
        public func inferVelocity(pitch: UInt8, onset: Double, tolerance: Double = 0.2) -> UInt8 {
            // lookup full
            if let sequence = full[pitch], !sequence.isEmpty {
                if let lastBefore = sequence.last(before: onset),
                   onset - lastBefore.offset < tolerance {
                    // found
                    return lastBefore.velocity
                } else if let firstAfter = sequence.first(after: onset),
                          firstAfter.onset - onset < tolerance {
                    return firstAfter.velocity
                }
            }
            
            // lookup chroma
            if let sequence = chroma[pitch % 12], !sequence.isEmpty {
                if let lastBefore = sequence.last(before: onset),
                   onset - lastBefore.offset < tolerance {
                    // found
                    return lastBefore.velocity
                } else if let firstAfter = sequence.first(after: onset),
                          firstAfter.onset - onset < tolerance {
                    return firstAfter.velocity
                }
            }
            
            // use global value
            if let lastBefore = single.last(before: onset),
               onset - lastBefore.offset < tolerance {
                // found
                return lastBefore.velocity
            } else if let firstAfter = single.first(after: onset),
                      firstAfter.onset - onset < tolerance {
                return firstAfter.velocity
            }
            
            // still no? Just use previous value
            return single.last(before: onset)?.velocity ?? single.last?.velocity ?? 0
        }
        
        
        @usableFromInline
        struct VelocityDataPoint: Interval {
            @inlinable
            var offset: Double {
                onset + duration
            }
            
            @usableFromInline
            let onset: Double
            @usableFromInline
            let duration: Double
            @usableFromInline
            let velocity: UInt8
        }
    }
    
    /// Use this to cache & infer velocity for a pitch & onset.
    public func makeVelocityProvider() -> IndexedContainer.VelocityProvider {
        let full = self.notes.mapValues { joints in
            joints.map({ VelocityProvider.VelocityDataPoint(onset: $0.onset, duration: $0.duration, velocity: $0.velocity) })
        }
        
        let chords = self.chords()
        var chroma: [UInt8 : [VelocityProvider.VelocityDataPoint]] = [:]
        chroma.reserveCapacity(12)
        
        for chord in chords {
            let groups = Dictionary(grouping: chord.contents, by: { $0.pitch % 12 })
            
            for (pitch, contents) in groups {
                chroma[pitch, default: []].append(VelocityProvider.VelocityDataPoint(onset: chord.leadingOnset, duration: chord.duration, velocity: UInt8(contents.mean(of: { Double($0.velocity) })!)))
            }
        }
        
        let single = chords.map { chord in
            VelocityProvider.VelocityDataPoint(onset: chord.leadingOnset, duration: chord.duration, velocity: UInt8(chord.mean(of: { Double($0.velocity) })!))
        }
        
        return IndexedContainer.VelocityProvider(full: full, chroma: chroma, single: single)
    }
    
}


extension Array where Element == IndexedContainer.VelocityProvider.VelocityDataPoint {
    
    /// Returns the first interval whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    func firstIndex(after timeStamp: Double) -> Index? {
        var left = 0
        var right = self.count
        
        while left < right {
            let mid = (left + right) / 2
            if self[mid].onset > timeStamp {
                right = mid
            } else {
                left = mid + 1
            }
        }
        
        // After the loop, 'left' is the index of the first element greater than the value, if it exists.
        // Check if 'left' is within bounds and return the element if it exists.
        if left < self.count {
            return left
        } else {
            return nil
        }
    }
    
    /// Returns the first interval whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    func first(after timeStamp: Double) -> Element? {
        self.firstIndex(after: timeStamp).map { self[$0] }
    }
    
    /// Returns the last interval whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    func lastIndex(before timeStamp: Double) -> Index? {
        var left = 0
        var right = self.count
        
        while left < right {
            let mid = (left + right) / 2
            if self[mid].offset < timeStamp {
                left = mid + 1
            } else {
                right = mid
            }
        }
        
        if left > 0 {
            return left - 1
        } else {
            return nil
        }
    }
    
    /// Returns the last interval whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    func last(before timeStamp: Double) -> Element? {
        self.lastIndex(before: timeStamp).map { self[$0] }
    }
    
}
