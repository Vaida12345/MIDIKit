# Writing Your Own Transforms

Change the notes of a track from your own package, the way the built-in transforms do.

## Overview

The transforms of this package, such as ``IndexedTrack/IndexedTrack/applyingGap(ideal:minimumNoteLength:)`` and ``IndexedTrack/IndexedTrack/normalizing(preserve:)``, find the notes to change through the lanes and chords of a track, edit a copy of its notes, and return a new track. Your own package can do the same with the public API:

- the ``IndexedTrack/IndexedTrack/Lane/noteIndices`` of each lane and the ``IndexedTrack/IndexedTrack/Chord/noteIndices`` of each chord, to find the notes;
- ``IndexedTrack/IndexedTrack/modifyingNotes(_:)``, to change the notes and return a new track;
- ``IndexedTrack/IndexedTrack/replacing(notes:sustains:)``, for changes that `modifyingNotes(_:)` doesn't allow.

### Positions and note indices

A lane or a chord is reached with two kinds of number:

- A **position** is where a note is within a lane, a chord or ``IndexedTrack/IndexedTrack/Chords``. Positions always start at 0, and run through `0..<count`.
- A **note index** is where a note is in ``IndexedTrack/IndexedTrack/notes``.

One rule keeps them apart: positions are always the subscripts of a lane, a chord and ``IndexedTrack/IndexedTrack/NoteIndices``, and note indices are only ever the elements of a `NoteIndices`. So for every position `p` of a lane:

```swift
track.notes[lane.noteIndices[p]] == lane[p]
```

Lanes and chords share their storage with the track, so creating one is cheap; the note indices are rebased so that their positions start at 0 all the same.

### Finding the notes

``IndexedTrack/IndexedTrack/lanes`` is a collection of the 88 lanes, indexed by key from 21 to 108, and each lane holds the notes of its key by onset. ``IndexedTrack/IndexedTrack/chords`` is a collection of chords, sorted by their first notes, and every note is in exactly one chord.

```swift
for lane in track.lanes {
    for index in lane.noteIndices {
        let note = track.notes[index] // the notes of one key, by onset
    }
}

let middleC = track.lanes[60]
```

Both are computed on first use and then cached, so keep them in a local before a loop rather than accessing them again.

### Editing the notes in place

``IndexedTrack/IndexedTrack/modifyingNotes(_:)`` gives a closure a copy of the notes to edit, and returns a track with the edited notes:

```swift
// End each note an eighth of a beat before the next note on its key, but keep it at least 1/128 beat long.
let lanes = track.lanes
let gapped = track.modifyingNotes { notes in
    for lane in lanes {
        for (current, next) in zip(lane.noteIndices, lane.noteIndices.dropFirst()) {
            notes[current].offset = min(notes[current].offset, max(notes[next].onset - 1/8, notes[current].onset + 1/128))
        }
    }
}
```

That is ``IndexedTrack/IndexedTrack/applyingGap(ideal:minimumNoteLength:)``, written outside the package. A transform by chord looks the same:

```swift
// End every note by the onset of the next chord.
let chords = track.chords
let clamped = track.modifyingNotes { notes in
    for (chord, next) in zip(chords, chords.dropFirst()) {
        for index in chord.noteIndices {
            notes[index].offset = max(notes[index].onset, min(notes[index].offset, next.leadingOnset))
        }
    }
}
```

The closure may change the offsets, velocities, release velocities and channels of the notes. It must not change the number of notes, their onsets or their keys, and each note must still end after it starts, and before the next note on its key starts. These rules keep the order of the notes and their lanes valid, so the new track reuses the layout of the lanes and needs no cleanup.

> Important: The rules are checked with an `assert`, so only debug builds catch a mistake. In a release build, a broken rule leaves a track whose analyses read the wrong notes.

The new track keeps the sustains, channel events, meta events, raw data and ``IndexedTrack/IndexedTrack/profile`` of the old one. Its chords are formed again from the new notes the first time they are used, as they may depend on offsets and velocities.

`modifyingNotes(_:)` copies the notes once, which takes a few microseconds for tens of thousands of notes; the closure's own work is usually larger.

### Moving, adding or removing notes

To move onsets, change keys, or add or remove notes, use ``IndexedTrack/IndexedTrack/replacing(notes:sustains:)``. It returns the track as a `MIDIContainer` with the given notes or sustains in place of its own, exactly as given, and keeps every other event. Index the result to clean the notes up and analyze them again:

```swift
// Move every note a sixteenth of a beat later.
let later = track.notes.map { note in
    var note = note
    note.onset += 1/16
    note.offset += 1/16
    return note
}
let moved = track.replacing(notes: later).indexed(profile: track.profile)
```

A track doesn't store the minimum gap it was created with. If you created it with another gap than the default, pass that gap to `indexed(profile:minimumConsecutiveNotesGap:)` again, as for ``IndexedTrack/IndexedTrack/warped(by:minimumConsecutiveNotesGap:)``.

### Forming chords of your own

An analysis profile decides how the chords of a track are formed. To use your own rules, conform to ``AnalysisProfile`` and build the chords with ``IndexedTrack/IndexedTrack/Chords/Builder``:

```swift
/// Puts every note in a chord of its own.
struct SingleNoteProfile: AnalysisProfile {
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        var builder = IndexedTrack.Chords.Builder(for: track)
        for index in track.notes.indices {
            builder.append(CollectionOfOne(index))
        }
        return builder.build()
    }
}

let separate = container.indexed(profile: SingleNoteProfile())
```

The chords must be appended in the order of their first notes, each with its note indices ascending, and together they must hold every note exactly once. ``IndexedTrack/IndexedTrack/Chords/Builder/build()`` checks this, and ``IndexedTrack/IndexedTrack/chords`` checks that the chords were formed for the track's own notes; both stop the program otherwise, in release builds too, as the analyses read notes through the chords.

A profile must be deterministic, as the chords are cached, and ``AnalysisProfile/formChords(in:)`` must not read `track.chords`, which would never return. ``ChordArbiter`` forms chords with constants of your choice, and its presets, ``ChordArbiter/generic``, ``ChordArbiter/transkun`` and ``ChordArbiter/pianoTranscription``, are a good place to start.
