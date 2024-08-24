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
container.tracks[0].quantize(by: 1/4)
print(container)

try container.writeData(to: .desktopDirectory.appending(path: "export.mid"))
