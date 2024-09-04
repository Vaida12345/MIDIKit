//
//  Sustains.swift
//  MIDIKit
//
//  Created by Vaida on 9/3/24.
//

import Stratum
import OSLog
import AudioToolbox


/// To support efficient lookup, the sustain events are always sorted.
public struct MIDISustainEvents: RandomAccessCollection, Sendable, Equatable {
    
    var sustains: [Element]
    
    public var startIndex: Int {
        self.sustains.startIndex
    }
    
    public var endIndex: Int {
        self.sustains.endIndex
    }
    
    public init(sustains: [Element] = []) {
        self.sustains = sustains.sorted(by: { $0.onset < $1.onset })
    }
    
    public subscript(position: Int) -> Element {
        get {
            self.sustains[position]
        }
        set {
            self.sustains[position] = newValue
        }
    }
    
    /// Returns the sustain at the given time stamp.
    ///
    /// This structure assumes that there are no overlapping timestamps.
    ///
    /// - Complexity: O(log *n*), binary search.
    public subscript(at timeStamp: MusicTimeStamp) -> Element? {
        var low = 0
        var high = self.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let interval = self[mid]
            
            if timeStamp >= interval.onset && timeStamp < interval.offset {
                return interval
            } else if timeStamp < interval.onset {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }
    
    public typealias Index = Int
    
    public typealias Element = MIDISustainEvent
    
}
