# Migrating to MIDIKit 2.1.0

Move a package or app from MIDIKit 1.x to 2.1.0, and review a migration for the changes a compiler won't find.

## Overview

This article lists what changed between MIDIKit 1.x and 2.1.0, how each 1.x API maps to 2.1.0, and, most importantly, the changes that still compile but behave differently. It is written for anyone migrating, and for reviewing how an integration moved. Read section 1, the silent behavior changes, first: those are the bugs a compiler will not find.

**Baseline.**
- 1.x is the last 1.x `main`, `aaec54b`. The tag `1.9.9` (`97406a2`) is a few commits earlier, and has no `TranscriptionAlgorithm` or `optimizeFor:` parameters yet.
- 2.0.0 is `4726df0`, and 2.0.1 (`e120f3a`) only adds `MIDINote.isBlack(_:)`.
- 2.1.0 adds the API for transforms written outside the package (section 2). Everything else in this article applies to 2.0.0 and 2.1.0 alike.

**Scope.** Three libraries ship: `MIDIKit` (the file model and live input), `IndexedTrack` (the analysis layer that replaces `IndexedContainer`) and `Intervals` (interval queries). `ScoreFollower` and `MIDIInputController` are unchanged, apart from `MIDIInputEvent` becoming plainly `Sendable`.

## 1. Silent behavior changes

Each item below compiles after a mechanical rename, yet gives a different result. For every one an integration touches, check that the new behavior is what the caller wants, and that the integration didn't just rename the call.

### 1.1 Velocity transfer: the receiver is flipped

- 1.x: `performance.applyVelocity(to: score)` **mutated `score`** (the argument), taking velocities from `performance` (the receiver).
- 2.x: `score.applyingVelocities(from: performance, warp:)` **returns a new track**: the receiver gets the velocities of the argument. See ``IndexedTrack/IndexedTrack/applyingVelocities(from:warp:)``.

A port that keeps the receiver, `performance.applyingVelocities(from: score)`, compiles and copies the sheet's meaningless velocities onto the performance. Check which track is the receiver, and that the result is used.

### 1.2 The time warp direction

`a.timeWarp(to: b)` returns the warp from the beats of `a` to the beats of `b`, the same direction as 1.x `a.timeWarp(other: b)`. Two places need the right direction:

- `a.warped(by: warp)` needs a warp **from `a`**: `a.warped(by: a.timeWarp(to: b))`.
- `score.applyingVelocities(from: performance, warp: warp)` needs a warp **from `score` to `performance`**: `score.timeWarp(to: performance)`. Passing `nil` computes exactly that.

> Warning: The README of 2.0.0 and 2.0.1 had this backwards in "Aligning two performances": it computed `transcription.timeWarp(to: score)` and passed it to `score.applyingVelocities(from: transcription, warp: warp)`. The README is fixed in 2.1.0. Don't accept code copied from the old example; the correct call is `score.applyingVelocities(from: transcription)`, or `score.applyingVelocities(from: transcription, warp: score.timeWarp(to: transcription))`.

### 1.3 Warping maps offsets, so durations change

1.x `projection(_:)` mapped each onset and **kept each duration**. ``IndexedTrack/IndexedTrack/warped(by:minimumConsecutiveNotesGap:)`` maps onsets **and** offsets, so note and sustain lengths stretch or shrink with the local tempo.

It also rebuilds the track as ``IndexedTrack/IndexedTrack/init(_:profile:minimumConsecutiveNotesGap:)`` does, with the `minimumConsecutiveNotesGap` it is given, `1/128` by default whatever gap the source track was created with:
- notes on one key whose onsets end up closer than the gap are merged, and a note that ends too close to the next on its key is shortened;
- sustains whose onsets end up closer than the gap merge, and every other sustain ends at least the gap before the next one;
- times the warp maps before 0, such as a time signature at 0 when the first paired chord moves earlier, move to 0.

If the caller relied on durations surviving the warp, or on a gap other than the default, flag it.

### 1.4 Value semantics: nothing mutates in place any more

`IndexedContainer` was a `final class`, and most of its operations mutated it: `applyGap`, `normalize`, `projection`, `alignFirstNoteToZero`, `applyVelocity(to:)`, `mergeNotesInSameInterval`, and even `removingArtifacts`, which also returned a container. ``IndexedTrack/IndexedTrack`` is an immutable `struct`, and every operation returns a new track.

- A call whose result is dropped does nothing. None of the transforms is `@discardableResult`, so treat every "result of call to … is unused" warning on `applyingGap`, `normalizing`, `removingArtifacts`, `warped`, `applyingVelocities` or `modifyingNotes` as a bug.
- Code that shared one `IndexedContainer` between several owners, and relied on seeing each other's mutations, now needs to pass the new track along explicitly.
- Writes through `ReferenceNote` (`note.velocity = …` on `container.notes[pitch]` or on a chord) are gone. In 2.1.0, edit offsets, velocities and channels with ``IndexedTrack/IndexedTrack/modifyingNotes(_:)``, finding the notes through `noteIndices`; move, add or remove notes with ``IndexedTrack/IndexedTrack/replacing(notes:sustains:)``, then index the result. See <doc:WritingTransforms>. In 2.0.0, edit a `MIDIContainer`, such as `track.makeContainer()`, and index it again.

### 1.5 Merging tracks no longer overwrites the channel

1.x `IndexedContainer` set every note's `channel` to its **track index modulo 16** whenever the container had more than one track, so code could tell the source track, such as the left and the right hand, from `note.channel`. 2.x keeps each note's **original** channel, and which track a note came from is lost. Any code that reads `channel` on the notes of an `IndexedTrack` built from a multi-track file, to recover the track, is wrong; it must use the `MIDIContainer`'s tracks instead.

