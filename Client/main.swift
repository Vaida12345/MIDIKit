//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import MIDIKit
import AudioToolbox


let original = try MIDIContainer(at: URL(filePath: "/Users/vaida/Desktop/AoT Original.mid"))
let transcribed = try MIDIContainer(at: URL(filePath: "/Users/vaida/Desktop/tests/Attack on Titan Main Theme.mid"))

await print(original.tracks[0].notesDistance(to: transcribed.tracks[0]))
print(original.tracks[0].notes.count)
