//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import MIDIKit
import AudioToolbox


var container = try MIDIContainer(at: URL(filePath: "/Users/vaida/Music/Piano Transcription/Ashes on The Fire - Shingeki no Kyojin.mid"))

container.tracks[0].quantize(by: 1/16)
container.tracks[0].notes = container.tracks[0].notes.normalizedLengthByShrinkingKeepingOffsetInSameRegion(sustains: container.tracks[0].sustains)

try container.writeData(to: URL.desktopDirectory.appending(path: "file.mid"))
