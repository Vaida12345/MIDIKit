//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

#if os(macOS)
import FinderItem
import Foundation
import MIDIKit
import DetailedDescription
import SwiftUI

//let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/14 Ballade No. 1 in G minor, Op. 23.mid'")
let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/Ashes on The Fire - Shingeki no Kyojin.mid'")
//let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/10 Clair de lune.mid'")
var indexed = container.indexed()
//indexed.alignFirstNoteToZero()
//indexed = indexed.removingArtifacts(threshold: 40)
let date = Date()
indexed.normalize(preserve: .acousticResult)
print(date.distanceToNow())
//
//try indexed.makeContainer().write(to: .desktopDirectory/"file.mid")

//try indexed.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")

indexed.assignHands()

//for chord in Chord.makeSingleHandedChords(from: indexed) {
//    if chord.features.contains(.preferLeftHand) {
//        for content in chord {
//            content.velocity = 0
//        }
//    } else if chord.features.contains(.preferRightHand) {
//        for content in chord {
//            content.velocity = 127
//        }
//    }
//}
DebugView(container: indexed).render(to: .desktopDirectory/"debug.pdf", format: .pdf, scale: 1)
//await DebugPointsPlot().render(to: .desktopDirectory/"points plot.pdf", format: .pdf, scale: 1)
#endif
