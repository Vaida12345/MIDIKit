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


var container = MIDIContainer()
var track = MIDITrack(notes: [MIDITrack.Note(onset: 0, offset: 1, note: 10, velocity: 10, channel: 0)])
container.tracks.append(track)

let exporter = MIDI2Exporter(container: container)
try exporter.makeData().write(to: FinderItem.desktopDirectory/"test.midi2")
