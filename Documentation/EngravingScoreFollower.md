# Integrating `EngravingScoreFollower`

`EngravingScoreFollower` is the score follower for a piano-practice interface that owns an
engraved, vertically arranged score. It uses pitches, gesture timing, releases, written
durations, hands, measures, and engraving lines to estimate position while protecting the
performer from unstable cursor and viewport movement.

This guide is part of the behavioral contract. Read it before connecting the follower to a
position marker or scroll view.

## When to use it

Use `EngravingScoreFollower` when the application can provide:

- every expected note onset and MIDI pitch;
- the written duration and notated hand of each note;
- whether simultaneous notes form a block or rolled chord;
- measure onset and duration;
- the engraving line containing each measure; and
- the beat range currently visible in the score view.

Use `ScoreFollower` instead when only a pitch sequence is available or when the presentation is
not organized into engraved measures and lines. The two followers intentionally have different
contracts.

## The three positions

The integration must keep these concepts separate:

| Value | Meaning | May move backward? |
| --- | --- | --- |
| `Update.beat` | Committed musical interpretation | Only after a confirmed replay or jump |
| `Update.displayBeat` | Stable marker position shown to the performer | Only during a confirmed jump |
| `Update.viewport` | Rare instruction for the score view | Only `.jump` may move backward |

Draw the normal score-position marker at `displayBeat`. Do not derive scrolling from `beat`.

During a visible replay, `beat` follows the passage being replayed while `displayBeat` waits at
the previous forward frontier. The score remains stationary. When the replay catches up,
`displayBeat` begins advancing again.

## Constructing the engraving reference

The reference owns musical and layout information as one immutable value:

```swift
let reference = try EngravingReference(
    measures: [
        .init(index: 12, onset: 0, duration: 4),
        .init(index: 13, onset: 4, duration: 4)
    ],
    lines: [
        .init(
            index: 3,
            beatRange: 0...8,
            measureRange: 12...13
        )
    ],
    moments: [
        .init(
            beat: 0,
            notes: [
                .init(pitch: 48, duration: 1, hand: .left),
                .init(pitch: 60, duration: 1, hand: .right),
                .init(pitch: 64, duration: 1, hand: .right)
            ],
            attack: .block
        )
    ]
)
```

Reference requirements:

- Measure indices must be unique and increase in score order.
- Measure onsets and durations must be finite; durations must be positive.
- Every measure must belong to exactly one line.
- Line indices must be unique.
- A line's beat range must contain all of its measures.
- Every moment must belong to a measure and contain at least one note.
- Pitches must be MIDI 1.0 note numbers in `0...127`.
- Note durations must be finite and nonnegative.

The initializer sorts valid measures, lines, and moments into score order. Moments at effectively
the same onset are merged. Duplicate pitch-and-hand metadata keeps the longest written duration.
If any merged source moment is rolled, the resulting moment is rolled.

Line and measure indices are identifiers supplied by the engraving model. They need not start at
zero. `ViewportRecommendation` returns the public line index, not the line's array offset.

## Lifecycle

For a new score or layout, replace the complete reference:

```swift
await follower.update(reference: reference)
```

`update(reference:)` resets the performance epoch. Do not separately install lines or measures.

For a user-initiated scroll within the same reference, use this ordering:

```swift
follower.reset()
follower.visibleRange = engraving.visibleBeatRange(in: scrollView)
```

Continue assigning `visibleRange` from scroll-view callbacks as the viewport changes. It is
expected to be updated many times before the next MIDI event:

```swift
func scrollViewDidScroll(_ scrollView: UIScrollView) {
    follower.visibleRange = engraving.visibleBeatRange(in: scrollView)
}
```

Report the beats actually visible in the usable reading area, including any intentional margin
above or below the centered line. Do not report the whole loaded page, a prefetch window, or the
entire score: an overly broad range would classify genuinely offscreen playing as a local replay.
Keep publishing intermediate ranges during a programmatic one-line animation; no debouncing is
required.

Reset only for user-driven navigation or an explicit restart. A follower-requested programmatic
scroll must update `visibleRange` but must not call `reset()`. In a UIKit integration,
`scrollViewWillBeginDragging` is an appropriate place to distinguish a user gesture from a
programmatic scroll.

