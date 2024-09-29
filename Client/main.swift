//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Stratum
import Foundation
import MIDIKit
import AudioToolbox
import DetailedDescription
import SwiftUI
import Charts
import Accelerate


//var container = try MIDIContainer(at: "/Users/vaida/Desktop/MIDIs/16 Regret : Humiliation.mid")
//
////// start by normalizing tempo
////let refereceNoteLength = container.tracks[0].notes.deriveReferenceNoteLength()
////
////let tempo = 120 * 1/4 / refereceNoteLength
////container.applyTempo(tempo: tempo)
////
////// deal with sustains
////let sustains = container.tracks[0].sustains
////
////detailedPrint(sustains)
////
////DistributionView(values: sustains.map(\.duration))
////    .frame(width: 800, height: 400)
////    .render(to: .desktopDirectory.appending(path: "distribution.pdf"))
//
//for note in container.tracks[0].notes[0..<16] {
//    print("MIDINote(onset: \(note.onset, format: .number.precision(.fractionLength(2))), offset: \(note.offset, format: .number.precision(.fractionLength(2))), note: \(note.note), velocity: \(note.velocity), channel: 0),")
//}


//StaffView(notes: MIDINotes.preview.map { StaffNote(note: $0) })
//    .render(to: .desktopDirectory.appending(path: "preview.pdf"))


var container = MIDIContainer()

var track = MIDITrack(notes: [], sustains: [])
track.notes = MIDINotes(notes: (1..<128).map({ MIDINote(onset: Double($0), offset: Double($0)+1, note: UInt8($0), velocity: 100, channel: 0) }))

container.tracks.append(track)
try container.writeData(to: .desktopDirectory.appending(path: "test.mid"))
