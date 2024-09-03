//
//  Sustains.swift
//  MIDIKit
//
//  Created by Vaida on 9/3/24.
//

import Stratum
import OSLog


/// To support efficient lookup, the sustain events are always sorted.
public struct MIDISustainEvents: RandomAccessCollection, Sendable, Equatable {
    
    var sustains: [Element]
    
    public var startIndex: Int {
        self.sustains.startIndex
    }
    
    public var endIndex: Int {
        self.sustains.endIndex
    }
    
    public init(notes: [Element] = []) {
        self.sustains = notes.sorted(by: { $0.onset < $1.onset })
    }
    
    public subscript(position: Int) -> Element {
        get {
            self.sustains[position]
        }
        set {
            self.sustains[position] = newValue
        }
    }
    
    public typealias Index = Int
    
    public typealias Element = MIDISustainEvent
    
}


//func findInterval(for value: Double) -> String? {
//    var low = 0
//    var high = intervals.count - 1
//    
//    while low <= high {
//        let mid = (low + high) / 2
//        let interval = intervals[mid]
//        
//        if value >= interval.start && value < interval.end {
//            return interval.value
//        } else if value < interval.start {
//            high = mid - 1
//        } else {
//            low = mid + 1
//        }
//    }
//    
//    return nil
//    }
