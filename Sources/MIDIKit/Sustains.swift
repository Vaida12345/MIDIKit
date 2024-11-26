//
//  Sustains.swift
//  MIDIKit
//
//  Created by Vaida on 9/3/24.
//

import OSLog
import AudioToolbox
import DetailedDescription


/// To support efficient lookup, the sustain events are always sorted.
public struct MIDISustainEvents: RandomAccessCollection, Sendable, Equatable, ExpressibleByArrayLiteral, CustomDetailedStringConvertible {
    
    var sustains: [Element]
    
    public var startIndex: Int {
        self.sustains.startIndex
    }
    
    public var endIndex: Int {
        self.sustains.endIndex
    }
    
    /// Returns the first sustain whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func first(after timeStamp: MusicTimeStamp) -> Element? {
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
            return self[left]
        } else {
            return nil
        }
    }
    
    /// Returns the last sustain whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func last(before timeStamp: MusicTimeStamp) -> Element? {
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
            return self[left - 1]
        } else {
            return nil
        }
    }
    
    /// - Complexity: O(*n* log *n*), sorting.
    public mutating func append(contentsOf: MIDISustainEvents) {
        self.sustains.append(contentsOf: contentsOf.sustains)
        self.sustains.sort(by: { $0.onset < $1.onset })
    }
    
    /// - Complexity: O(*n* log *n*), sorting.
    public mutating func append(_ sustain: MIDISustainEvent) {
        self.sustains.append(sustain)
        self.sustains.sort(by: { $0.onset < $1.onset })
    }
    
    public mutating func forEach(body: (_ index: Index, _ element: inout Element) -> Void) {
        self.sustains.forEach(body: body)
    }
    
    public init(sustains: [Element] = []) {
        self.sustains = sustains.sorted(by: { $0.onset < $1.onset })
    }
    
    public init(arrayLiteral elements: Element...) {
        self.sustains = elements
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
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDISustainEvents>) -> any DescriptionBlockProtocol {
        descriptor.sequence("", of: self)
    }
    
}
