//
//  Measure.swift
//  MIDIKit
//
//  Created by Vaida on 9/5/24.
//

import DetailedDescription


/// A **measure** (or **bar**) is a segment of time in a piece of music that contains a specific number of beats, as defined by the **time signature**.
///
/// In CoreAudio, the time stamps are represented in `MusicTimeStamp`, measured in *beats*.
///
/// ## The Time Signature
///
/// The **numerator** indicates the number of *beats* per measure.
///
/// The **denominator** indicates *n*th note gets one *beat*.
///
/// For Example, a `4/4` indicates that there are 4 beats per measure, and each beat is a quarter note
public struct MIDIMeasure: Equatable, CustomDetailedStringConvertible {
    
    var notes: MIDINotes
    
    var sustains: MIDISustainEvents
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDIMeasure>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.notes)
            descriptor.sequence(for: \.sustains)
        }
    }
    
    public init(notes: MIDINotes = [], sustains: MIDISustainEvents = []) {
        self.notes = notes
        self.sustains = sustains
    }
    
}


extension Array where Element == MIDIMeasure {
    
    public func jointed() -> MIDIMeasure {
        self.reduce(into: MIDIMeasure()) {
            $0.notes.append(contentsOf: $1.notes)
            $0.sustains.append(contentsOf: $1.sustains)
        }
    }
    
}
