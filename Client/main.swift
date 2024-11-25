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


var container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/1-61 Piano Sonata No. 14, _Moonlight__ I. Adagio sostenuto (edited).mid")
try await container.export(
    to: .desktopDirectory.appending(path: "file.wav")
)
