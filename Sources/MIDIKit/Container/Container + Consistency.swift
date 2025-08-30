//
//  Container + Consistency.swift
//  MIDIKit
//
//  Created by Vaida on 2025-08-28.
//

import OSLog


extension MIDIContainer {
    
    /// Checks consistency.
    ///
    /// This function essentially checks and ensures consistency across file IOs.
    ///
    /// This function checks for the note pitch, velocity, and no overlapping.
    ///
    /// - Returns: Whether the check passes.
    @discardableResult
    public func _checkConsistency() -> Bool {
        let logger = Logger(subsystem: "MIDIKit", category: "Consistency")
        var passed = true
        
        for track in self.tracks {
            for note in track.notes {
                if note.pitch < 21 || note.pitch > 108 {
                    logger.warning("You initialized a MIDI note \(note) with pitch outside acceptable range (21...108). CoreMIDI may choose to ignore this note on IO.")
                    passed = false
                }
                if note.velocity == 0 {
                    logger.warning("You initialized a MIDI note \(note) with velocity zero. CoreMIDI may choose to ignore this note on IO.")
                    passed = false
                }
                if note.duration <= 0 {
                    logger.warning("You initialized a MIDI note \(note) with invalid duration. CoreMIDI may choose to ignore this note on IO.")
                    passed = false
                }
            }
            
            if track.sustains.contents != track.sustains.sorted() {
                logger.warning("The sustain events are not sorted.")
                passed = false
            }
            
            var sustainIterator = track.sustains.makeIterator()
            var _curr = sustainIterator.next()
            var _next = sustainIterator.next()
            
            while let curr = _curr {
                guard let next = _next else { break }
                defer { _curr = next; _next = sustainIterator.next() }
                
                if curr.offset >= next.onset {
                    logger.warning("You initialized a MIDI sustain \(curr) that overlaps with others. CoreMIDI may produce sustains with incorrect lengths.")
                    passed = false
                }
            }
        }
        
        // MARK: - no note overlapping
        let contents: UnsafeMutableBufferPointer<MIDINote>
        defer { contents.deallocate() }
        
        if self.tracks.count == 1,
           let track = self.tracks.first {
            var notes = track.notes.contents
            notes.sort { $0.onset < $1.onset }
            contents = .allocate(capacity: notes.count)
            memcpy(contents.baseAddress!, &notes, MemoryLayout<MIDINote>.stride * notes.count)
        } else {
            var notes = self.tracks.flatMap(\.notes)
            notes.sort { $0.onset < $1.onset }
            contents = .allocate(capacity: notes.count)
            memcpy(contents.baseAddress!, &notes, MemoryLayout<MIDINote>.stride * notes.count)
        }
        
        // construct grouped
        var grouped: [UInt8 : [ReferenceNote]] = [:]
        contents.forEach { index, element in
            grouped[element.note, default: []].append(contents.baseAddress! + index)
        }
        
        // construct dictionary
        var index = 0 as UInt8
        while index <= 108 {
            defer { index &+= 1 }
            guard let contents = grouped[index] else { continue }
            var i = 0
            while i < contents.count - 1 {
                // overlapping?
                if contents[i].offset >= contents[i + 1].onset {
                    func description(_ note: ReferenceNote) -> String {
                        "\(note.onset.formatted(.number.precision(.fractionLength(2)))) - \(note.offset.formatted(.number.precision(.fractionLength(2))))"
                    }
                    
                    logger.warning(
                       """
                       You initialized a MIDI event that overlaps with others. CoreMIDI may produce notes with incorrect lengths.
                       \(MIDINote.description(for: contents[i].note))(note: \(contents[i].note), range: \(description(contents[i])) and \(description(contents[i + 1])))
                       """
                    )
                    passed = false
                }
                i &+= 1
            }
        }
        
        return passed
    }
    
}
