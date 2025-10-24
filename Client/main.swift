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

//let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/Nuvole Bianche.mid'")
let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/Ashes on The Fire - Shingeki no Kyojin.mid")
//let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/桜廻廊.mid")

var indexed = container.indexed()

//let regions = indexed.regions()
//for (i, region) in regions.enumerated() {
//    for note in region.notes {
//        note.channel = UInt8(i % 16)
//    }
//}
await indexed.splitStaves()
await indexed.normalize(preserve: .notesDisplay)

DebugView(container: indexed).render(to: .desktopDirectory/"debug.pdf", format: .pdf, scale: 1)
#endif
