Read, write and analyze MIDI files, with a focus on piano performances and their transcriptions.

## Overview

MIDIKit is made of three libraries.

- **`MIDIKit`** is the faithful model of a MIDI file. A `MIDIContainer` holds `MIDITrack`s and a `MIDITempoTrack`, with their notes, sustains, channel events, meta events and raw data such as SysEx, and the time and key signatures. Files are read and written through CoreMIDI, with every time rounded to a grid of 9,600 ticks per quarter note, so that times never drift. `MIDIInputController` and `ScoreFollower` handle live MIDI input.
- **`IndexedTrack`** is the analysis layer. It merges a performance into one cleaned-up track at 120 BPM, then forms chords, finds downbeats and the key signature, normalizes note lengths, removes artifacts, aligns two performances with a `TimeWarp`, and transfers velocities from one to the other. An analysis profile tunes it for the transcriber that made the file: `.generic`, `.transkun` or `.pianoTranscription`.
- **`Intervals`** provides `Interval`, `DisjointIntervals` and `IntervalTree`, the interval queries the other two libraries build on.

## Getting Started

`MIDIKit` uses [Swift Package Manager](https://www.swift.org/documentation/package-manager/) as its build tool. To use it in your own project, add a `dependencies` clause to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Vaida12345/MIDIKit.git", from: "2.0.0")
]
```

Then add the libraries you need to your target dependencies:

```swift
.product(name: "MIDIKit", package: "MIDIKit"),
.product(name: "IndexedTrack", package: "MIDIKit"),
.product(name: "Intervals", package: "MIDIKit"),
```

No library re-exports another, so import each module where you use it.

MIDIKit supports macOS 15, iOS 18, watchOS 11, tvOS 18 and visionOS 2 or later.

### Using Xcode Package support

You can add this framework as a dependency to your Xcode project by clicking File -> Swift Packages -> Add Package Dependency. The package is located at:

```
https://github.com/Vaida12345/MIDIKit.git
```

## Examples

### Reading and writing

```swift
import MIDIKit

let container = try MIDIContainer(at: "/path/to/performance.mid")

for track in container.tracks {
    for note in track.notes {
        print(note.onset, note.offset, note.pitch, note.velocity)
    }
    print(track.sustains.count, "sustains")
}

// Move everything so that the first note starts at 0.
let trimmed = container.trimmingLeadingSilence()
try trimmed.write(to: "/path/to/trimmed.mid")
let data = try trimmed.data()
```

Times are in beats. Sustains keep every pedal change: when the pedal is lifted and pressed again, the earlier sustain ends a small gap before the next one starts, 1/128 beat by default, rather than merging the two into one long pedal.

```swift
let sustains = MIDISustainEvents([
    MIDISustainEvent(onset: 0, offset: 1),
    MIDISustainEvent(onset: 1, offset: 2), // lifted and pressed again at 1
])
// [0, 1 − 1/128] and [1, 2]
```

### Analyzing a performance

```swift
import MIDIKit
import IndexedTrack

// Merged into one track at 120 BPM, tuned for the output of Transkun.
let track = container.indexed(profile: .transkun)

for chord in track.chords {
    print(chord.leadingOnset, chord.map(\.pitch))
}

let downbeats = track.downbeats()
let keySignature = track.keySignature

let cleaned = track
    .removingArtifacts(threshold: 40)
    .normalizing(preserve: .acousticResult)
    .applyingGap()
try cleaned.makeContainer().write(to: "/path/to/cleaned.mid")
```

### Aligning two performances

```swift
// The warp maps the beats of the transcription to the beats of the score.
let warp = transcription.timeWarp(to: score)
let aligned = transcription.warped(by: warp)

// Gives the score the dynamics of the performance.
let expressive = score.applyingVelocities(from: transcription, warp: warp)
```

### Interval queries

```swift
import Intervals

let sustains = track.sustains
if let index = sustains.index(at: 12.5) {
    print("The pedal is down at beat 12.5, in", sustains[index])
}
let next = sustains.firstIndex(after: 12.5)
```

## Migrating from 1.x

| 1.x | 2.0 |
|---|---|
| `IndexedContainer`, `container.indexed()` | `IndexedTrack`, `container.indexed(profile:)` |
| `TranscriptionAlgorithm.transkun`, `.pianoTranscription` | the `.transkun` and `.pianoTranscription` analysis profiles |
| `VelocityProvider` | `IndexedTrack.applyingVelocities(from:warp:)` |
| `writeData(to:)` | `write(to:)` |

Sustains that touch or overlap are no longer kept as they are, nor merged into one: they stay apart at every pedal change, with a small gap. The release notes list every change.