The first informative note-on after reset latches the latest visible range as an acquisition
hint. The performer can begin anywhere; the visible range is a prior, not a restriction. Strong
musical evidence can acquire a different location, in which case the result is presented as a
jump.

Acquisition hypotheses remain private until a location is committed. Consequently `consume`
may return `nil` for several valid note-ons at the start of repeated or otherwise ambiguous
material. A complete chord acquires immediately only when its full performed-hand interpretation
identifies one score destination. Monophonic offscreen acquisition requires corroborated ordered
context; one differing note cannot move the viewport. No provisional acquisition guess updates
`beat`, `displayBeat`, or the forward frontier.

After acquisition, `visibleRange` has two jobs:

1. It defines which earlier score positions can be treated as a local replay.
2. It distinguishes a visible replay from an offscreen jump.

It never increases the confidence of a musical hypothesis. This prevents follower-driven
scrolling from confirming the follower's own decision.

## Connecting MIDI input

`MIDIInputController` publishes decoded note, release, and pedal events. Preserve their order and
timestamps:

```swift
let follower = EngravingScoreFollower()
let midi = MIDIInputController.shared

try midi.initialize()
try midi.connectToFirstAvailableSource()

Task { @MainActor in
    for await event in midi.events() {
        guard let update = follower.consume(event) else { continue }
        apply(update)
    }
}
```

The follower consumes note-offs and control changes as evidence but returns an `Update` only for
an informative note-on. MIDI note-on with velocity zero is normalized to note-off. Sustain and
sostenuto affect release evidence; they do not create score attacks.

If an integration already decodes its transport, preserve the input timestamp with the public
decoded-event overload:

```swift
let update = follower.consume(parsedEvent, timestamp: originalMIDITimestamp)
```

Pass the original `MIDITimeStamp`, not the time at which a UI task eventually handles the event.
A timestamp of zero means “timing unavailable” and deliberately selects pitch-only behavior.
Equal timestamps preserve stream order. Nonmonotonic differences and extreme discontinuities are
ignored by the timing estimator rather than repaired or used to reject notes.

Use one serialized event stream for a follower. MIDI channels are retained by
`MIDIInputEvent`, but the follower currently treats all channels as one piano performance.

## Applying updates

A typical presentation adapter should resemble:

```swift
func apply(_ update: EngravingScoreFollower.Update) {
    positionMarker.beat = update.displayBeat
    positionMarker.confidence = update.confidence

    switch update.viewport {
    case .unchanged:
        break

    case let .advance(toLine: lineIndex):
        scoreView.centerLine(
            withIndex: lineIndex,
            animated: true,
            allowsSpringing: false
        )

    case let .jump(toLine: lineIndex):
        scoreView.reframeWithoutTraversingScore(toLineWithIndex: lineIndex)
    }
}
```

The method names on `scoreView` are illustrative; they are not MIDIKit APIs.

### `.unchanged`

Do not adjust the scroll position. This is expected while:

- the performer remains on the same engraving line;
- the follower is acquiring, uncertain, or lost;
- a replay or relocation probe is being evaluated; or
- a confirmed replay remains within the visible margin.

### `.advance(toLine:)`

Center the specified line using one forward line movement. The follower emits this only after
`displayBeat` has been reliably committed to the immediate next engraving line. It does not
pre-scroll during the final measure of the current line.

The target line may already be visible. The recommendation establishes it as the new viewport
line after the performer's eyes have moved to it. Use a short deterministic animation without
springing, bounce, or overshoot. Do not independently retarget the scroll view from later raw
`beat` values.

### `.jump(toLine:)`

Reframe directly at the destination. A jump may move forward or backward. Do not animate through
intervening systems because that implies continuous traversal and makes similar lines difficult
to reacquire. A snap or brief crossfade is preferable.

`didRelocate` is `true` for a jump. A decrease in `displayBeat` is valid only on such an update.

## Expected performer-facing behavior

### Normal forward playing

- `beat` and `displayBeat` advance through committed moments.
- Similar passages may remain internally ambiguous, but ordinary tracking cannot publish a
  backward position.
- The viewport remains still for the whole line.
- The viewport advances once, and only once, after committed entry into the next line.

### Mistakes

