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


//var container = try MIDIContainer(at: "/Users/vaida/Desktop/short.mid")
var container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/藤井風　きらり 钢琴翻弹.mid")
//var container = try MIDIContainer(at: "/Users/vaida/Desktop/MIDIs/Written Sagrada.mid")
//var container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/Ashes on The Fire - Shingeki no Kyojin.mid")

//container.tracks[0].notes = MIDINotes(notes: Array(container.tracks[0].notes[0..<16]))
//container.tracks[0].sustains = []

let min = container.tracks[0].notes.map(\.onset).min()!

container.tracks[0].notes.forEach { index, element in
    element.onset -= min
    element.offset -= min
}

let refereceNoteLength = container.tracks[0].notes.deriveReferenceNoteLength()
print(refereceNoteLength) //

let tempo = 120 * 1/4 / refereceNoteLength
container.applyTempo(tempo: tempo)

container.tracks[0].notes = container.tracks[0].notes.normalizedLengthByShrinkingKeepingOffsetInSameRegion(sustains: container.tracks[0].sustains)
detailedPrint(container.tracks[0].notes)

container.tracks[0].quantize(by: 1/4)
detailedPrint(container.tracks[0].notes)

for note in container.tracks[0].notes {
    assert(note.duration <= 10)
}

try container.writeData(to: "/Users/vaida/Desktop/MIDIs/normalized.mid")


/*
 Written
─notes: <16 elements>
 ├─[0]: Note(range: 0.00 - 0.24, note: 54, velocity: 80)
 ├─[1]: Note(range: 0.25 - 0.49, note: 61, velocity: 80)
 ├─[2]: Note(range: 0.50 - 0.74, note: 54, velocity: 80)
 ├─[3]: Note(range: 0.75 - 0.99, note: 61, velocity: 80)
 ├─[4]: Note(range: 1.00 - 1.24, note: 54, velocity: 80)
 ├─[5]: Note(range: 1.25 - 1.49, note: 61, velocity: 80)
 ├─[6]: Note(range: 1.50 - 1.74, note: 54, velocity: 80)
 ├─[7]: Note(range: 1.75 - 1.99, note: 61, velocity: 80)
 ├─[8]: Note(range: 2.00 - 2.24, note: 54, velocity: 80)
 ├─[9]: Note(range: 2.25 - 2.49, note: 61, velocity: 80)
 ├─[10]: Note(range: 2.50 - 2.74, note: 54, velocity: 80)
 ├─[11]: Note(range: 2.75 - 2.99, note: 61, velocity: 80)
 ├─[12]: Note(range: 3.00 - 3.24, note: 54, velocity: 80)
 ├─[13]: Note(range: 3.25 - 3.49, note: 62, velocity: 80)
 ├─[14]: Note(range: 3.50 - 3.74, note: 54, velocity: 80)
 ╰─[15]: Note(range: 3.75 - 3.99, note: 62, velocity: 80)
 
Raw
 notes: <16 elements>
 ├─[0]: Note(range: 0.00 - 0.89, note: 54, velocity: 40)
 ├─[1]: Note(range: 0.47 - 1.19, note: 61, velocity: 60)
 ├─[2]: Note(range: 0.91 - 1.59, note: 54, velocity: 49)
 ├─[3]: Note(range: 1.21 - 1.91, note: 61, velocity: 64)
 ├─[4]: Note(range: 1.61 - 2.25, note: 54, velocity: 59)
 ├─[5]: Note(range: 1.94 - 2.57, note: 61, velocity: 71)
 ├─[6]: Note(range: 2.28 - 2.93, note: 54, velocity: 71)
 ├─[7]: Note(range: 2.60 - 3.21, note: 61, velocity: 83)
 ├─[8]: Note(range: 2.96 - 3.63, note: 54, velocity: 73)
 ├─[9]: Note(range: 3.24 - 3.93, note: 61, velocity: 80)
 ├─[10]: Note(range: 3.66 - 4.33, note: 54, velocity: 71)
 ├─[11]: Note(range: 3.96 - 11.30, note: 61, velocity: 74)
 ├─[12]: Note(range: 4.35 - 5.13, note: 54, velocity: 70)
 ├─[13]: Note(range: 4.75 - 5.43, note: 62, velocity: 61)
 ├─[14]: Note(range: 5.14 - 5.81, note: 54, velocity: 65)
 ╰─[15]: Note(range: 5.45 - 6.15, note: 62, velocity: 66)
 
 Normalized
 notes: <16 elements>
 ├─[0]: Note(range: 0.00 - 0.63, note: 54, velocity: 40)
 ├─[1]: Note(range: 0.33 - 0.84, note: 61, velocity: 60)
 ├─[2]: Note(range: 0.64 - 1.12, note: 54, velocity: 49)
 ├─[3]: Note(range: 0.85 - 1.34, note: 61, velocity: 64)
 ├─[4]: Note(range: 1.13 - 1.58, note: 54, velocity: 59)
 ├─[5]: Note(range: 1.36 - 1.80, note: 61, velocity: 71)
 ├─[6]: Note(range: 1.60 - 2.06, note: 54, velocity: 71)
 ├─[7]: Note(range: 1.82 - 2.25, note: 61, velocity: 83)
 ├─[8]: Note(range: 2.07 - 2.55, note: 54, velocity: 73)
 ├─[9]: Note(range: 2.27 - 2.76, note: 61, velocity: 80)
 ├─[10]: Note(range: 2.57 - 3.04, note: 54, velocity: 71)
 ├─[11]: Note(range: 2.78 - 7.93, note: 61, velocity: 74)
 ├─[12]: Note(range: 3.06 - 3.60, note: 54, velocity: 70)
 ├─[13]: Note(range: 3.33 - 3.81, note: 62, velocity: 61)
 ├─[14]: Note(range: 3.61 - 4.08, note: 54, velocity: 65)
 ╰─[15]: Note(range: 3.82 - 4.32, note: 62, velocity: 66)
*/


//container.tracks[0].notes.drawDistanceDistribution()
