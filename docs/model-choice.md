# Why `large-v3-turbo`

Three candidates, measured on real recordings of spontaneous Portuguese speech
with English technical terms in the middle, not on lab audio. A whole dictation
in another language sits outside that coverage.

## The rule, applied in this order

1. **Discard** every model that gets vocabulary wrong to the point of requiring
   manual editing. Latency does not buy quality: if it creates rework, the gain
   from dictating disappears.
2. Among those left, the fastest wins.
3. If none stays within the ceiling, do not pick one by shouting. Reopen the
   architecture discussion.

**Ceiling: 1500 ms**, from the end of the speech to the finished text. Above
that the flow breaks and the person goes back to typing.

## Latency

Whisper processes in **30-second windows**: a 5 s dictation costs the same as a
25 s one. There is no cost per second of audio. There is a cost per window.

The numbers discount the model load, because the app keeps it warm. And they
come from the process's internal stopwatch, not from wall-clock time: wall-clock
includes process spawn and reading the model from disk, which do not exist in
the app.

| Model | Dictation up to 30 s | Per window | 1500 ms ceiling |
|---|---|---|---|
| large-v3-turbo-q5_0 | 782 ms | 820 ms | within |
| medium-q5_0 | 737 ms | 856 ms | within |
| small-q5_1 | 290 ms | 346 ms | within |

**Latency does not discriminate.** All three pass with room to spare, and the
difference between turbo and medium is within the noise of a single run. The
decision is about quality.

*(In the real app, with the model already warm, a short dictation measured
599 to 609 ms.)*

## Quality

What separated the models was vocabulary: an English system name in the middle
of a Portuguese sentence, a business term, and an infrequent verb.

| Error type | turbo | medium | small |
|---|---|---|---|
| English product name, two words | correct | spelling swapped | correct |
| Common noun ("investigação") | correct | correct | **another word** |
| Verb ("disparar") | correct | correct | **another verb** |
| Business term | correct | invented spelling | invented spelling |
| Infrequent verb | wrong | correct | wrong |
| Hallucination | none | none | **invented a caption** |

## Decision

**`large-v3-turbo-q5_0`**: 547 MB, quantized locally from OpenAI's checkpoint.

**Justification, in the order of the rule:**

1. **`small-q5_1` is disqualified**, despite being 2.7× faster. It does not get
   spelling wrong, it gets **meaning** wrong: it swapped one noun for another
   and one verb for another, changing what the sentence said. And it
   hallucinated a music caption at the end of a long audio (which, in a
   dictation, would be invented text pasted into your document). Rule 1 is
   explicit.
2. **`medium-q5_0` also falls under rule 1.** It gets wrong precisely the
   vocabulary a technical dictation needs to preserve: product name and business
   term. Whoever dictates and has to correct a system name every time goes back
   to typing.
3. **`large-v3-turbo-q5_0` is what remains**, the only one to pass rule 1.

## Known limit: what happens above two windows, and what was hiding there

By the bench, the 1500 ms ceiling would **not** survive a dictation that occupies
more than one window: from the second one on the cost doubles, and turbo (820 ms
per window) would give 1640 ms. Only `small` would hold two windows.

In the app the projection did not hold: a 31 s dictation, two windows, measured
**1299 ms** on 2026-08-28 (`.vibeflow/backlog.md`, L1: five dictations read
from the app's log, ~614 ms fixed plus ~22 ms per second of speech). Within the
ceiling. Why the bench projects more than the app measures was not investigated.

Inside a single window the cost stays nearly flat: the four dictations of that
same reading, from 1.5 s to 19.4 s of speech, cost 612 to 698 ms. It is a
working note read off a log, not a reproducible bench.

**Until 2026-09-05 this section said that nobody had measured above two windows,
and that the limit was "not a defect". Both were wrong**, and a defect was living
in the gap. The app asked whisper for `no_timestamps`, which left the library
with nothing to compute the window advance from, so it stepped a blind 30 s and
dropped whole windows of speech. Measured over 460 s of synthesized speech with
the app's transcription parameters: 645 correct words of 1120 with the flag on,
1101 with it off. Over 404 s of recorded speech the distance was wider, 19% of
the words against 98%. The write-up is in
`.vibeflow/hotfixes/2026-09-05-long-dictation-loses-and-repeats-speech.md`, and
two regression tests cover it now.

Model choice had nothing to do with that, and it is worth saying plainly: every
model on this bench would have dropped the same windows.

What is left is the wait, and it is real. 404 s of speech costs about 13 s, close
to a second per window. The app sets no duration limit, and since 2026-09-05 it
draws whisper's own progress on the orb's border while a long transcription
runs.

## A finding that remains open

An infrequent verb from the domain came out wrong **consistently** in turbo and
small, and right in medium. No base model gets specific vocabulary right
reliably. It is the concrete evidence in favor of a custom vocabulary (initial
prompt), which this project now has (`Vocabulary.swift`, commit `43d968f`): the
terms go in as `initial_prompt`, and deterministic replacements run over the
finished text. Whether that fixes this verb was not measured
(`.vibeflow/backlog.md`, A3).

## How to reproduce

```bash
bash scripts/setup-bench.sh                  # builds the three models
bash scripts/record-fixture.sh 01-normal     # record your own samples
bash scripts/bench.sh                        # measures and prints the table
```

The bench aborts if inference falls back to the CPU: a time measured that way
is ~11× higher and does not represent the app. See `docs/pitfalls.md`.
