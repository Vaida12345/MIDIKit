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

let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/1-61 Piano Sonata No. 14, _Moonlight__ I. Adagio sostenuto.mid")
let date = Date()
var indexed = await container.indexed()
//let chords = Chord.makeChords(from: indexed)
//detailedPrint(chords)
//print(date.distanceToNow())
try await indexed.normalize()
print(date.distanceToNow())


//var result = MIDIContainer()
//var track = MIDITrack()
//for (offset, chord) in chords.enumerated() {
//    for note in chord {
//        track.notes.append(MIDINotes.Note(onset: note.onset, offset: note.offset, note: note.note, velocity: note.velocity, channel: UInt8(offset % 16)))
//    }
//}
//result.tracks.append(track)
try indexed.makeContainer().write(to: .desktopDirectory/"file.mid")
