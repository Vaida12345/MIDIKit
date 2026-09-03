# `EngravingScoreFollower` Agent Contract

This document is the maintainer contract for agents changing `EngravingScoreFollower` or code
that integrates with it inside MIDIKit. It records the product assumptions, algorithmic design,
presentation behavior, performance constraints, and deliberate omissions agreed during its
design.

The companion [integration guide](EngravingScoreFollower.md) explains how an engraving app uses
the public API. This document explains why the implementation has its present shape and which
properties must survive refactoring. If code and this contract disagree, do not silently choose
one: identify whether the code is a defect or the contract needs an explicit product decision.

## 1. Product purpose

This follower is for piano practice against an engraved score. It receives serialized MIDI
events and estimates the performed score beat, but it also protects the performer's visual frame
of reference. Correct musical inference and good score presentation are related but distinct
problems.

The intended performer may:

- start anywhere without selecting a starting beat;
- play normally forward;
- omit or add notes while learning;
- play only the left hand or only the right hand;
- play block chords in arbitrary MIDI note order;
- roll chords much more slowly than in performance;
- repeat a nearby passage backward and then move forward again;
- jump to a distant passage; and
- pause, use rubato, or produce unreliable timestamps.

The follower must operate autonomously. The only routine user signal is scrolling. A user-driven
scroll means the previous following result is no longer authoritative and starts a new
acquisition epoch. There is no start-position picker or loop-selection UI.

## 2. Performer-facing principle

The score is a spatial memory aid, not a moving telemetry display. Music systems look similar,
and performers use the stable position of a system, nearby measures, and peripheral landmarks to
maintain reading position. Moving a system while the eyes are still reading it is disorienting,
even if the movement anticipates where the performer will go next.

Consequently:

- inference may be uncertain without causing visual motion;
- the marker may deliberately wait while the internal musical location replays an earlier
  visible passage;
- ordinary scrolling happens only after committed entry into the next line;
- normal scrolling advances one engraving line at a time;
- a confirmed nonlocal jump reframes directly instead of animating through intervening lines;
  and
- backward replay within the visible margin never scrolls backward.

These are product requirements, not cosmetic preferences. A change that improves synthetic
alignment accuracy while making the marker or viewport oscillate is a regression.

## 3. Scope and deliberate non-goals

The follower currently supports exact MIDI pitches in `0...127`, with tolerance for missing,
extra, and incorrect played notes in its similarity scoring. It does not perform pitch-class,
enharmonic, octave, or transposition matching.

The engraving model provides:

- moments with onset beat;
- every expected MIDI pitch at each moment;
- expected note duration;
- notated hand;
- block-versus-rolled attack type;
- measure index, onset, and duration;
- line index, beat range, and measure range; and
- the currently visible beat range at runtime.

The model intentionally does not require or invent:

- time signatures;
- written repeats or repeat expansion rules;
- navigation transitions;
- phrase or section annotations;
- a user-selected starting position;
- a supplied loop or active-practice range; or
- stable external moment identifiers.

A changed set of moments is installed as a new `EngravingReference`. Moment identity therefore
does not need to survive reference replacement. Thread-safety redesign is outside the current
scope; callers should provide one serialized event stream.

`ScoreFollower` is a separate, general follower. Do not fold this engraving-specific behavior
into it, and do not modify it as a side effect of work on `EngravingScoreFollower`.

## 4. Vocabulary

- **Score moment**: all notated attacks sharing an onset. It may contain one note or a block or
  rolled chord spanning both hands.
- **Physical gesture**: the group of MIDI note-ons interpreted as one performed score moment.
- **Local incumbent**: the currently committed, continuity-preserving alignment path.
- **Challenger**: a bounded alternative path started elsewhere and evaluated forward from its
  own possible change point.
- **Forward frontier**: the furthest ordinary forward location reached in the current epoch.
- **Correction**: commitment to a location in the short provisional local tail.
- **Replay**: commitment to an earlier destination that remains inside the visible range.
- **Jump**: a confirmed nonlocal destination, including any backward destination outside the
  visible range.
- **Musical beat**: `Update.beat`, the follower's committed musical interpretation.
- **Display beat**: `Update.displayBeat`, the stable primary marker presented to the performer.
- **Viewport line**: the line currently treated as the visual reading anchor by the presentation
  policy.