- Missing, additional, or incorrect pitches reduce confidence without granting permission to
  move backward or jump.
- Unsupported input holds the committed marker and viewport.
- A matching chord elsewhere in the score cannot cause an immediate relocation.

### Visible backward practice

- An earlier interpretation is evaluated invisibly while the public position waits.
- Several ordered gestures and distinguishing context are required before replay is committed.
- On commitment, `beat` moves to the current point in the earlier passage.
- `displayBeat` and the viewport remain at the forward frontier.
- The replay must remain inside the current visible range. No backward scrolling occurs.

### Offscreen backward practice

An earlier position outside `visibleRange` is not a local replay. It is evaluated by the guarded
jump mechanism. Until confirmed, the marker and viewport hold. On confirmation, `beat`,
`displayBeat`, and the viewport relocate together.

### One-hand practice

No mode selection is required. The follower evaluates both-hand, left-hand, and right-hand
interpretations concurrently and reports the inferred mode in `activeHands`. Notes belonging
only to the inactive notated hand can provide participation evidence but cannot advance a
one-hand interpretation.

### Chords

A block chord is one physical gesture. Its individual note-on messages must not consume later
moments. Repeating an identical or similar chord requires boundary evidence such as key releases
or a completed preceding gesture.

A rolled chord also remains one gesture. The follower uses membership and accumulated evidence
rather than a fixed chord timeout, so deliberately slow rolls are supported.

### Timing

Timing is bounded corroborating evidence, never a gate:

- confirmed adjacent gestures maintain a robust estimate of host-time ticks per score beat;
- block and rolled chords learn separate onset-span distributions;
- each global challenger starts an independent clock after its possible change point;
- a pause before a replay or jump is not compared with music preceding the destination;
- written duration, note-off time, and local tempo provide weak mistaken-hit evidence; and
- large rubato, fermatas, zero timestamps, and transport jitter reduce timing confidence without
  disabling pitch-based alignment.

There is intentionally no rule equivalent to “notes within N milliseconds form a chord.” A note
matching an unplayed member of the current block or rolled chord remains in that gesture even
when it arrives unusually late. Conversely, elapsed time alone cannot close an incomplete chord.

## Stability architecture

The implementation deliberately does not model forward motion, replay, and relocation as three
peer state machines. It has one monotone local incumbent and a bounded collection of global
challengers:

1. The gesture assembler combines serialized note-ons into one physical block or rolled chord.
   A physical gesture can expose at most one score boundary.
2. The local incumbent may hold for an inserted mistake, advance to its immediate successor, or
   provisionally consider one missed score gesture. It has no backward transition.
3. Global challengers are seeded continuously from indexed chord and transition fingerprints.
   They use only evidence observed after their possible change point; music played before a jump
   is never matched against music preceding the destination.
4. Candidate comparison uses relative evidence. Notes common to the incumbent and challenger
   are neutral; exclusive chord tones, bass and soprano motion, register, and ordered gestures
   distinguish locations.
5. Each challenger carries a monotone local counterfactual over the same post-change episode.
   Relocation evidence therefore compares a remote continuation with a coherent local repair,
   not with a newly selected local position on every note.
6. A challenger must describe one uninterrupted post-change episode: an anchor, coherent
   continuation, and confirmation. Passage-like errors separated by local recovery cannot be
   added together. At least two gestures in the episode must distinguish the challenger from
   local continuity.
7. A relocation decision uses only completed physical gestures or a current gesture whose
   expected pitch set has been exactly resolved. It is vetoed when more than one score
   destination is ready, rather than choosing an arbitrary repeated occurrence.
8. Candidate lookup certifies whether its bounded search was exhaustive. Truncation can delay a
   relocation but can never manufacture a unique destination.
9. Only after those checks may a challenger replace the incumbent. Its destination is then
   classified as a correction, visible replay, or jump.

After a jump, the relocation gate rearms only after two strong local continuations. This
evidence-based hysteresis prevents one bad relocation from cascading into another.

This architecture matters for similar passages. A shared chord tone cannot keep a wrong local
interpretation alive, but neither can it promote a remote passage. If two locations are
observationally identical, the follower preserves continuity until later evidence selects
exactly one of them. Missing that evidence leaves the location ambiguous; it does not justify an
arbitrary switch.

