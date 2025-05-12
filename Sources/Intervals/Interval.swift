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
