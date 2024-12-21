//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import FinderItem
import Foundation
import MIDIKit
import AudioToolbox
import DetailedDescription
import SwiftUI
import Charts
import Accelerate
import AVFAudio


//let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/1-61 Piano Sonata No. 14, _Moonlight__ I. Adagio sostenuto.mid")
let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/Secret Base.mid")
let date = Date()
var indexed = await container.indexed()
let chords = await Chord.makeChords(from: indexed)
//detailedPrint(chords)
//print(date.distanceToNow())
//try await indexed.normalize()
print(date.distanceToNow())
//try indexed.makeContainer().write(to: .desktopDirectory/"file.mid")




var result = MIDIContainer()
var track = MIDITrack()
for (offset, chord) in chords.enumerated() {
    for note in chord {
        track.notes.append(MIDINotes.Note(onset: note.onset, offset: note.offset, note: note.note, velocity: note.velocity, channel: note.channel))
    }
}
flushAverage(container: indexed, track: &track)

result.tracks.append(track)
try result.write(to: .desktopDirectory/"file.mid")