Replay and jump are classifications of a winning challenger. They are not peer movement states
competing every event with ordinary forward motion.

## 5. Reference-data contract

`EngravingReference` owns measures, lines, and moments in one immutable value. Music and layout
must not be installed independently because that permits mismatched state.

Construction guarantees:

- measures, lines, and moments are nonempty;
- measure indices are unique and increase in score order;
- measure onsets are finite, durations are finite and positive, and measures do not overlap;
- line indices are unique and line ranges are valid;
- every measure belongs to exactly one line;
- each line's beat range contains its measures;
- every moment has a finite beat, belongs to a measure, and contains a note;
- pitches are MIDI 1.0 values and durations are finite and nonnegative; and
- valid input is normalized into score order.

Moments at effectively the same onset are merged. Duplicate `(pitch, hand)` notes keep the
longest expected duration. If any merged source moment is rolled, the merged moment is rolled.
Public measure and line indices are engraving-owned identifiers and need not be zero-based.

The reference owns lines rather than maintaining a second mutable layout state. Replacing the
reference resets the follower.

## 6. Lifecycle and viewport-input contract

For a new score or changed moment set:

```swift
await follower.update(reference: reference)
```

For user-driven navigation in the same score, the required ordering is:

```swift
follower.reset()
follower.visibleRange = currentVisibleBeatRange
```

The app may then assign `visibleRange` eagerly and repeatedly as its `UIScrollView` moves. The
last valid range received before the first informative note-on is the acquisition prior.

Important distinctions:

- A user-driven scroll calls `reset()` because it says the prior result was wrong, obsolete, or
  beyond the passage the user wanted to play.
- A follower-requested programmatic scroll updates `visibleRange` but must not call `reset()`.
- Unsupported first notes must not latch the epoch, viewport sample, or a spurious gesture.
- The performer may start outside the viewport. Visibility is a useful prior, never a hard
  restriction.
- After acquisition, visibility classifies an earlier result as replay versus jump. It does not
  add musical likelihood to a candidate.
- The range describes the actually usable visible reading area, including intentional margins,
  not a loaded page, prefetch window, or the whole score.
- Adjacent boundaries are treated with half-open behavior internally so a shared endpoint alone
  does not make the next line visible.

The follower determines local repetition itself. Do not add an app-maintained loop range unless
the product contract is deliberately changed.

## 7. MIDI event contract

The preferred entry point is `consume(_ input: MIDIInputEvent)`. Alternate transports may call:

```swift
follower.consume(parsedEvent, timestamp: originalMIDITimestamp)
```

Requirements:

- Preserve source order and the original Core MIDI timestamp.
- Do not replace the timestamp with UI-delivery or task-scheduling time.
- Timestamp zero means timing is unavailable and selects pitch-only fallback behavior.
- Equal or nonmonotonic timestamps preserve event order but contribute no invalid time delta.
- MIDI note-on with velocity zero is a note-off.
- Note-offs and control changes update evidence but do not return an `Update`.
- Sustain controller 64 and sostenuto controller 66 inform gesture-boundary evidence.
- MIDI channels are currently combined into one piano performance.

The controller already supplies note-on, note-off, control-change, velocity, channel, and
timestamp information. The engraving follower presently scores pitch, release, pedal state, and
timestamp. Velocity is retained in each assembled gesture but is not currently scored; channel
separation is deliberately not part of alignment.

## 8. Gesture-assembly contract

MIDI serializes a physical chord into multiple note-on messages. The assembler must prevent one
physical chord from consuming several score moments.

Hard rules:

1. One physical gesture can expose at most one score transition.
2. A newly played pitch that is an unplayed member of the current expected block or rolled chord
   stays in the current gesture, regardless of elapsed time.
3. Re-articulating a pitch after its key release is strong, tempo-independent boundary evidence.
4. Coverage of the current chord, membership in the next chord, key releases, and pedal state
   may jointly indicate a boundary.
5. Timing may adjust a boundary threshold only slightly; timing alone may not close a chord.
6. Block and rolled chords use different learned timing distributions and different completion
   expectations.
7. A credible new challenger may contribute chord-membership masks while it is being evaluated,
   preventing a distant serialized chord from being split before relocation is confirmed.

