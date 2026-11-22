# ``IndexedTrack``

Analyze piano performances and their transcriptions: chords, downbeats, key signatures, note lengths, alignment and dynamics.

## Overview

An ``IndexedTrack/IndexedTrack`` is a performance merged into one track, cleaned up, and indexed for analysis. Create one from a `MIDIContainer`, choosing the analysis profile that suits the transcriber that made the file:

```swift
import MIDIKit
import IndexedTrack

let container = try MIDIContainer(at: "/path/to/performance.mid")
let track = container.indexed(profile: .transkun)

let chords = track.chords
let downbeats = track.downbeats()
let keySignature = track.keySignature
```

Creating a track converts the container to a constant 120 BPM and merges its tracks. Notes outside the piano range, `21...108`, or with invalid times are dropped; two strikes of one key closer than the minimum gap, `1/128` beat by default, are merged; and every note ends before the next note on its key starts. Sustains are kept apart at every pedal change. See ``IndexedTrack/IndexedTrack/init(_:profile:minimumConsecutiveNotesGap:)`` for the rules.

A track never changes after it is created. The structures derived from its notes, the ``IndexedTrack/IndexedTrack/lanes``, ``IndexedTrack/IndexedTrack/chords`` and ``IndexedTrack/IndexedTrack/intervalTree``, are built the first time they are used and shared by every copy. Every transform returns a new track, and ``IndexedTrack/IndexedTrack/makeContainer()`` turns one back into a `MIDIContainer`, to write it to a file.

To write transforms of your own, outside this package, see <doc:WritingTransforms>. To move code from MIDIKit 1.x, see <doc:Migrating-to-MIDIKit-2.1.0>.

## Topics

### Essentials

- ``IndexedTrack/IndexedTrack``
- ``IndexedTrack/IndexedTrack/init(_:profile:minimumConsecutiveNotesGap:)``
- ``MIDIKit/MIDIContainer/indexed(profile:minimumConsecutiveNotesGap:)``
- ``IndexedTrack/IndexedTrack/makeContainer()``

### Notes, Lanes and Chords

- ``IndexedTrack/IndexedTrack/notes``
- ``IndexedTrack/IndexedTrack/lanes``
- ``IndexedTrack/IndexedTrack/Lanes``
- ``IndexedTrack/IndexedTrack/Lane``
- ``IndexedTrack/IndexedTrack/NoteIndices``
- ``IndexedTrack/IndexedTrack/chords``
- ``IndexedTrack/IndexedTrack/Chords``
- ``IndexedTrack/IndexedTrack/Chord``
- ``IndexedTrack/IndexedTrack/intervalTree``
- ``IndexedTrack/IndexedTrack/sustains``

### Analysis Profiles

- ``AnalysisProfile``
- ``GenericProfile``
- ``TranskunProfile``
- ``PianoTranscriptionProfile``
- ``ChordArbiter``
- ``DownbeatTracker``

### Analyses

- ``IndexedTrack/IndexedTrack/downbeats(prior:)``
- ``IndexedTrack/IndexedTrack/keySignature``
- ``IndexedTrack/IndexedTrack/storedKeySignature``
- ``IndexedTrack/IndexedTrack/estimateKeySignature()``

### Transforms

- ``IndexedTrack/IndexedTrack/applyingGap(ideal:minimumNoteLength:)``
- ``IndexedTrack/IndexedTrack/normalizing(preserve:)``
- ``IndexedTrack/IndexedTrack/PreserveSettings``
- ``IndexedTrack/IndexedTrack/removingArtifacts(threshold:proximityThreshold:)``
- ``IndexedTrack/IndexedTrack/mergingNotesInSameInterval(of:threshold:difference:)``

### Alignment and Dynamics

- ``TimeWarp``
- ``IndexedTrack/IndexedTrack/timeWarp(to:parameters:)``
- ``IndexedTrack/IndexedTrack/warped(by:minimumConsecutiveNotesGap:)``
- ``IndexedTrack/IndexedTrack/applyingVelocities(from:warp:)``

### Writing Your Own Transforms

- <doc:WritingTransforms>
- ``IndexedTrack/IndexedTrack/modifyingNotes(_:)``
- ``IndexedTrack/IndexedTrack/replacing(notes:sustains:)``
- ``IndexedTrack/IndexedTrack/Chords/Builder``

### Migration

- <doc:Migrating-to-MIDIKit-2.1.0>
