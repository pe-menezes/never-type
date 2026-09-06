# Bench fixtures

Reference audio in **your voice**, used to measure latency and judge quality in
technical pt-BR. Nothing here goes to git besides this README.

## How to record

```bash
scripts/record-fixture.sh 01-normal-speech
scripts/record-fixture.sh 02-technical-terms 18
scripts/record-fixture.sh 03-short-sentence 12
```

With no argument, the script lists the available audio devices. The default is
device `[0]`; pass the index as the third argument to use another one.

The script already records in 16 kHz mono 16-bit PCM, which is what `whisper-cli`
consumes. Do not record in QuickTime: it comes out at 44.1 kHz stereo and the
bench rejects it.

## What to record

At least three clips, covering **short and long dictation**. The variation is the
point: Whisper processes in 30-second windows, and only by recording below and
above that step can you see it. If they all have the same length, the bench
measures a constant and you never find out.

The rule is to speak the way you really speak: normal pace, with the hesitations
that exist. A polished announcer's delivery measures a scenario that is not yours.

**01, normal speech.** A message the way you would send it on Slack. Everyday
Portuguese, without heavy jargon.

**02, technical terms.** The hard case, and the one that decides the model. Mix
Portuguese with English terms the way it comes out naturally, and include the
name of at least one internal system. Something like this (in Portuguese, since
that is what the app transcribes):

> "Subi o deploy em staging mas o pod tá em CrashLoopBackOff, acho que é o
> health check. Vou olhar o dashboard no Datadog e depois abro uma issue pro
> time de plataforma."

*(Roughly: "I pushed the deploy to staging but the pod is in CrashLoopBackOff, I
think it's the health check. I'll look at the Datadog dashboard and then open an
issue for the platform team.")*

**03, short sentence.** One or two sentences, the length of most real
dictations. Short sentences are where the model errs most and where latency
shows most.

**04, long dictation.** More than four minutes of continuous speech. This one is
not for the bench: it is the input of `RecordedLongDictationTests`, and it exists
because whisper processes in 30-second windows and the way it drops whole windows
only separates a working build from a broken one well above two of them. Measured
2026-09-05 on a 404 s recording: a build with `no_timestamps` on kept 19% of the
words, and it did it without repeating a single sentence, so the text gave no
sign of the loss. See
`.vibeflow/hotfixes/2026-09-05-long-dictation-loses-and-repeats-speech.md`.

Any continuous recording above four minutes works here. The test measures
characters per second of audio and never reads the content, so there is no
transcript of this fixture anywhere and a failure prints numbers only.

## What NOT to record

No personal or sensitive data: documents, contract numbers, client names,
credentials. For those, the cost of a slip is not worth anything.

Technical vocabulary and system names, on the other hand, are exactly what the
bench needs to measure: there is no way to evaluate whether the model gets your
jargon right with made-up sentences. So real speech is acceptable, with one
consequence:

This directory is in `.gitignore`, and the transcriptions in `bench-out/` too. Do
not force `git add`. If you quote excerpts in a versioned analysis, remember they
leave your computer along with the repository.