There must be no fixed rule of the form “notes within N milliseconds are one chord.” Practice
tempo and rolled-chord speed vary too much for such a rule. Releases are attack evidence even
when a pedal continues the sound; pedals weaken sparse-gesture boundary evidence but do not erase
physical key releases.

## 9. Alignment architecture

### 9.1 Why there is one incumbent

The previous design treated forward movement, backward movement, tolerant matching, and jumping
as comparable states. That allowed ordinary ambiguity to move the cursor backward. The current
architecture instead has one monotone local incumbent plus bounded global challengers.

The local incumbent may:

- hold at the current moment for an insertion or incomplete gesture;
- advance to the immediate relevant successor;
- provisionally recover one omitted score moment; or
- switch among both-hand, left-hand, and right-hand interpretations.

It has no backward edge. Normal local matching therefore cannot publish backward motion. Once a
physical gesture has aligned a score moment, later notes extending that gesture may refine the
match but cannot consume another moment.

### 9.2 Acquisition

The user does not select a start. Acquisition evaluates bounded score-wide candidates in all
three hand modes. Evidence includes current chord similarity, a preceding gesture when
available, bass and soprano motion, and a strong but defeasible visible-range prior. A complete,
high-quality multi-note chord can establish tracking immediately; monophonic input generally
uses ordered context.

The visible range must remain a prior. Stronger musical evidence can acquire elsewhere and cause
a jump presentation.

### 9.3 Challengers and relocation

Challengers are seeded continuously from indexed chord candidates away from the immediate local
neighborhood. Each challenger:

- starts at its own possible change point;
- advances only forward through score order;
- receives no credit from performance history before that change point;
- owns an independent tempo clock;
- accumulates completed and current relative evidence; and
- is retained in a bounded beam.

This prevents two opposite errors: requiring the local path to become completely lost before a
real jump, and jumping immediately when one remote chord happens to resemble a mistake.

A challenger may commit only after one uninterrupted post-change episode has established an
anchor, continued from that anchor, and supplied a confirmation. In the current policy this is
at least three coherent physical gestures, at least two of which distinguish the destination
from local continuity. Contradiction ends the episode: passage-like errors on opposite sides of
local recovery cannot be added together. Only completed gestures, or a current gesture whose
expected pitch set is exactly resolved, count toward commitment. Visible backward replay remains
more conservative in its evidence requirement. A single anomalous anchor is never sufficient to
relocate.

Relocation is an intervention decision, not merely an alignment maximum. Its false-positive
cost is asymmetric: a delayed jump briefly holds a stable score, while a false jump destroys the
performer's spatial reference. This is the same distinction made in change-point detection,
fault-tolerant control, and hysteretic interfaces. Therefore a musically plausible challenger
may make tracking uncertain without yet gaining permission to move the display.

Commitment also has an ambiguity veto. Hand modes and seed histories that name the same current
score position are one destination hypothesis, but two different destinations that are both
ready block each other. The follower preserves continuity until post-change evidence selects
exactly one occurrence. It never resolves repeated material by array order or beam tie-breaking.

On commitment:

- a destination in the short provisional tail is a correction;
- an earlier destination inside `visibleRange` is replay;
- every other nonlocal destination is a jump; and
- the committed path adopts the challenger's post-change timing clock.

Backward playing is therefore represented as a newly confirmed forward-running path at an
earlier location, not as the incumbent walking backward.

## 10. Distinguishing similar passages from mistakes

Absolute match quality is insufficient because two passages may share most or all chord tones.
Candidate comparison must use evidence relative to the incumbent.

The important anchors are:

- pitches present only at the challenger location;
- pitches present only at the local location;
- missing candidate-relative notes once a gesture is coherent enough to assess;
- complete chord shape rather than raw note count;
- bass motion;
- soprano motion;
- absolute register, preserved by exact MIDI-pitch masks;
- ordered multi-gesture context; and
- bounded timing compatibility after a candidate's change point.

Notes common to both candidates are neutral evidence. They must neither keep a weak incumbent
alive nor promote a remote passage. This is the key to handling passages that differ by only a
few notes.

The intended decisions are:

- One passage-like wrong gesture is treated as an insertion, not proof of a jump.
- One differing note followed by local recovery does not relocate.
- Two distinguishing gestures begin a serious relocation probe; coherent confirmation is still
  required before it may relocate, and the incumbent need not become completely lost.
