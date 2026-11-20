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
    /// This function checks the pitch, velocity and duration of every note, and that notes on the same key do not overlap. Sustains need no check, as ``MIDISustainEvents`` keeps them sorted and disjoint.
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
        }
        
        // MARK: - no note overlapping
        
        // The notes of every track, ordered by pitch and then onset, so that consecutive notes on a key are neighbors.
        var notes = self.tracks.flatMap(\.notes)
        notes.sort { $0.pitch < $1.pitch || ($0.pitch == $1.pitch && $0.onset < $1.onset) }
        
        func description(_ note: MIDINote) -> String {
            "\(note.onset.formatted(.number.precision(.fractionLength(2)))) - \(note.offset.formatted(.number.precision(.fractionLength(2))))"
        }
        
        var index = 1
        while index < notes.count {
            let previous = notes[index &- 1]
            let current = notes[index]
            if previous.pitch == current.pitch && previous.offset >= current.onset {
                logger.warning(
                   """
                   You initialized a MIDI event that overlaps with others. CoreMIDI may produce notes with incorrect lengths.
                   \(MIDINote.description(for: previous.pitch))(note: \(previous.pitch), range: \(description(previous)) and \(description(current)))
                   """
                )
                passed = false
            }
            index &+= 1
        }
        
        return passed
    }
    
}