### 1.6 Sustains are split at every pedal change

1.x kept `MIDISustainEvents` as given, only sorted, and `IndexedContainer` merged overlapping or touching sustains into one long pedal. In 2.x, `MIDISustainEvents` is always sorted and disjoint, with a gap at every pedal change:

- Two sustains whose onsets are closer than `minimumGap` (default `1/128` beat) merge.
- Otherwise each sustain ends at least `minimumGap` before the next one starts, and the later one is extended so that the pedal stays down as long as before. `[0, 1]` and `[1, 2]` become `[0, 1 − 1/128]` and `[1, 2]`.
- A gap under two ticks of `MIDIContainer.writeResolution` is raised to two ticks, so a written pedal up always comes before the next pedal down.
- Invalid sustains, non-finite or ending before they start, are dropped. Short ones are kept.

This happens in every initializer and `insert`, including `MIDITrack(notes:sustains:…)`, `MIDIContainer(notes:sustains:)` and file reading. `normalizeToConstantTempo` and `trimLeadingSilence` keep the spacing the sustains already have when it stays valid, and clean them up again otherwise. ``IndexedTrack/IndexedTrack/init(_:profile:minimumConsecutiveNotesGap:)`` uses its `minimumConsecutiveNotesGap` as the sustain gap.

Code that counted sustains, expected one merged pedal, or compared sustains to hand-built expectations will see different values. Normalizing, downbeats and playback now see every pedal change.

Also on reading: a pedal still down at the end of a track used to be dropped; it now ends at the end of the track.

### 1.7 IndexedTrack cleans up notes differently

| | 1.x `IndexedContainer` | 2.x `IndexedTrack` |
|---|---|---|
| Pitch outside `21...108` | clamped to 21 or 108 | dropped |
| Non-finite times, or offset before onset | kept | dropped |
| Two same-key onsets closer than the gap | the earlier note dropped, the later kept | merged: earlier onset, later offset, louder velocity |
| Note order | by onset; ties in no defined order | by (onset, pitch) |
| `channel` | track index when there are several tracks | original channel (see 1.5) |
| Channel and meta events | **not** rescaled to 120 BPM | rescaled to 120 BPM, sorted |
| Tempo track meta events (format-1 time and key signatures) | ignored | included in `metaEvents`, and put back in the tempo track by `makeContainer()` |
| Raw data (SysEx) | dropped | kept in `rawData`, written back by `makeContainer()` |
| `removingArtifacts` | dropped channel and meta events, and kept a ghost note that a later, unrelated quiet note on its key followed | keeps the events, and removes that ghost note as documented |

Note counts and positions can therefore differ slightly from 1.x for the same file. A test that pins exact counts from 1.x output may need new expectations; check that each new expectation was derived, not just pasted from the failing output.

### 1.8 The key signature is optional and prefers the stored one