- If two passages remain observationally identical, preserve continuity rather than choosing an
  arbitrary remote occurrence.
- A wrong local interpretation that shares some pitches with the performance must not advance
  indefinitely merely because similarity is nonzero.

Do not attempt to repair this behavior solely by retuning one threshold. Instability here is a
model-structure problem: local continuity, relative evidence, and multi-gesture commitment must
remain separate concepts.

## 11. One-hand practice contract

Both-hand, left-hand, and right-hand interpretations are evaluated concurrently; the user does
not select a practice hand. Precomputed successor tables skip moments empty for a chosen hand.

Participation evidence is accumulated per completed physical gesture with decay. It must be
independent of MIDI note arrival order inside a chord. `activeHands` begins as `unknown` and
settles only after sufficient evidence.

A note belonging solely to the inactive notated hand must not advance a one-hand interpretation.
It may contribute evidence that the performer is actually using both hands.

## 12. Pitch and tolerance contract

Score and observed pitch sets are represented as `UInt128` masks. Similarity is the harmonic
mean of pitch precision and recall, so both extra performed notes and missing expected notes are
penalized while exact matches remain strongest.

Tolerance means tolerance for performance mistakes in the pitch set. It does not mean accepting
nearby semitones as the same pitch. Any future fuzzy-pitch feature must be an explicit API and
product decision because it would affect candidate indexing, ambiguity, and relocation safety.

## 13. Timing contract

Timing is corroborating evidence, never a gate.

The local timing model:

- estimates Core MIDI host-time ticks per score beat without wall-clock conversion;
- learns only from sufficiently credible committed transitions;
- updates robustly in log space so proportional tempo changes are symmetric;
- clips ordinary residuals;
- treats extreme pauses and transport discontinuities as reduced timing confidence rather than
  a new tempo;
- ignores zero, equal, and nonmonotonic deltas; and
- keeps separate block-chord and rolled-chord onset-span distributions.

Written duration combines with note-off dwell and learned tempo to provide weak evidence that a
short, isolated note was a mistaken insertion. It must not override contradictory pitch or
sequence evidence.

Each challenger starts an independent clock at its possible relocation point. Neither the pause
nor melodic motion from before the possible jump may be compared with music preceding the
destination. Timing evidence on a challenger is intentionally down-weighted, cannot make an
observation distinguishing, and a winning challenger's clock is adopted only when the
challenger commits.

No timing score may become large enough to override strong pitch disagreement. Rubato,
fermatas, slow practice, invalid timestamps, and deliberately slow rolls must continue to work
through pitch-based fallback.

## 14. Public update and presentation contract

`Update` deliberately exposes three different kinds of location:

| Field | Contract |
| --- | --- |
| `beat` | Committed musical interpretation. It may revise after a confirmed correction, replay, or jump; ordinary local forward tracking does not move backward. |
| `displayBeat` | Primary visible marker. It advances only through confirmed forward tracking and changes discontinuously only for a confirmed jump. |
| `plausibleBeatRange` | Compact local uncertainty near `beat`; distant alternatives are excluded rather than producing a misleading huge interval. |
| `measureIndex` | Public engraving measure identifier containing `beat`. |
| `confidence` | Bounded model confidence for diagnostics and subtle marker treatment, not permission for the app to invent scrolling. |
| `state` | `acquiring`, `tracking`, `uncertain`, or `lost`; uncertainty must hold presentation stable. |
| `activeHands` | Inferred `unknown`, `left`, `right`, or `both`. |
| `viewport` | The only authoritative scroll recommendation. |
| `didRelocate` | True only for discontinuous presentation reframing. |

The primary position marker is drawn at `displayBeat`, never raw `beat`.

### 14.1 Display beat

`displayBeat`:

- initializes at the first published location;
- increases on committed `.continuous` tracking;
- holds during `.held`, `.correction`, `.replay`, uncertainty, and lost tracking;
- remains at the forward frontier while a visible earlier passage is replayed; and
- may decrease or jump forward only when `didRelocate` is true.

When replay catches the forward frontier, normal display advancement resumes. This makes the
marker appear to wait for the performer instead of bouncing around the score.

### 14.2 Viewport recommendations

- `.unchanged`: do nothing. This is normal for an entire line, uncertainty, candidate probing,
  mistakes, and visible replay.
