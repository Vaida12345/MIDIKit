//
//  Interval.swift
//  MIDIKit
//
//  Created by Vaida on 1/3/25.
//

public protocol Interval {
    
    var onset: Double { get }
    
    var offset: Double { get }
    
}


extension Interval {
    
    @inlinable
    public var duration: Double { offset - onset }
    
}


extension Range<Double>: Interval {
    
    @inlinable
    public var onset: Double {
        self.lowerBound
    }
    
    @inlinable
    public var offset: Double {
        self.lowerBound
    }
    
}
