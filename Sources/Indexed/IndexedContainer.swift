//
//  IndexedContainer.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Essentials
import ConcurrentStream


/// Container supporting efficient lookup.
public struct IndexedContainer {
    
    /// The notes grouped by the key.
    ///
    /// Key: 21...108
    public let notes: [UInt8 : SingleNotes]
    
    /// The sorted notes.
    ///
    /// The `combinedNotes` and `notes` share the same reference.
    public let combinedNotes: CombinedNotes
    
    /// The sustain events.
    public let sustains: MIDISustainEvents
    
    /// The running average.
    public let average: RunningAverage
    
    /// The stored parameter for methods that returns a new ``IndexedContainer``.
    internal let parameters: Parameters
    
    
    /// Converts the indexed container back to ``MIDIContainer``.
    public func makeContainer() -> MIDIContainer {
        let track = MIDITrack(notes: MIDINotes(notes: self.combinedNotes.map(\.content)), sustains: self.sustains)
        return MIDIContainer(tracks: [track])
    }
    
    
    /// - Parameters:
    ///   - notes: The source notes. The notes are referenced and not copied. The other properties will be calculated accordingly.
    ///   - sustains: The source sustain events.
    ///   - runningLength: The length for calculating the running average. The default value is `4` beats, that is one measure in a 4/4 sheet.
    ///
    /// Any methods that returns a new ``IndexedContainer`` will use the parameters set in the initializer.
    public init(
        notes: [UInt8 : SingleNotes],
        sustains: MIDISustainEvents,
        runningLength: Double = 4
    ) async {
        self.notes = notes
        self.sustains = sustains
        self.combinedNotes = CombinedNotes(contents: notes.values.flatten().sorted(on: \.onset, by: <))
        
        let average = await RunningAverage(combinedNotes: combinedNotes, runningLength: runningLength)
        self.average = average
        self.parameters = Parameters(runningLength: runningLength)
    }
    
    /// - Parameters:
    ///   - container: The source container.
    ///   - minimumConsecutiveNotesGap: The minimum gap between two consecutive notes. The default value is `1/128`. The minimum length of individual note from La campanella in G-Sharp Minor by Lang Lang is 0.013 beat, which is around 1/64 beat.
    ///   - runningLength: The length for calculating the running average. The default value is `4` beats, that is one measure in a 4/4 sheet.
    ///
    /// Any methods that returns a new ``IndexedContainer`` will use the parameters set in the initializer.
    public init(
        container: MIDIContainer,
        minimumConsecutiveNotesGap: Double = 1/128,
        runningLength: Double = 4
    ) async {
        self.sustains = MIDISustainEvents(sustains: container.tracks.flatMap(\.sustains))
        
        let notes = container.tracks.flatMap(\.notes).map(ReferenceNote.init)
        let combinedNotes = CombinedNotes(contents: notes.sorted(by: { $0.onset < $1.onset }))
        async let average = await RunningAverage(combinedNotes: combinedNotes, runningLength: runningLength)
        
        let grouped = Dictionary(grouping: notes, by: \.note)
        
        var dictionary: [UInt8 : SingleNotes] = [:]
        dictionary.reserveCapacity(88)
        for i in 21...108 {
            guard let contents = grouped[UInt8(i)]?.sorted(by: { $0.onset < $1.onset }) else { continue }
            for i in 0..<contents.count {
                // ensures non-overlapping
                if i > contents.count - 1 {
                    contents[i].offset = min(contents[i].offset, contents[i + 1].onset - minimumConsecutiveNotesGap)
                }
            }
            
            dictionary[UInt8(i)] = SingleNotes(contents)
        }
        
        self.notes = dictionary
        self.combinedNotes = combinedNotes
        self.average = await average
        self.parameters = Parameters(runningLength: runningLength)
    }
    
    
    /// The stored parameter for methods that returns a new ``IndexedContainer``.
    struct Parameters {
        
        let runningLength: Double
        
    }
    
}


extension MIDIContainer {
    
    /// Converts the container to ``IndexedContainer``.
    ///
    /// - Parameters:
    ///   - minimumConsecutiveNotesGap: The minimum gap between two consecutive notes. The default value is `1/128`. The minimum length of individual note from La campanella in G-Sharp Minor by Lang Lang is 0.013 beat, which is around 1/64 beat.
    ///   - runningLength: The length for calculating the running average. The default value is `4` beats, that is one measure in a 4/4 sheet.
    ///
    /// Any methods that returns a new ``IndexedContainer`` will use the parameters set in the initializer.
    public func indexed(
        minimumConsecutiveNotesGap: Double = 1/128,
        runningLength: Double = 4
    ) async -> IndexedContainer {
        await IndexedContainer(
            container: self,
            minimumConsecutiveNotesGap: minimumConsecutiveNotesGap,
            runningLength: runningLength
        )
    }
    
}