- `.advance(toLine:)`: move exactly one line forward after the performer has committed entry into
  that line. Never pre-scroll from the end of the preceding line.
- `.jump(toLine:)`: directly reframe a confirmed arbitrary destination. This may move forward or
  backward and sets `didRelocate`.

If an apparently continuous alignment crosses more than one line, presentation classifies it as
a jump because animating through several similar systems falsely implies continuous traversal.
For jumps, prefer a snap or brief crossfade over a long scroll through intervening systems.

An earlier destination inside the visible margin may commit as replay and never scrolls. An
earlier destination outside the viewport is necessarily a jump. The viewport itself moves only
forward unless a jump commits.

## 15. State and confidence contract

Tracking state reports evidence quality; it must not create another movement state machine.

- `acquiring` means a location is still being established.
- `tracking` means a location or transition has sufficient commitment.
- `uncertain` means local quality is weak or a challenger is becoming credible.
- `lost` follows a sustained streak of poor new-gesture evidence.

Uncertain and lost states hold the public marker and viewport. A credible challenger may still
commit a jump without waiting for `lost`; that is necessary for responsive relocation.

## 16. Performance and storage contract

The score may be long, and MIDI note-ons are latency-sensitive. Reference compilation may do
more work once, but per-event work must stay bounded.

Current choices:

- `UInt128` stores all 128 MIDI pitches without heap allocation.
- Inline three-lane masks store both, left, and right interpretations.
- Exact chord postings, exact two-gesture fingerprints, per-pitch postings, and precomputed
  hand-specific successors avoid score scans.
- Exact repeated matches are sampled across the whole score rather than taking a prefix.
- Nonexact lookup starts from the rarest observed pitch and ranks a bounded, score-wide sample.
- Acquisition and challenger candidate counts are bounded.
- The challenger beam, recent history, and provisional tail are bounded.
- No event may linearly scan every score moment merely because the played pitch is common.

Maintain these properties during refactors. Avoid per-moment reference objects or transient
arrays on the hot path when inline masks or fixed bounded storage suffice. Validate changes in a
release build and retain a long repetitive-score stress case.

## 17. Component ownership

Files under `Sources/IO` have intentionally narrow responsibilities:

- `EngravingReference.swift`: public immutable score/layout input and validation.
- `EngravingScoreFeatures.swift`: compiled gestures, masks, fingerprints, postings, and
  successors.
- `PerformanceGestureAssembler.swift`: conversion of serialized MIDI into physical gestures.
- `PerformanceTimingModel.swift`: robust tempo, chord-span, dwell, and articulation evidence.
- `EngravingAlignmentModel.swift`: acquisition, monotone incumbent, challengers, hand inference,
  confidence, and movement classification.
- `EngravingPresentationPolicy.swift`: `displayBeat`, compact plausible range, and viewport
  behavior.
- `EngravingScoreFollower.swift`: public façade, lifecycle, event routing, and public invariants.

Do not merge presentation decisions into alignment scoring. Candidate weights must not directly
move the scroll view, and viewport state must not reinforce musical candidate likelihood.

## 18. Hard invariants

Every implementation change must preserve these unless the product owner explicitly changes the
contract:

1. The established local incumbent never transitions backward.
2. Ordinary forward tracking never publishes backward movement.
3. One physical chord cannot consume multiple score moments.
4. A matching unplayed member of the current chord is not separated by a timeout.
5. One wrong or passage-like gesture cannot establish relocation.
6. A relocation needs one uninterrupted, confirmed post-change episode; evidence separated by
   contradiction does not accumulate.
7. Two independently ready destinations veto each other until later evidence resolves them.
8. Shared notes between two locations are neutral.
9. Pre-jump performance history does not score the destination path.
10. Timing cannot independently decide a chord boundary, match, replay, or jump.
11. Zero and invalid timing preserve pitch-only operation.
12. Left-only and right-only practice require no user mode selection.
13. MIDI ordering within a chord does not decide hand participation.
14. Without `didRelocate`, `displayBeat` never decreases.
15. Visible replay may move `beat` but never `displayBeat` or the viewport.
16. Backward playing outside the visible range commits only as a jump.
17. Uncertainty and lost tracking do not scroll.
18. Normal viewport motion occurs only after entry into the immediate next line.
19. Arbitrary or multi-line reframing is a jump.
20. `visibleRange` is never self-confirming musical evidence.
21. User scrolling resets; follower-driven scrolling does not.
22. Score and engraving lines remain owned by the same reference.
23. Per-event candidate work remains bounded with score length.
24. The separate general `ScoreFollower` remains untouched.

