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


let date = Date()
let container = try await MIDIContainer(at: "/Users/vaida/Desktop/04 The Winter.mid").indexed()
//let reference = try await MIDIContainer(at: "/Users/vaida/Desktop/04 The Winter.mid").indexed()
//let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/1-61 Piano Sonata No. 14, _Moonlight__ I. Adagio sostenuto.mid")
//let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/Secret Base.mid")
//detailedPrint(chords)
//print(date.distanceToNow())
//try await container.normalize(preserve: .notesDisplay)
//var indexedContainer = indexed.makeContainer()
//flushAverage(container: indexed, track: &indexedContainer.tracks[0])
//try indexedContainer.write(to: .desktopDirectory/"file.mid")

//await container.align(to: reference)
//try container.makeContainer().write(to: .desktopDirectory/"file.mid")

let features = await container.keyFeatures()
var featureContainer = features.makeContainer()
let pivots = features.pivots()
//pivots.append(to: &featureContainer.tracks[0])
try featureContainer.write(to: .desktopDirectory/"file.mid")


//var result = MIDIContainer()
//var track = MIDITrack()
//for (offset, chord) in chords.enumerated() {
//    for note in chord {
//        track.notes.append(MIDINotes.Note(onset: note.onset, offset: note.offset, note: note.note, velocity: note.velocity, channel: note.channel))
//    }
//}
//flushAverage(container: indexed, track: &track)
//
//result.tracks.append(track)
//try result.write(to: .desktopDirectory/"file.mid")

print(date.distanceToNow())
