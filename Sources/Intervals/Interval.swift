//
//  Interval.swift
//  MIDIKit
//
//  Created by Vaida on 1/3/25.
//

public protocol Interval: Comparable {
    
    var onset: Double { get }
    
    var offset: Double { get }
    
}


extension Interval {
    
    @inlinable
    public var duration: Double { offset - onset }
    
    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.onset < rhs.onset
    }
    
}


extension Range<Double>: Interval, @retroactive Comparable {
    
    @inlinable
    public var onset: Double {
        self.lowerBound
    }
    
    @inlinable
    public var offset: Double {
        self.lowerBound
    }
    
}