## 19. Current numerical policy

These values document the current implementation so agents can reason about behavior. They are
tunable parameters, not substitutes for the architectural invariants above. Change them only
with focused traces or tests demonstrating the tradeoff.

| Area | Current policy |
| --- | --- |
| Acquisition candidates | 18 per hand mode |
| Challenger seeds | 12 per hand mode |
| Challenger beam | 28 paths |
| Recent gesture history | 5 gestures |
| Provisional correction tail | 3 indices |
| Minimum local match | `0.58` |
| Local advance margin | `0.35` |
| Insertion penalty | `0.7` |
| One-score-moment deletion penalty | `2.7` |
| Challenger restart penalty | `0.65` |
| Jump evidence | `3.0` |
| Visible replay evidence | `4.1` |
| Minimum coherent post-change episode | 3 resolved physical gestures |
| Minimum distinguishing observations within that episode | 2 |
| Minimum challenger average quality | `0.62` |
| Destination ambiguity | Every independently ready destination vetoes the others |
| Block-chord completion baseline | `0.72` |
| Rolled-chord completion baseline | `0.82` |
| Next-chord membership baseline | `0.45` |
| Maximum timing boundary adjustment | `±0.08` |
| Nonexact posting probes | At most 8 times the requested candidate count |

Pitch similarity, transition motion, visibility priors, mode-change penalties, mismatch streaks,
and timing compatibility have additional bounded weights in their owning component. Keep weights
near the evidence they govern rather than centralizing them into an opaque global score.

## 20. Required behavioral coverage

Do not judge a model change only with a clean ascending melody. At minimum preserve focused
coverage for:

- latest post-reset viewport acquisition;
- stronger music overriding the viewport prior;
- right-only and left-only following;
- inactive-hand notes not advancing one-hand mode;
- hand inference independent of chord note order;
- normal similar passages never moving backward;
- one anomalous anchor remaining an insertion;
- coherent distinguishing gestures activating a remote passage;
- two remote-like gestures remaining a probe until a coherent confirmation;
- contradictory local recovery ending a relocation episode;
- equally plausible repeated destinations vetoing relocation;
- remote passages that share local chord tones;
- relocation before complete local failure;
- replay inside the viewport versus jump outside it;
- stable `displayBeat` during replay;
- viewport advancement only after next-line entry;
- block and rolled chords consuming one moment;
- deliberately slow rolled chords after tempo learning;
- decoded-event timestamp preservation;
- zero, equal, nonmonotonic, variable, and widely separated timestamps; and
- bounded work on a long repetitive score.

The current focused suite is `EngravingScoreFollowerTests`. Existing unrelated package tests are
not evidence for these contracts. When fixing a real trace, add a focused regression that states
the performer-facing behavior rather than mirroring private implementation details.

## 21. Change-review checklist for agents

Before changing the model:

1. Classify the problem as gesture assembly, local alignment, global relocation, hand inference,
   timing, or presentation.
2. Verify whether the proposed evidence is available before or only after the decision it would
   influence; avoid feedback loops.
3. Decide whether the change affects musical `beat`, visible `displayBeat`, viewport behavior, or
   more than one of them.
4. Test the change against mistakes and repeated passages, not only its motivating trace.
5. Confirm that one MIDI gesture cannot earn multiple confirmations.
6. Confirm that invalid timing still produces the same pitch-driven class of behavior.
7. Check worst-case event complexity and allocations.
8. Update this contract and the public integration guide if semantics change.

Do not fix an alignment issue by:

- adding backward edges to the local incumbent;
- making replay, forward, and jump peer states again;
- allowing one distinctive note to relocate;
- using absolute similarity where relative evidence is required;
- counting common notes as evidence for a remote occurrence;
- using history from before a possible jump as though it preceded the destination;
- introducing a chord timeout;
- letting `visibleRange` confirm the follower's own location during tracking;
- scrolling from raw `beat`; or
- tuning thresholds without addressing the structural cause.

The intended optimization target is a resilient musical assistant whose visible behavior feels
calm and predictable to a performer, not a cursor that reacts maximally to every new MIDI event.
