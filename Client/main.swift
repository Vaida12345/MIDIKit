//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import MIDIKit
import AudioToolbox


var container = try MIDIContainer(at: URL(filePath: "/Users/vaida/Music/Piano Transcription/Sagrada Reset/Rayons - Sagrada Reset - 16 regret - humiliation.mid"))

print("did start")
let (low, high) = container.tracks[0].notes.separate(clusteringThreshold: 1, tolerance: 1)
container.tracks.append(container.tracks[0])
container.tracks[0].notes = high
container.tracks[1].notes = low

try container.writeData(to: URL.desktopDirectory.appending(path: "file.mid"))