Alignment and presentation are separate components. Candidate changes can make the public state
`uncertain` or `lost`, but they cannot move `displayBeat` or the viewport. The presentation layer
responds only to a confirmed movement classification.

The implementation is divided under `Sources/IO`: `EngravingScoreFeatures` compiles the immutable
score, `PerformanceGestureAssembler` owns chord construction, `PerformanceTimingModel` owns all
temporal estimation, `EngravingAlignmentModel` owns the incumbent and challengers, and
`EngravingPresentationPolicy` owns marker and viewport stability. `EngravingScoreFollower` is the
public façade joining those components.

## Behavioral invariants

These invariants are intentional and should remain true when the implementation changes:

1. Without `didRelocate`, `displayBeat` never decreases.
2. Ordinary forward tracking never decreases `beat`.
3. A visible replay may decrease `beat`, but never `displayBeat`.
4. A visible replay never produces a viewport recommendation.
5. Uncertain or lost tracking never moves the viewport.
6. `.advance` names the immediate next engraving line and never moves backward.
7. Only `.jump` may target an arbitrary or earlier line.
8. A backward destination outside the viewport cannot commit as local replay.
9. One physical chord cannot provide multiple gesture confirmations.
10. `visibleRange` influences acquisition and replay locality, never musical likelihood during
    established tracking.
11. Presentation never promotes a continuous alignment into a jump. A multi-line continuation
    without relocation authorization holds the marker and viewport.

The key architectural rules are that active paths never walk backward through the score and one
physical performance gesture never confirms multiple score gestures. Backward practice starts a
new forward-running interpretation at an earlier location.

## Common integration mistakes

### Scrolling from `beat`

This recreates viewport oscillation during practice. Always obey `Update.viewport`; do not look up
the line containing raw `beat` and center it independently.

### Drawing the primary marker at `beat`

During a local replay this moves the user's stable landmark backward. Draw it at `displayBeat`.
Raw `beat` can be used for diagnostics or non-spatial analytics.

### Resetting during follower-requested scrolling

This discards the performance history on every line transition. Reset only when the user drives
the scroll view or when starting a new performance epoch.

### Updating the viewport before reset

The acquisition hint is sampled after reset. For user navigation, call `reset()` first and then
publish every resulting `visibleRange` update.

### Treating a boundary beat as two visible lines

Adjacent line and measure ranges commonly share an endpoint. Report the actual viewport range;
the follower applies half-open boundary behavior internally so an endpoint alone does not make
the following line visible.

### Inventing a loop range

Do not infer or supply an active loop. The visible viewport is the local replay boundary, and the
follower determines replay from musical evidence.

## Troubleshooting

- **The marker waits after a mistake:** This is deliberate. The follower lacks enough evidence
  to publish a new position.
- **The marker does not move backward during repetition:** Inspect `beat`; the visible marker is
  intentionally held at `displayBeat`.
- **Backward practice caused a jump:** The destination was outside the current visible range or
  required nonlocal confirmation.
- **A jump takes several gestures:** One matching gesture is intentionally insufficient. A
  coherent distinguishing sequence can win without waiting for complete local failure.
- **The viewport does not pre-scroll near a line ending:** This is required. It moves only after
  the performer has entered the new line.
- **One hand does not advance immediately:** `activeHands` begins as `unknown` and accumulates
  evidence before settling on left, right, or both.

## Maintainer and agent guidance

Do not fix tracking errors by restoring backward targets to the primary beam or by making the
viewport follow the highest-scoring hypothesis. Those changes violate the performer-facing
contract even if they improve a short synthetic sequence.

When changing the follower:

- keep gesture assembly, alignment, and presentation as separate components;
- preserve one monotone incumbent and candidate-relative challenger evidence;
- retain ambiguous alternatives until a distinguishing anchor arrives;
- never use pre-jump performance history to identify a destination;
- require multi-gesture commitment before publishing a nonlocal hypothesis;
- preserve the display and viewport invariants above;
- test ambiguous repeated passages as well as unique melodies;
- test note ordering within large block and rolled chords;
- test zero, equal, nonmonotonic, highly variable, and extremely separated timestamps;
- measure release-build event-processing cost; and
- update this document whenever public semantics change.