- 1.x `keySignature(optimizeFor:)` returned a non-optional key signature, `.natural` when it found no evidence, and ignored any key signature stored in the file.
- 2.x ``IndexedTrack/IndexedTrack/keySignature`` is a property of type `MIDIKeySignature?`. It returns the first stored key-signature meta event unless that one is natural, and otherwise estimates one from the notes with a different method (Temperley's profiles, about 90% correct on ASAP against 75% before). It returns `nil` only when nothing is stored and the notes give no evidence: there are none, or every pitch class has the same weight.

Check every `?? .natural` or force unwrap the port added, and whether the caller wanted the estimate only (``IndexedTrack/IndexedTrack/estimateKeySignature()``, then `.signature`) or the stored one only (``IndexedTrack/IndexedTrack/storedKeySignature``).

### 1.9 Downbeats treat the prior differently, and infer the meter

1.x `downbeats(beatsPerMeasure:prior:optimizeFor:)` took a bar length, and kept `prior` as a **leading prefix** of known downbeats. 2.x ``IndexedTrack/IndexedTrack/downbeats(prior:)`` has no `beatsPerMeasure`: the tracker finds bars of 2, 3 or 4 beats, which may change within the piece, and a pickup.

Every finite, non-negative time in `prior` is kept at its exact time **wherever it falls**, and the bars around it are fitted to it. Two anchors less than `1e-9` beat apart count as one. An anchor beyond the end of the decoding is kept in the result without forcing a bar. The decoding ends at most two of the longest bars, 22.4 beats, after the last onset, so a note or pedal held far past the music no longer stretches it.

The result is strictly increasing times in beats at 120 BPM. A port that drops `beatsPerMeasure: 3` silently loses a hint that no longer exists; check that the caller doesn't depend on the meter being forced.

### 1.10 Note ordering is total

`<` used to compare onsets only. It now orders by onset, then pitch, offset, velocity, channel and release velocity, consistent with `==`. `sort()` on notes now puts notes with the same onset in pitch order, and `min()` and `max()` pick a defined note on ties. Code that relied on the input order of simultaneous notes surviving a sort changes.

### 1.11 Lanes trap outside the piano range

1.x `container.notes[pitch]` returned `nil` for a pitch with no notes, including any pitch outside `21...108`. 2.x `track.lanes[pitch]` returns an empty ``IndexedTrack/IndexedTrack/Lane`` for an empty key, but **traps**, with a precondition, for a pitch outside `21...108`. Check that a port iterating `0...127`, or passing an unchecked pitch, guards the range. In 2.1.0, `for lane in track.lanes` visits exactly the 88 keys.

### 1.12 Written files differ

- `MIDIContainer.writeResolution` is 9,600 ticks per quarter note, not 4,800, and every time is rounded to that grid before writing, so times no longer drift along the file. Notes and sustains last at least one tick, and notes keep their length to the tick even when longer than 512 beats.
- At the same tick, SysEx and channel events are written before notes, so a GM reset or a program change comes before the notes it sets up.
- SysEx (`rawData`) is now written; 1.x dropped it.
- Every channel voice message is now read and written back (program change, pitch bend, aftertouch, every controller), where 1.x read only control changes, dropped their channel, and wrote them all on channel 0 (shown as channel 1 in most software; see 10.1). A read-then-write round trip now keeps them.
- A file written from an `IndexedTrack`, through `makeContainer()`, keeps its time signature, in the tempo track.

Golden-file tests, file hashes and size checks need new references.

## 2. New in 2.1.0

2.1.0 lets code outside the package write transforms like the built-in ones. See <doc:WritingTransforms>.

| API | What it does |
|---|---|
| ``IndexedTrack/IndexedTrack/Lane/noteIndices``, ``IndexedTrack/IndexedTrack/Chord/noteIndices`` | the index in `track.notes` of each note of a lane or a chord, as a ``IndexedTrack/IndexedTrack/NoteIndices`` whose positions start at 0 |
| ``IndexedTrack/IndexedTrack/Lanes`` as a collection | `for lane in track.lanes` visits the 88 keys, `21...108`; `track.lanes[pitch]` is unchanged |
| ``IndexedTrack/IndexedTrack/modifyingNotes(_:)`` | returns a track whose notes a closure edited without changing their number, onsets or keys, checked with an `assert` |
| ``IndexedTrack/IndexedTrack/replacing(notes:sustains:)`` | returns the track's container with other notes or sustains, to index again |

None of these changes existing behavior.

## 3. Package and build

| Topic | 1.x | 2.x |
|---|---|---|
| `swift-tools-version` | 6.1 | 6.4: clients need a Swift 6.4 toolchain |
| Products | `MIDIKit` | `MIDIKit`, `IndexedTrack`, `Intervals` |
| Module layout | everything in `MIDIKit` | three modules; none re-exports another |
| Dependencies of `MIDIKit` | DetailedDescription, FinderItem, ConcurrentStream, NativeImage, Optimization, Essentials, ColorComponents | DetailedDescription, FinderItem, Optimization, Essentials, ColorComponents, Intervals |
| `Package.resolved` | committed | not tracked; it belongs to the client |
| Platforms | macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2 | unchanged |

What a client needs:

- **Products.** Add `.product(name: "IndexedTrack", package: "MIDIKit")` to every target that indexes or analyzes, and `.product(name: "Intervals", package: "MIDIKit")` to every target that names `Interval`, `DisjointIntervals` or `IntervalTree`, or calls their queries.
- **Imports.** `import IndexedTrack` in every file that uses `indexed(...)`, `IndexedTrack`, profiles, chords, downbeats, key estimation, the time warp or velocity transfer. ``MIDIKit/MIDIContainer/indexed(profile:minimumConsecutiveNotesGap:)`` lives in `IndexedTrack`, so without the import the error is "value of type `MIDIContainer` has no member `indexed`". `import Intervals` in files that name `Interval`, `DisjointIntervals` or `IntervalTree`. The queries themselves, such as `index(at:)` and `firstIndex(after:)` on `sustains` or a `Lane`, compile without it today, as MIDIKit imports `Intervals`; with the `MemberImportVisibility` upcoming feature turned on, they need the import too.
- **Transitive dependencies.** `MIDIKit` no longer depends on `ConcurrentStream` or `NativeImage`. A client that used their APIs without declaring them, which worked through MIDIKit, must now declare and import them itself.
- **Version requirement.** During integration a client may point at a branch or a revision. Before the integration merges, it should require `from: "2.0.0"`, or `from: "2.1.0"` for the API in section 2. Flag any branch or local-path dependency left in a `Package.swift` that is about to merge.
- **The module shares its name with a type.** In module `IndexedTrack`, the struct `IndexedTrack` shadows the module, so `IndexedTrack.TimeWarp` fails ("not a member type of struct `IndexedTrack.IndexedTrack`"). Use the plain name, or the module selector `IndexedTrack::TimeWarp` to disambiguate. Nested types such as `IndexedTrack.Chord` and `IndexedTrack.PreserveSettings` are real members and work as written.

## 4. IndexedContainer to IndexedTrack

``IndexedTrack/IndexedTrack`` is an immutable, `Sendable` struct. It holds the merged, cleaned-up notes at 120 BPM, its `profile`, and a cache of derived structures (`lanes`, `intervalTree`, `chords`) built on first use and shared by every copy. Workarounds for the old class not being `Sendable` (`nonisolated(unsafe)`, `@unchecked Sendable` wrappers, rebuilding inside each task) can go, though keeping them isn't a bug.

| 1.x | 2.x | Notes |
|---|---|---|
| `container.indexed(minimumConsecutiveNotesGap:)` | `container.indexed(profile:minimumConsecutiveNotesGap:)` | needs `import IndexedTrack`; `profile` defaults to `.generic` |
| `IndexedContainer(container:minimumConsecutiveNotesGap:)` | `IndexedTrack(_:profile:minimumConsecutiveNotesGap:)` | the container label is gone |
| `contents: UnsafeMutableBufferPointer<MIDINote>` | `notes: [MIDINote]` | immutable; sorted by (onset, pitch) |
| `for note in container` (`Sequence`), `count`, `isEmpty` | `track.notes`, `track.notes.count`, `track.notes.isEmpty` | `IndexedTrack` is not a collection |
| `notes: [UInt8: DisjointNotes]`, `notes[pitch]` | `lanes[pitch]` → `Lane` | `Lane` is a `RandomAccessCollection` of `MIDINote` conforming to `DisjointIntervals`; never `nil`, traps outside `21...108` (1.11); in 2.1.0, `lane.noteIndices` gives each note's index in `notes` |
| `OverlappingIntervals` queries on `contents` (`subscript(at:)`, `range(_:)`, `lastIndex(onsetBefore:)`) | `intervalTree`: `intervals(containing:)`, `intervals(overlapping:)`, `indices(containing:)`, `indices(overlapping:)`, `forEach(overlapping:_:)`, `forEachIndex(overlapping:_:)`, `overlaps(_:)` | results in onset order |
| `sustains: MIDISustainEvents` (settable) | `sustains: IndexedTrack.Sustains` (`let`; alias of `MIDISustainEvents`) | see 1.6 |
| `controlEvents: MIDIControlEvents` | `channelEvents: [MIDIChannelEvent]` | an array here, unlike `MIDITrack.channelEvents`; see 10.1 |
| `metaEvents` (settable) | `metaEvents` (`let`) | now includes the tempo track's meta events |
| none | `rawData: [MIDIRawData]` | |
| none | `profile: any AnalysisProfile` | see section 5 |
| `makeContainer()` | `makeContainer()` | one track, with an explicit 120 BPM tempo; carries raw data; puts the time signatures in the tempo track |
| `applyGap(ideal:minimumNoteLength:)` (mutating) | `applyingGap(ideal:minimumNoteLength:)` → `IndexedTrack` | the 1.x clamp could make a note overlap the next one or end before it starts; fixed, idempotent, never lengthens |
| `normalize(preserve:optimizeFor:)` (mutating) | `normalizing(preserve:)` → `IndexedTrack` | chords come from the profile; the final pass ends each note strictly before the next on its key |
| `IndexedContainer.PreserveSettings` | `IndexedTrack.PreserveSettings` | same cases and raw values; lost `description` and `localizedStringResource` (see 14) |
| `removingArtifacts(threshold:proximityThreshold:)` | same name → `IndexedTrack` | goes through the profile; keeps channel and meta events; see 1.7 |
| `alignFirstNoteToZero()` | `MIDIContainer.trimLeadingSilence()` / `trimmingLeadingSilence()`, before indexing | differs: a sustain held at the first note is clipped to 0 instead of dropped, earlier channel, meta and raw events move to 0 instead of being dropped, and the tempo in effect at the first note moves to 0 |
| `chords(optimizeFor:)` | `chords` (property) | see section 6 |
| `downbeats(beatsPerMeasure:prior:optimizeFor:)` | `downbeats(prior:)` | see 1.9 and section 8 |
| `keySignature(optimizeFor:)` | `keySignature` (property, optional) | see 1.8 and section 7 |
| `timeWarp(other:parameters:)` → `TimeWarpMapping` | `timeWarp(to:parameters:)` → `TimeWarp` | see section 9 |
| `projection(_:)` (mutating) | `warped(by:minimumConsecutiveNotesGap:)` → `IndexedTrack` | see 1.3 |
| `applyVelocity(to:)`, `makeVelocityProvider(optimizeFor:)`, `VelocityProvider.inferVelocity(pitch:onset:tolerance:)` | `applyingVelocities(from:warp:)` | receiver flipped (1.1); no per-note lookup any more |
| writing notes through `ReferenceNote` | `modifyingNotes(_:)`, `replacing(notes:sustains:)` (2.1.0) | see 1.4 and <doc:WritingTransforms> |

## 5. Analysis profiles replace TranscriptionAlgorithm

`TranscriptionAlgorithm?` was passed as `optimizeFor:` to each analysis. In 2.x the choice is made once, when the track is created, and every analysis asks the track's ``IndexedTrack/IndexedTrack/profile``.

| 1.x | 2.x |
|---|---|
| `optimizeFor: nil` | `profile: .generic` (``GenericProfile``), the default |
| `optimizeFor: .transkun` | `profile: .transkun` (``TranskunProfile``) |
| `optimizeFor: .pianoTranscription` | `profile: .pianoTranscription` (``PianoTranscriptionProfile``) |

What to check:

- **One profile per track.** A 1.x call site that passed different algorithms to different analyses of the same container now needs one track per profile.
- **Runtime choice.** `indexed(profile:)` takes `some AnalysisProfile`, and an existential opens implicitly, so this compiles:

  ```swift
  let profile: any AnalysisProfile = switch transcriber {
  case nil: GenericProfile()
  case .transkun: TranskunProfile()
  case .pianoTranscription: PianoTranscriptionProfile()
  }
  let track = container.indexed(profile: profile)
  ```

  Here `transcriber` is the client's own optional enum. `let p: any AnalysisProfile = .generic` compiles too.
- **Comparing profiles.** `profile` is `any AnalysisProfile`, which is not `Equatable`. Use `track.profile is TranskunProfile`.
- **A persisted or user-facing algorithm.** `TranscriptionAlgorithm` was `Codable`, `CaseIterable` and `RawRepresentable` (`"transkun"`, `"pianoTranscription"`). Profiles are none of these. A client that stored it, or listed it in a picker, needs its own enum with the **same raw values**, so stored values keep decoding, plus a mapping to a profile like the one above.
- **Custom profiles.** A client may conform to ``AnalysisProfile``.
  - `formChords(in:)` is required: use ``ChordArbiter`` with custom constants, or ``IndexedTrack/IndexedTrack/Chords/Builder``. `removingArtifacts(from:threshold:proximityThreshold:)` and `downbeats(in:prior:)` have defaults.
  - Each must be deterministic.
  - `formChords` must form the chords of the track it is given, not of a copy, and must not read `track.chords`, which would never return. `Chords.Builder.build()` and `chords` check the chords in release builds too, and stop the program when they are wrong.
  - `downbeats` must return strictly increasing times that include every valid `prior`.
  - Neither may read offsets the transcriber doesn't report faithfully. PianoTranscription offsets are not reliable, so a custom profile for its output must not use them for chords or downbeats.
- **Tuned constants are public.** ``ChordArbiter/generic``, ``ChordArbiter/transkun``, ``ChordArbiter/pianoTranscription`` and ``DownbeatTracker/generic``, ``DownbeatTracker/transkun``, ``DownbeatTracker/pianoTranscription`` can be used directly, for example in a custom profile. `ChordArbiter.transkun` was tuned again for Transkun 1.3.0, so its chords differ slightly from 1.x.

## 6. Chords

| 1.x | 2.x |
|---|---|
| `container.chords(optimizeFor:)` → `[Chord]` | `track.chords` → `IndexedTrack.Chords`, computed once and cached |
| `Chord.makeChords(from:spec:optimizeFor:)` | `track.chords`, or `profile.formChords(in: track)`, or `ChordArbiter.formChords(in:)` |
| `Chord.Spec()` / `Chord.Spec(duration:)` | none; a constant window needs a custom profile built with `Chords.Builder` |
| `Chord.makeSingleHandedChords(from:spec:optimizeFor:)` | none |
| `Chord` (element `ReferenceNote`, mutable) | `IndexedTrack.Chord` (element `MIDINote`, read-only); in 2.1.0, `chord.noteIndices` gives each note's index in `track.notes` |
| `Chord.init(contents:maxOffset:features:)` | `IndexedTrack.Chords.Builder(for:)`, `append(_:features:)` with note indices, `build()` |
| `leadingOnset`, `maxOffset`, `duration` | same |
| `pitchSpan: UInt8` | `pitchRange: ClosedRange<UInt8>`; the span is `upperBound - lowerBound` |
| `features` (`var`): `.glissando`, `.preferLeftHand`, `.preferRightHand` | `features` (`let`): `.glissando` only |
| `Chord: Hashable`, `CustomStringConvertible`, `DetailedStringConvertible` | none of these |
| `[Chord].firstIndex(after:)` | none; `chords` is sorted by `leadingOnset`, so use a binary search |

``IndexedTrack/IndexedTrack/Chords`` is a `RandomAccessCollection` but not an `Array`: code that appended to, sorted or stored chords as `[Chord]` needs `Array(track.chords)` or a rewrite. Chords can't be shown with `ForEach(…, id: \.self)` any more, since `Chord` is not `Hashable`; use the index. Every note is in exactly one chord.

## 7. Key signatures

`IndexedContainer.KeySignature` is replaced by `MIDIKeySignature` in `MIDIKit`, also available as `IndexedTrack.KeySignature`.

| 1.x `IndexedContainer.KeySignature` | 2.x `MIDIKeySignature` |
|---|---|
| `pitches: [Int]`, `accidental` (stored) | `sharps: Int` in `-7...7` (stored); `pitches` and `accidental` computed |
| `.natural`, `.sharps1` … `.sharps7`, `.flats1` … `.flats7` | `.natural`, `MIDIKeySignature(sharps: n)` with negative `n` for flats |
| `allCases` (`CaseIterable`), ordered flats1…flats7, natural, sharps1…sharps7 | none; `(-7...7).map(MIDIKeySignature.init(sharps:))` gives flats7…flats1, natural, sharps1…sharps7, so a picker or index built on the old order must not assume the same positions |
| `init?(accidental:accidentalCount:)` | `MIDIKeySignature(sharps: accidental.rawValue * count)` |
| `init(pitches:accidental:)` | none: any pitches were accepted before; only the 15 standard signatures exist now |
| none | `init(majorTonic:)`, `majorTonic`, `init?(_ event: MIDIMetaEvent)`, `description` (such as `2♭`) |
| `Accidental` (`flat = -1`, `neutral = 0`, `sharp = 1`) | same |

`IndexedTrack` adds ``IndexedTrack/IndexedTrack/keySignature`` (see 1.8), ``IndexedTrack/IndexedTrack/storedKeySignature``, and ``IndexedTrack/IndexedTrack/estimateKeySignature()``, which returns a `MIDIKeySignature.Estimate?` with `signature`, `correlation` and `margin`. The encoding changed; see section 14.

## 8. Downbeats

``IndexedTrack/IndexedTrack/downbeats(prior:)`` asks the profile, which uses a ``DownbeatTracker`` (``DownbeatTracker/generic``, ``DownbeatTracker/transkun`` or ``DownbeatTracker/pianoTranscription``). The tracker replaces the 1.x beam search, and on held-out ASAP pieces scores a downbeat F-measure of about 0.44 against 0.28 for 1.x on Transkun input. Expect different results from 1.x on most pieces; a test that pins 1.x downbeats needs new expectations. `baselineBarLength`, `localBarRegions` and `LocalBarRegion` are gone (section 12). Times are in beats at 120 BPM, as before.

A custom tracker's `beatFloor` and `beatRegionDivisor` are clamped to usable ranges, so a value of 0 or NaN no longer stops the program.

## 9. Time warp and velocity transfer

### Time warp

| 1.x | 2.x |
|---|---|
| `a.timeWarp(other: b, parameters:)` | `a.timeWarp(to: b, parameters:)` (same direction, `a` → `b`) |
| `IndexedContainer.TimeWarpMapping` | ``TimeWarp`` (`Hashable`, `Sendable`) |
| `TimeWarpMapping.map(_:)`, `.identity` | `TimeWarp.map(_:)`, `.identity` |
| none | `TimeWarp.knots: [TimeWarp.Knot]` (`source`, `target`), `TimeWarp(knots:)` (`nil` unless the knots are non-empty, finite, and strictly increasing in both source and target) |
| `IndexedContainer.TimeWarpParameters(epsilonA:…slopeMax:)`, all defaulted | `TimeWarp.Parameters`: entirely different fields, all required but `fitTolerance`; start from `.generic`, change fields on a copy, and check `isValid` |
| `a.projection(mapping)` (mutating, kept durations) | `a.warped(by: warp)` → new track (maps offsets; see 1.3) |

The algorithm is new, a tempo-state Viterbi search over chords followed by an isotonic fit, and reads onsets and keys only. There are no per-transcriber presets: `TimeWarp.Parameters.generic` suits every transcriber. 1.x parameter values don't carry over; flag any attempt to translate them field by field.

### Velocity transfer

`score.applyingVelocities(from: performance, warp: nil)` maps the score's onsets into the performance through `score.timeWarp(to: performance)`, or the given warp, pairs notes one to one per key within 0.15 beats, and fills unmatched notes from nearby performance velocities minus 15. Only velocities change. The receiver is the track that **receives** velocities (1.1). If the client also warps the score, it can compute the warp once and pass it to both `warped(by:)` and `applyingVelocities(from:warp:)`, as both want the score → performance direction.

There is no per-note `inferVelocity(pitch:onset:)` any more. A client that queried velocities for notes not in an `IndexedTrack` needs to build a track of them first, or the behavior must be reconsidered; flag any ad hoc reimplementation.

## 10. MIDIKit module changes

### 10.1 Control events become channel events

`MIDIControlEvent(s)` and `controlEvents` are replaced by `MIDIChannelEvent(s)` and `channelEvents`.

> Important: The 1.x type was mislabeled: `MIDIControlEvent.channel` held the **controller number**, `velocity` held the **value**, the real channel was dropped, and events were written on channel 0. A mechanical port of `MIDIControlEvent(onset: t, channel: 67, velocity: 127)` to `MIDIChannelEvent(onset: t, channel: 67, …)` is wrong, and asserts, as a channel is `0...15`.

```swift
// 1.x
MIDIControlEvent(onset: t, channel: 67, velocity: 127)   // soft pedal down
event.channel == 67                                      // "is this the soft pedal?"

// 2.x
MIDIChannelEvent(onset: t, channel: 0, message: .controlChange(controller: 67, value: 127))
if case .controlChange(controller: 67, let value) = event.message { … }
```

`Message` also has `.programChange(program:)`, `.channelPressure(pressure:)`, `.polyphonicKeyPressure(key:pressure:)` and `.pitchBend(value:)` (14-bit, `0x2000` is the center).

Channels are numbered `0...15`, as in the MIDI bytes; most software shows them as 1 to 16. The sustain pedal, control change 64 on any channel, is still read into `sustains` and never into `channelEvents`. Sustains are written as control change 64 on channel 0, whatever channel they were read from.

A client that builds its own `.controlChange(controller: 64, …)` events would write the pedal twice; it should use `sustains`. Code that iterates `channelEvents` must now handle, or skip, messages other than control changes. `MIDITrack` initializers take `channelEvents:` instead of `controlEvents:`.

### 10.2 Notes

| 1.x | 2.x |
|---|---|
| `MIDINote.note` (stored), `pitch` (alias) | `pitch` (stored), `note` deprecated |
| `MIDINote(onset:offset:note:velocity:…)` | `MIDINote(onset:offset:pitch:velocity:…)`, `note:` deprecated |
| `<` by onset only | total order (1.10) |
| `MIDINotes.distance(to:missingPenalty:)`, `normalizedDistance(to:missingPenalty:)` | `similarity(to:onsetTolerance:offsetToleranceRatio:)` → `MIDINotes.Similarity` |
| `MIDINotes.deriveReferenceNoteLength(minimumNoteDistance:)` | none |
| none | `MIDINote.isBlack(_:)` (2.0.1) |

`similarity` is a soft F1 in `0...1`, where **higher is better**, with an exact one-to-one pairing; `distance` was a cost, where **lower is better**, and could match a note twice. Any threshold or comparison ported from `distance` must be inverted and calibrated again, not just renamed. `Similarity` also reports `matchedCount`, `unmatchedCount`, `otherUnmatchedCount`, `onsetRMSE` and `offsetRMSE`.

### 10.3 Sustains

`MIDISustainEvents` (see 1.6 for the rules):

- `init(_:minimumGap:)` takes any `Sequence` of `MIDISustainEvent`; `insert(_:minimumGap:)` and `insert(contentsOf:minimumGap:)` clean up the same way.
- `contents` is read-only, the subscript is get-only, and it is no longer a `MutableCollection`. To change sustains, build a new `MIDISustainEvents` from modified elements, or in 2.1.0 pass them to `IndexedTrack.replacing(notes:sustains:)`.
- It conforms to `Intervals.DisjointIntervals` instead of the 1.x `DisjointIntervals`; see section 11 for the queries.
- `MIDISustainEvent` is no longer `Comparable`, so `sustains.sorted()` fails. Sort with `sorted { $0.onset < $1.onset }`, or rely on `MIDISustainEvents` being sorted already.

### 10.4 Tracks, tempo and time signatures

| 1.x | 2.x |
|---|---|
| `MIDITrack.controlEvents` | `channelEvents` |
| `MIDITrack.range: ClosedRange` (`0...0` without notes) | `ClosedRange?`, `nil` without notes |
| `MIDITrack.quantize(by:)` | none |
| `MIDITrack.measures(timeSignature:)`, `MIDIMeasure`, `[MIDIMeasure].jointed()` | none |
| `MIDITempoTrack.contents` / `.events` / `init(events:tempos:)` | `tempos` / `metaEvents` / `init(metaEvents:tempos:)`; old names deprecated |
| `MIDITempoTrack.Tempo.tempo`, `init(timestamp:tempo:)` | `beatsPerMinute`, `init(timestamp:beatsPerMinute:)`; old names deprecated |
| `MIDITempoTrack.setTimeSignature(beatsPerMeasure:beatsPerNote:)` | `tempo.timeSignature = MIDITimeSignature(3, 4)`; `nil` removes it |
| none | `MIDITimeSignature` (`numerator`, `denominator`, `default` 4/4, `init?(_ event:)`, `event(at:)`, `Codable`) |

`setTimeSignature`'s `beatsPerNote` was the denominator, 4 for a quarter note; `MIDITimeSignature(numerator, denominator)` takes the same values. A file without a time signature is still written as 4/4.

### 10.5 Container

| 1.x | 2.x |
|---|---|
| `writeData(to:)` (deprecated) | `write(to:)` |
| `adjustMIDINotesToConstantTempo(_:)` (deprecated) | `normalizeToConstantTempo(_:)` |
| `indexed(minimumConsecutiveNotesGap:)` → `IndexedContainer` | `indexed(profile:minimumConsecutiveNotesGap:)` → `IndexedTrack`, in module `IndexedTrack` |
| `FinderItem.AsyncLoadableContent.MIDIContainer` | `.midiContainer`; old name deprecated |
| none | `trimLeadingSilence()`, `trimmingLeadingSilence()` |
| `writeResolution` 4,800 | 9,600 (1.12) |

`normalizeToConstantTempo` now also rescales channel events, meta events, raw data and the tempo track's meta events; in 1.x only notes and sustains moved. The results for notes are bit for bit the same.

`trimLeadingSilence()` keeps the opening tempo when a note starts before 0: everything moves later, and the first tempo, if it starts by 0, moves to 0.

### 10.6 Smaller changes

- `MIDIRawData.timestamp` and `data` are `var`.
- `MIDIMetaEvent` is `Hashable`.
- `MIDIInputEvent` is `Sendable` without `@unchecked`.
- The public `Collection.median`, and `Range<Double>.onset` and `offset` (with `Range<Double>: Interval`), that 1.x exported are gone.

## 11. Intervals

The 1.x protocols `Interval`, `SortedIntervals`, `DisjointIntervals` and `OverlappingIntervals` lived in `MIDIKit`. 2.x has `Interval` and `DisjointIntervals` in module `Intervals`, plus `IntervalTree` for overlapping intervals.

- `Interval` requires only `onset` and `offset`; it no longer refines `Comparable`, and doesn't require `duration`. Client types that conformed for sorting must add their own `Comparable`.
- `DisjointIntervals` no longer assumes indices start at 0, and returns `Int` indices.
- Removed queries: `nearest(to:)`, `nearestIndex(to:)`, `nearest(to:isValid:)`. `index(at:tolerance:)` now returns the closest interval when several lie within the tolerance, which covers most uses of `nearest`; otherwise combine `lastIndex(before:)` and `firstIndex(after:)`. 1.x `applyVelocity(to:)` was built on `nearest(to:isValid:)`; its replacement is `applyingVelocities`, not a port.
- Added: `firstIndex(after:from:)`, `lastIndex(before:from:)` and `index(at:tolerance:from:)`, cursors for queries that move forward in time; `indices(overlapping:)`; and `isValidDisjointIntervals()`.
- `OverlappingIntervals` is replaced by `IntervalTree(_:)` over any sorted random-access collection of intervals, and by ``IndexedTrack/IndexedTrack/intervalTree`` for notes.
- Conformances: `MIDINote` and `MIDISustainEvent` conform to `Intervals.Interval`; `MIDISustainEvents` and ``IndexedTrack/IndexedTrack/Lane`` conform to `Intervals.DisjointIntervals`.

## 12. Removed with no replacement

A client that used any of these must drop the feature, keep its own copy of the 1.x code, or ask for a new API. Flag each use, and don't accept a silent substitution with something that only looks similar.

- `IndexedContainer.regions()`, `Region`, `Regions`
- `runningAverage(runningLength:)`, `RunningAverage`
- `keyFeatures()`, `KeyFeature`, `KeyFeatures`, `Pivot`, `Pivots`, `Pivots.append(to:)`
- `baselineBarLength(beatsPerMeasure:)`, `baselineBarLength(beatsPerMeasure:samples:)`, `localBarRegions(...)`, `LocalBarRegion`
- `sustainCoverage`, `sustainDurations()`
- `mergeNotesInSameInterval(in:threshold:difference:)`
- `splittingHands`
- `VelocityProvider.inferVelocity(pitch:onset:tolerance:)` as a per-note lookup
- `Chord.makeSingleHandedChords`, `Chord.Spec(duration:)`, `Chord.Features.preferLeftHand` and `.preferRightHand`
- `ReferenceNote`, `DisjointNotes`, `NotesProviding`
- `MIDIMeasure`, `MIDITrack.measures(timeSignature:)`, `[MIDIMeasure].jointed()`
- `MIDITrack.quantize(by:)`
- `MIDINotes.deriveReferenceNoteLength(minimumNoteDistance:)`
- `PreserveSettings.description` and `localizedStringResource`

`sustainCoverage` and `sustainDurations()` are one-liners over `track.sustains` and `track.notes`; reimplementing them in the client is fine.

## 13. Still deprecated

These compile with a warning. An integration should move to the new name now, as they may go in a later release.

| Deprecated | Use |
|---|---|
| `MIDINote.note` | `pitch` |
| `MIDINote(onset:offset:note:velocity:channel:releaseVelocity:)` | `pitch:` |
| `MIDITempoTrack.events`, `.contents` | `metaEvents`, `tempos` |
| `MIDITempoTrack(events:tempos:)` | `init(metaEvents:tempos:)` |
| `MIDITempoTrack.Tempo.tempo`, `init(timestamp:tempo:)` | `beatsPerMinute`, `init(timestamp:beatsPerMinute:)` |
| `FinderItem.AsyncLoadableContent.MIDIContainer` | `.midiContainer` |

## 14. Persistence and file output

- **Key signatures.** `MIDIKeySignature` encodes as a single number, its `sharps`. It decodes both that and the 1.x keyed format `{"pitches": [...], "accidental": n}`, so stored 1.x values still load, but values written by 2.x can't be read by 1.x. A key signature stored inside a SwiftData `@Model` changes type and shape, which may need a schema migration; check how the client stores it.
- **PreserveSettings.** Same raw values (`"Acoustic Result"`, `"Notes Display"`), so values stored by raw value (`@AppStorage`, `RawRepresentable` coding) still decode. The type moved from `IndexedContainer.PreserveSettings` to ``IndexedTrack/IndexedTrack/PreserveSettings``, and it no longer carries text for the user interface. A client that showed `setting.localizedStringResource` or `setting.description` in a picker must now provide its own labels, localized in its own bundle. The 1.x text, for reference: "Acoustic Result" with "Optimize note lengths using the sustain pedal for the most realistic sound.", and "Notes Display" with "Tighten note lengths to reduce overlaps and make chords and rhythms easier to read."
- **Transcription algorithm.** See section 5: keep the raw values `transkun` and `pianoTranscription` in the client's own enum.
- **MIDI files.** See 1.12. Files written by 1.x read back the same in 2.x, apart from the sustain cleanup (1.6) and the end-of-track pedal.

## 15. Review checklist

Run these over the integration's diff and over the whole client, since unchanged code can depend on changed behavior. Each hit needs the check named beside it.

```bash
rg -n 'applyingVelocities|applyVelocity|VelocityProvider|inferVelocity'   # 1.1: the receiver is the track that receives velocities; the result is used
rg -n 'timeWarp\(|warped\(by|projection\(|TimeWarp'                        # 1.2, 1.3: warp direction; durations; the gap; not copied from the old README
rg -n 'applyingGap|normalizing\(|removingArtifacts|warped\(by|modifyingNotes' # 1.4: results used, not dropped
rg -n 'noteIndices|modifyingNotes|replacing\(notes'                        # 2: positions and note indices not mixed; modifyingNotes keeps counts, onsets and keys
rg -n '\.channel\b'                                                         # 1.5 and 10.1: not used as a track index or as a controller number
rg -n 'sustains|MIDISustainEvent'                                           # 1.6, 10.3: no merged-pedal assumptions; no mutation; no sorted()
rg -n 'keySignature|KeySignature'                                           # 1.8, 7, 14: optional handled; stored versus estimated; persistence
rg -n 'downbeats\('                                                         # 1.9: beatsPerMeasure dropped consciously; prior semantics
rg -n 'lanes\[|lane:|\.notes\['                                             # 1.11: pitch guarded to 21...108; no `lanes[lane:]` from a branch before 2.0.0
rg -n 'controlEvents|MIDIControlEvent|controlChange'                        # 10.1: controller and value, real channel, CC 64 not duplicated
rg -n 'distance\(to|normalizedDistance|similarity\('                        # 10.2: thresholds inverted and calibrated again
rg -n 'TranscriptionAlgorithm|optimizeFor|AnalysisProfile|Profile\(\)'      # 5: one profile per track; persisted raw values kept; custom profiles valid
rg -n 'PreserveSettings'                                                    # 14: labels provided by the client
rg -n 'writeResolution|\.mid"|golden|fixture'                               # 1.12: golden files regenerated on purpose
rg -n '\.note\b|note:|\.tempo\b|events:|\.MIDIContainer\b'                  # 13: deprecated names migrated
rg -n 'import (MIDIKit|IndexedTrack|Intervals|NativeImage|ConcurrentStream)' # 3: imports and declared products match the use
```

And beyond the searches:

- `Package.swift` declares the `IndexedTrack` and `Intervals` products where used, and any `NativeImage` or `ConcurrentStream` the client uses itself.
- Before merging, MIDIKit is required `from: "2.0.0"`, or `from: "2.1.0"` for the API of section 2, not a branch, revision or local path.
- The client builds with no warnings from MIDIKit APIs: no deprecations, no unused transform results.
- Every test whose expectations changed was changed for a reason this article gives, and the new expectation was checked, not copied from the failing output.
- Nothing removed in section 12 was replaced by a lookalike without saying so.
- No 1.x numeric constants were carried over into `TimeWarp.Parameters`, `ChordArbiter` or `DownbeatTracker`.
- Custom `AnalysisProfile` conformances are deterministic, form the chords of the track they are given, don't read `track.chords` inside `formChords`, and don't read offsets from PianoTranscription output.
- Closures passed to `modifyingNotes(_:)` keep the number, onsets and keys of the notes: only debug builds check this.
- Code that showed MIDIKit data in SwiftUI still means the same: `ForEach(track.notes, id: \.self)` is fine, as `MIDINote` is `Hashable`, but `ForEach(track.chords, id: \.self)` is not, as `Chord` is not `Hashable`.
