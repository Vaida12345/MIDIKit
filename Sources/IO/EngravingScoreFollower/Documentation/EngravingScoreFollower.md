# Integrating `EngravingScoreFollower`

`EngravingScoreFollower` follows live piano MIDI against an `EngravingReference` while keeping
musical position separate from visual presentation. That separation is intentional: the follower
can become uncertain, recover locally, or recognize visible replay without moving the score under
the pianist's eyes.

## Setup

Construct and validate one reference containing measures, engraving lines, and note moments, then
install it atomically:

```swift
let follower = EngravingScoreFollower()
await follower.update(reference: reference)
follower.visibleRange = currentlyUsableBeatRange
```

Reference replacement is a hard reset. Do not deliver old-reference MIDI after the awaited call.
Send all subsequent property changes and MIDI events from one serialized context.

## Sending input

The normal controller path preserves the MIDI timestamp:

```swift
if let update = follower.consume(inputEvent) {
    apply(update)
}
```

Alternate transports and deterministic playback can use:

```swift
let update = follower.consume(parsedEvent, timestamp: originalHostTime)
```

A timestamp of zero is supported and disables only timing evidence for that relationship. Always
preserve the timestamp for note-off, including MIDI's velocity-zero note-on spelling.

Before the music is located reliably, `consume` returns `nil`. There is no public `acquiring`
state to render.

## Applying an update

```swift
func apply(_ update: EngravingScoreFollower.Update) {
    musicalCursor.beat = update.beat
    primaryCursor.beat = update.displayBeat

    switch update.viewport {
    case .unchanged:
        break
    case let .advance(toLine: line):
        revealLine(line, animated: true)
    case let .jump(toLine: line):
        revealLine(line, animated: false)
    }
}
```

`beat` is the committed musical location. `displayBeat` is the stable primary marker. During a
confirmed replay that remains visible, `beat` can move backward while `displayBeat` stays at the
former reading frontier. This is expected.

`didReframe` is true exactly for a discontinuous visual frame change. Without it, the app can rely
on `displayBeat` never decreasing. `.advance` is a one-system continuity motion and does not set
`didReframe`.

`confidence` belongs to the published score destination. `state` describes whether that position
is tracking normally, uncertain, or lost. In the latter two states the follower holds the visual
frame.

## Visible range

Keep `visibleRange` synchronized with what the pianist can actually use, not merely what exists in
the scroll view's backing buffer. The upper bound is treated as the edge of the usable region for
ordinary ranges.

The follower uses this range in three ways:

1. as a defeasible prior before acquisition;
2. to distinguish visible replay from offscreen relocation;
3. to suppress unnecessary line movement when the next system is already visible.

It is not self-confirming evidence during established tracking.

## User navigation

When the user begins to scroll, call the argument-free API once:

```swift
follower.userReset()
```

Then continue publishing `visibleRange` as scrolling proceeds. The last range before the next
attack becomes the acquisition hint. `userReset()` clears position and partial chord evidence but
retains performer timing calibration and prevents the scroll interval from being interpreted as a
musical pause.

Do not call `userReset()` for a viewport change requested by the follower. Apply the recommendation
and report the resulting `visibleRange`; otherwise every automatic page movement would destroy
tracking history.

## Viewport recommendations

- `.unchanged`: preserve the current spatial frame.
- `.advance(toLine:)`: reveal one upcoming system during ordinary forward reading. When the next
  line is not already visible, this can arrive on the last committed onset of the current line.
- `.jump(toLine:)`: directly reframe after a confirmed nonlocal destination.

Recommendations are sparse and should be handled idempotently. Uncertainty, lost tracking, one
wrong onset, and visible replay do not issue viewport movement.

## API migration

The replacement intentionally removes `reset()`, `plausibleBeatRange`, and
`TrackingState.acquiring`. Use `userReset()`, render uncertainty from `confidence` and `state`, and
wait for the first non-`nil` update. `didRelocate` is renamed to `didReframe` because it describes a
presentation action, not every musical relocation.

For algorithm details and invariants, see
[`EngravingScoreFollowerAgentContract.md`](EngravingScoreFollowerAgentContract.md).
