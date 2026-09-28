# AntennaHead Station Automation — design (first-hour prototype)

Status: written 2026-09-27. **The first-hour prototype is built and has been tested live**:
[dsward2/StationDirector](https://github.com/dsward2/StationDirector), checked out at `StationDirector/` in the umbrella.
Its README lists where the build departs from this design. The main differences:
- The director runs the audio graph itself; there are no ControlBooth pipelines.
- Lines are rendered ahead of time, so there's no long-running announcer stage and 6030 is unused.
- ControlBooth stays in "Receiving" mode, and the director switches the relay itself.
- **Segments never pause Music.** If an AirPlay stream to ControlBooth is paused
  for more than a few seconds, shairport-sync keeps a dead session, so segments mute the
  mixer and seek the track back to 0 instead of pausing.
Author: Douglas S. Ward, with Claude.

## How to use this doc to start a session

Paste something like this into a new Claude Code session opened on the
umbrella (`antennahead-umbrella/`):

> Read `antennahead-workspace/STATION_AUTOMATION_DESIGN.md`. We're building
> the first-hour prototype it describes. Start with the "Verify first"
> checklist in §8, report what you find, then build milestone M1.

Everything below is grounded in the code as of `main` on 2026-09-27; file
paths are relative to `antennahead-umbrella/`.

---

## 1. Goal

An automated, personal-use radio station that plays through AntennaHead's
existing stream (web UI, iOS, Watch, Apple TV): music from the user's Music.app
playlists, with a synthesized announcer who gives station IDs, time and
temperature, news headlines, and weather, and talks over the ends of songs the
way a real DJ does.

This is mostly **broadcast automation**, not AI: a scheduler working from an
hourly template (a "clock"). AI is used in one narrow, well-fenced place: writing the
announcer's short lines (§6).

**Personal use only.** Relaying Apple Music tracks to anyone outside the
household is a licensing problem. The station is for the user's own devices.

## 2. The first-hour prototype (scope)

One repeating hourly clock, Mon–Sun:

| Minute | Segment | Source |
|---|---|---|
| :00 | Top of hour: station ID, time, current temperature, 3 news headlines | speech (music paused) |
| :01–:29 | Music set from a chosen playlist; a short announcer line talked over the last ~8 s of each song | Music.app + speech over ducked music |
| :30 | Weather: short forecast | speech over ducked music, or music paused |
| :31–:59 | Music set continues, with announcer lines | as above |

Out of scope for the prototype (later milestones, §9): traffic, playing
ControlBooth's scheduled recordings into the clock, song selection by mood/time
of day, Watch/TV controls for the station, a ControlBooth UI for editing clocks.

## 3. What already exists (reuse, don't rebuild)

These are in place and working; the prototype is mostly wiring them together.

- **PipelineHelpers `PCMMixer`** (`PipelineHelpers/Sources/PCMMixer/main.swift`):
  N-input S16LE mixer. Input 0 is the clock master; others are buffered
  (silence on underrun). **Sidechain ducking** built in: `--duck-input <i>`
  attenuates every other input while input *i* has signal, with
  attack/release/hold envelope. Live control over UDP `--control-port`
  (`ratio`, `gain <i> <g>`, `gains`). This is exactly "announcer talks over
  the music".
- **PipelineHelpers `PCMSpeechSynth`**: TTS source. `--input udp:<port>` =
  each datagram is new text; **without `--repeat` it speaks each new text
  once, then goes silent** until the next datagram (verified in
  `main.swift` ~L445–480). Supports `--ssml` (prosody for modern voices),
  `--voice`, `--speech-rate`. Output is S16LE mono at `--rate` (default
  22050), real-time paced; needs a sox stage to reach 48 kHz / 2 ch.
- **Precedent:** AntennaHead's own filler already does speech-ducked-over-a-bed
  with these two helpers: `PCMSpeechSynth → sox → PCMUDPSender` into the filler
  `PCMMixer` input 1 on UDP 6027, `--duck-input 1`, control on 6028 (see
  `AntennaHead/AntennaHead/Services/SDRController.swift`, `fillerAnnouncePCMPort`
  / `fillerMixerControlPort`). **Copy its sox arguments and duck settings as
  the starting point.**
- **`PCMUDPReceiver --fill-silence --rate 48000 --channels 2`**: turns a bursty
  UDP source into a continuous paced stream, suitable as the mixer's clock
  master.
- **ControlBooth AirPlay receiver** (`ControlBooth/.../AirPlayReceiverService.swift`,
  AirPlayReceiver package): shairport-sync + sox, relays decoded PCM to
  `AirPlaySettings.destinationHost:destinationPort` (default 127.0.0.1:6019 =
  AntennaHead). **The destination port is configurable**, so Music.app's
  audio can be pointed at the station mixer instead of straight at AntennaHead.
- **ControlBooth pipelines** (`Pipeline.swift`, `PipelineRunner.swift`): user-
  defined stage chains, each with its own `destinationHost/destinationPort`;
  `startAnnouncingToAntennaHead` makes AntennaHead open its 6019 receiver
  first. Per-stage `--control-port` is already parsed by `Pipeline.swift`.
- **ControlBooth `Scheduler`** + `ScheduledEvent` (day bitmask, start seconds,
  duration, recording options). Suitable for "run the station 6 am–midnight";
  **not** for minute-level clock segments, which the new director owns.
- **Now Playing text**: `AntennaHeadClient.announceNowPlaying(_:pipeline:)`
  (`'NpUp'` AppleEvent) already pushes a now-playing string to AntennaHead,
  which every client (web, iOS, Watch, TV) shows. Use it for "Song — Artist".
- **Captions**: AntennaHead's `PCMTranscriber` would caption the announcer for
  free, since the station is just another source.

## 4. Architecture

```
 Music.app ──AirPlay──▶ ControlBooth AirPlay receiver (shairport-sync + sox)
                              │ relay to destinationPort = 6031 (not 6019)
                              ▼
 ┌──────────────────── "Station" ControlBooth pipeline ─────────────────────┐
 │ PCMUDPReceiver --port 6031 --fill-silence --rate 48000 --channels 2       │
 │   │ stdout (music bed; clock master)                                      │
 │   ▼                                                                       │
 │ PCMMixer --input stdin --input udp:6032 --duck-input 1                    │
 │          --control-port 6033 [--duck-* from the filler's settings]        │
 │   │                                                                       │
 │   ▼  (ControlBooth appends PCMUDPSender → AntennaHead 6019)               │
 └───────────────────────────────────────────────────────────────────────────┘
                              ▲ udp:6032 (48 kHz / 2 ch S16LE)
 ┌──────────── "Announcer" ControlBooth pipeline (dest port 6032) ───────────┐
 │ PCMSpeechSynth --input udp:6030 --ssml --voice <premium voice>            │
 │   ▼ sox (22050 mono → 48000 stereo, same args as the filler feeder)       │
 └───────────────────────────────────────────────────────────────────────────┘
                              ▲ udp:6030 (text / SSML, one datagram per line)
 ┌────────────────────────── Station Director (new) ─────────────────────────┐
 │ clock/scheduler · Music.app via AppleScript · NWS weather · RSS headlines │
 │ · Foundation Models for announcer copy · mixer control on udp:6033        │
 │ · now-playing via AntennaHeadClient.announceNowPlaying                    │
 └───────────────────────────────────────────────────────────────────────────┘
```

Port choices 6030–6033 are the next free ones after the documented 6019–6029;
**add them to `antennahead-workspace/NETWORK_PORTS.md`** when they become real.

### Where the Station Director lives

- **Prototype: a standalone Swift command-line tool** (a small SwiftPM package,
  e.g. `StationDirector/` in the umbrella, not yet a repo). It's fast to iterate on, and
  unsandboxed, so it can drive Music.app with AppleScript (it will need the
  Automation permission for Music). It talks to everything over UDP, AppleScript, and HTTP,
  so it doesn't need to live inside either app yet.
- **Later:** fold it into ControlBooth as a service with a UI, once the design
  has settled. ControlBooth is the right long-term home: unsandboxed, already
  runs pipelines and schedules, already talks to AntennaHead. AntennaHead is
  sandboxed, which makes scripting Music.app painful.

## 5. Station Director: responsibilities

### 5.1 Music.app (AppleScript via `NSAppleScript` or `osascript`)
- Select the output: `set current AirPlay devices to {AirPlay device "<receiver name>"}`
  (the name shown in ControlBooth's AirPlay settings). Verify the exact name.
- `play playlist "<name>"`, `pause`, `play`, `next track`, `shuffle enabled`.
- Poll about once a second: `player state`, `player position`, `duration of current track`,
  `name`/`artist`/`album of current track`. Derive "seconds remaining".
- Consider turning **crossfade** on in Music settings; it's free polish.
- Prefer the **mixer** for ducking over Music's `sound volume`: AirPlay volume
  changes are sent to shairport-sync and are coarse and laggy.

### 5.2 Announcer
- Send a UDP datagram (UTF-8, SSML when `--ssml`) to 127.0.0.1:6030. One line
  per datagram. The mixer ducks automatically while speech is present.
- **Timing:** estimate speech duration (word count ÷ ~2.6 words/s at default
  rate; calibrate once), and schedule the talk-over to start at
  `remaining − estimate − 1 s`. Keep lines short (≤ 12 words) for talk-overs.
- **Long segments** (top of hour, weather): `pause` Music, speak, then wait
  for the estimate plus a margin, then `play`. Or, better, detect the end of speech
  (see §8, item 6).

### 5.3 Data sources
- **Time:** local clock. Say it the way people do ("It's 4:15" or "quarter past four").
- **Weather: National Weather Service**, free and no key needed, but it requires a
  `User-Agent` header with contact info (use a GitHub URL, not a personal email):
  `GET https://api.weather.gov/points/{lat},{lon}` → `forecast`,
  `forecastHourly`, `observationStations` URLs; current temperature from the
  nearest station's `/observations/latest`. Cache the points lookup. The
  lat/lon is a config value (ask the user; they're in central Arkansas).
- **Headlines:** RSS 2.0 / Atom via `XMLParser`. The prototype keeps its own
  feed-URL list in config. (AntennaHead has `RSSFeedService` + subscribed feeds,
  but they live in its sandbox DB; reusing them via AntennaHead's HTTP API is
  a later nicety.)

### 5.4 Now Playing + control
- On each track change, send `"<title> — <artist>"` through AntennaHead's
  `'NpUp'` path, so the TV, Watch, and web show the song. From the CLI,
  replicate the AppleEvent (see `ControlBooth/.../AntennaHeadClient.swift`
  `send(eventID:)`, class `'AntH'`) or shell out to `osascript`.

### 5.5 Configuration (JSON file for the prototype)
`station.json`: station name and slogan, playlist name(s), AirPlay receiver
name, lat/lon, feed URLs, voice identifier, speech rate, talk-over lead
seconds, duck settings, and the hour clock as an ordered list of
`{minute, segment}`.

## 6. AI: where it's used, and the guardrail

Use Apple's on-device **Foundation Models** framework (`LanguageModelSession`,
guided generation with `@Generable`) for:
- Talk-over lines: *"That was **Dreams** by **Fleetwood Mac**. It's 72 and
  clear at 4:15. Here's **Steely Dan**."*
- Rewriting RSS titles into one-sentence radio copy.
- Varying the station ID so it isn't identical every hour.

**Guardrail: facts come from data, the model only does the wording.** Pass the
model a struct of facts (title, artist, next title/artist, time string,
temperature, conditions) and generate into a `@Generable struct AnnouncerLine
{ var text: String }`, instructed to use only the provided facts, with no song
trivia, dates, or chart claims (it will invent them). Then post-check that every
proper noun in the output is in the facts; if not, fall back to a template line.

Always keep **template fallbacks**, for when the model is unavailable
(`SystemLanguageModel.default.availability`), slow, or fails the post-check.
The station must never go silent because of the model.

## 7. Voice quality

The voice makes or breaks it. Install a **Premium** or **Enhanced** voice
(System Settings › Accessibility › Spoken Content › System Voice › Manage
Voices), or use the user's **Personal Voice** if they've made one (it requires an
authorization request). List the available voices with `PCMSpeechSynth --list-voices`.
Use SSML `<prosody>` and `<break>` for pacing (modern voices ignore the classic `[[ ]]`
commands). See also `AntennaHead/.../SpeechVoicePreference.swift`.

## 8. Verify first (at the start of the build session)

1. **AirPlay relay to a custom port:** set ControlBooth's AirPlay
   `destinationPort` to 6031 and confirm the relay targets it, and that nothing
   assumes 6019 (e.g. the "announce to AntennaHead" dance in
   `AirPlayReceiverService`, which should now be skipped or pointed at the
   Station pipeline instead).
2. **Concurrent ControlBooth pipelines:** Station (→ 6019) and Announcer
   (→ 6032) must run together. Check `PipelineRunner` allows two at once and
   that only the one sending to 6019 announces to AntennaHead.
3. **Music.app → ControlBooth AirPlay** with Apple Music (not just local
   files) and the receiver in "Receiving" mode, not "Relayed". Confirm
   AppleScript `current AirPlay devices` can select it.
4. **Foundation Models availability** on this Mac mini (M1, macOS 27, the
   Apple Intelligence setting), and check the macOS 27 SDK's
   `FoundationModels` interface for API changes since macOS 26.
5. **Duck tuning:** start from the filler's `--duck-*` values; judge by ear.
   Music should drop to about −12 dB under speech and recover smoothly.
6. **End-of-speech signal:** `PCMSpeechSynth` has no "done" message. Options:
   estimate duration (simplest); have the director render the utterance's
   length first (AVSpeechSynthesizer `write` → sample count); or add a small
   `--done-port` to PCMSpeechSynth that sends `done <generation>` after
   `writePaced`. The last is the most robust, and is a small PipelineHelpers PR.
7. **Latency:** PCMSpeechSynth renders the whole utterance before playing
   (~hundreds of ms). Fine, but include it in the talk-over lead time.

## 9. Milestones

- **M1: Audio path.** Create the Station and Announcer pipelines in ControlBooth
  (by hand in its UI), point AirPlay at 6031, play a Music playlist, and
  `echo "Testing one two" | nc -u -w0 127.0.0.1 6030`: hear the music duck
  under the voice on an AntennaHead client. No director code yet.
- **M2: Director skeleton.** CLI with `station.json`, Music.app control and
  polling, templated talk-over lines at song ends, now-playing push.
- **M3: The clock.** Top-of-hour ID + time + temperature + 3 headlines (NWS +
  RSS), and weather at :30. Runs unattended for an hour.
- **M4: Announcer copy with Foundation Models,** with the guardrail and fallbacks.
- **Later:** traffic (MapKit travel times for set routes; the ARDOT
  IDriveArkansas feed is worth a look); scheduled recordings as clock segments
  (ControlBooth's `SharedRecordingFolder` + `PCMFilePlayer`); mood / time-of-
  day playlist choice; station start/stop from TV/Watch; fold the director into
  ControlBooth with a clock editor UI; a dead-air watchdog (SoundAnalysis on
  the mixer output).

## 10. Open questions for the user

- Station name / call-letters style and slogan for the ID.
- Which playlists; shuffle or in order.
- Lat/lon (or town) for weather; which news feeds.
- Hours of operation (the ControlBooth `ScheduledEvent` window) vs always-on.
- Talk-over on every song, or every 2–3 songs.

## 11. Working rules for the build session (from past sessions)

- Umbrella repos are separate GitHub repos under `dsward2`; work on a branch,
  open a PR, and merge only when the user says so. Commit attribution per the session's
  instructions.
- Building ControlBooth into its **running** Debug DerivedData kills its
  helper processes (sox, shairport-sync). Build with a separate
  `-derivedDataPath`.
- The user's AntennaHead web UI has **login on**. Don't enter the credentials;
  ask the user to sign in where needed.
- RTL-SDR dongles are identified by EEPROM serial, not index.
