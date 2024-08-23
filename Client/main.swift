//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import MIDIKit
import AudioToolbox


var normalized = try MIDIContainer(at: URL(fileURLWithPath: "/Users/vaida/Desktop/ Regret : Humiliation.mid"))
var raw = try MIDIContainer(at: URL(fileURLWithPath: "/Users/vaida/Music/Piano Transcription/Sagrada Reset/Rayons - Sagrada Reset - 16 regret - humiliation.mid")).tracks[0]

for (index, note) in raw.notes.enumerated() {
    raw.notes[index].onset = timestampConvert(raw: note.onset)
    raw.notes[index].offset = timestampConvert(raw: note.offset)
}

let potentialMatches = raw.notes.sorted(by: { $0.onset < $1.onset })
let searchTolerance: Double = 5

// search for match
for (index, note) in normalized.tracks[0].notes.enumerated() {
    let _matches = potentialMatches.filter { _match in
        _match.onset > note.onset - searchTolerance &&
        _match.onset < note.onset + searchTolerance &&
        _match.note == note.note
    }
    
    guard let best = _matches.sorted(by: { abs($0.onset - note.onset) + abs($0.offset - note.offset) < abs($1.onset - note.onset) + abs($1.offset - note.offset) }).first else { continue }
    normalized.tracks[0].notes[index].velocity = best.velocity
}

normalized.writeData(to: URL(fileURLWithPath: "/Users/vaida/Desktop/result.mid"))
print(normalized)


func timestampConvert(raw: MusicTimeStamp) -> MusicTimeStamp {
    (raw - 1.5) / 284 * 200
}
