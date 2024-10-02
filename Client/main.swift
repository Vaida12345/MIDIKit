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


var container = try MIDIContainer(at: "/Users/vaida/Desktop/Ashes on The Fire - Shingeki no Kyojin.mid")
detailedPrint(container)
