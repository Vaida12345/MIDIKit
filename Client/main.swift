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
await indexed.alignFirstNoteToZero()
//indexed = indexed.removingArtifacts(threshold: 40)
let date = Date()
await indexed.normalize(preserve: .acousticResult)
print(date.distanceToNow())

try indexed.makeContainer().write(to: .desktopDirectory/"file.mid")

//try indexed.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")



#endif
