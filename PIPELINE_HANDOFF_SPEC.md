# Pipeline Handoff Spec (draft)

App Group file‑drop by which **AntennaHead** hands a pipeline definition to
**ControlBooth** for import and/or execution, replacing the removed
"Select Custom Task" UI in AntennaHead.

Status: draft for discussion. Nothing below is implemented.

---

## 1. Why a file drop (not an AppleEvent payload)

The existing cross‑app control channel is AppleEvents (`AntennaHeadClient` →
`'AntH'` handlers; ControlBooth's `.sdef` `StartPipelineCommand` etc.). That
channel is fine for *verbs on things that already exist* ("start the pipeline
named X"). It is a poor fit for shipping a whole nested pipeline definition:
descriptor plumbing for arrays of arrays of strings, size limits, no natural
place to stage it.

A file in the shared App Group container carries the structured payload; a
short poke (URL scheme or AppleEvent) carries only *"handoff `<id>` is
waiting"*. Belt = data, suspenders = trigger.

## 2. Container location

App Group `group.com.dsward.antennahead` is **already** declared in both
`AntennaHead/AntennaHead/AntennaHead.entitlements` and
`ControlBooth/ControlBooth.entitlements`, and already used for `Recordings/`
and `Logs/`. No entitlement work.

```
<group container>/Handoff/
    inbox/      AntennaHead writes here, ControlBooth consumes
    status/     ControlBooth writes here, AntennaHead consumes
    processed/  ControlBooth moves consumed inbox files here (optional; else delete)
```

Resolve the container with
`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`,
**off the main thread** — a cold call has been observed to take ~35 s from a
freshly‑signed process (see the `LogStore.configure` note in the umbrella
memory). Create `Handoff/inbox` and `Handoff/status` with
`createDirectory(withIntermediateDirectories: true)` on first use, same as
`SharedRecordingFolder.url`.

## 3. Inbox file

**Name:** `<id>.pipeline.json`, where `<id>` is a UUID string.
**Write atomically:** write `inbox/.<id>.pipeline.json.tmp`, then
`FileManager.replaceItemAt` / `rename(2)` into place (same filesystem → atomic).
Readers MUST ignore dotfiles.

```jsonc
{
  "specVersion": 1,
  "id": "7C4B0E1A-9F3D-4E2B-8A11-2D9C6F0A1B23",
  "createdAt": "2026-09-02T14:33:00Z",   // ISO‑8601 UTC
  "source": "AntennaHead",
  "action": "import",                     // see §5
  "ttlSeconds": 120,                      // consumer ignores the file after createdAt + ttl

  "pipeline": {
    "name": "FM 91.9 MHz → custom",
    "destinationHost": "127.0.0.1",       // required
    "destinationPort": 8123,              // required — AntennaHead's live PCM‑in port at handoff time (see §9)
    "tasks": [
      { "path": "rtl_fm_localradio",
        "arguments": ["-f", "91900000", "-M", "fm", "-s", "171000", "-r", "48000", "-"] },
      { "path": "FMDeemphasis",
        "arguments": ["--rate", "48000"] }
    ]
  },

  "audioHints": {                          // optional; AntennaHead‑side params, consumer MAY ignore
    "sampleRate": 48000,
    "channels": 2
  }
}
```

### 3.1 `pipeline.tasks` is the already‑shared format

Each element is exactly the `{ "path", "arguments" }` shape that
`PipelineStage.StageDTO` in
`ControlBooth/Services/Database/Pipeline.swift` already decodes, and that
AntennaHead already stores in `CustomTask.taskJson`. The `pipeline` object,
because it has a `tasks` key, is directly consumable by the existing
`PipelineStage.decode(_:)` path with no new parser — feed it the substring for
`pipeline` (or refactor `decode` to take the already‑parsed object).

The auto‑appended terminal `PCMUDPSender` stage is **not** included — ControlBooth's
`PipelineRunner.start` adds it from `destinationHost`/`destinationPort`, same as
for a hand‑built pipeline. Do not put a UDP sender in `tasks`.

`destinationHost` and `destinationPort` are **required**. AntennaHead sends the
port its `PCMUDPReceiver` for ControlBooth PCM is actually bound to at handoff
time — ControlBooth never hardcodes or guesses one. A file missing either
field, or with `destinationPort` outside 1–65535, is `rejected` (§4).

That port is stable in practice (see §9): it defaults to **6019**
(`PortSettings.controlBoothUDP` → `SDRController.controlBoothReceivePort`),
persists in `app_config` under `AntennaHeadControlBoothPort`, and is never
auto‑assigned or bumped. So an `import`ed pipeline row stays valid across
AntennaHead launches. Sending it explicitly is belt‑and‑braces against a future
config change, not a workaround for churn.

### 3.2 Tool path rules

Unchanged from `PipelineRunner.resolveToolPath`: a bare name resolves against
`Contents/Helpers/`; anything with a `/` is used as‑is (ControlBooth is
unsandboxed). AntennaHead should emit **bare helper names** for anything both
apps vendor (`FMDeemphasis`, `PCMMixer`, `rtl_fm_localradio`, …) and absolute
paths only for host tools the user configured. A handoff file is exactly as
trusted as the App Group itself — only same‑team apps holding the entitlement
can write there — so no extra path sanitising beyond what `StageEditorView`
already allows.

### 3.3 UDP ports *inside* stage arguments

`destinationPort` is only the terminal `PCMUDPSender` target. A stage can carry
its own ports in `arguments` — most notably `PCMMixer --input udp:<port>
[--input udp:<port> …] --control-port <n>` for an N‑input mix. Those are opaque
argument strings to this spec: they travel verbatim and ControlBooth does not
parse, validate, or rewrite them. Rules for the sender (AntennaHead):

- Any such port must be a concrete number chosen by the sender, never a
  placeholder or an "allocate one for me" sentinel — there is no negotiation
  channel back.
- It's the sender's job to keep them distinct from `destinationPort`, from each
  other, and from ports already in use on the box. If a future AntennaHead
  feature auto‑allocates a mixer input port, it must resolve it to a real free
  port *before* writing the handoff file and bake that number into `arguments`.
- ControlBooth being unsandboxed, a mixer stage binding those UDP inputs just
  works; no entitlement concern.

## 4. Status file

**Name:** `status/<id>.status.json`, atomic write, same dotfile rule.
ControlBooth writes it at least once (terminal state); MAY write an interim
`accepted` before `started`.

```jsonc
{
  "specVersion": 1,
  "id": "7C4B0E1A-9F3D-4E2B-8A11-2D9C6F0A1B23",
  "state": "started",        // accepted | started | rejected | failed
  "controlBoothPipelineName": "FM 91.9 MHz → custom",   // the name actually created (may be de‑duped)
  "pipelineID": 42,          // ControlBooth DB row id, when known
  "message": "Imported and started.",
  "updatedAt": "2026-09-02T14:33:02Z"
}
```

| state      | meaning                                                              |
|------------|--------------------------------------------------------------------- |
| `accepted` | file parsed, pipeline row created/updated, not yet started           |
| `started`  | `PipelineRunner.start` succeeded                                     |
| `rejected` | bad `specVersion`, malformed JSON, empty `tasks`, missing/invalid `destinationHost`/`destinationPort`, expired ttl |
| `failed`   | started but a stage errored (`toolMissing`, `senderMissing`, …)      |

AntennaHead polls `status/<id>.status.json` (short‑lived, e.g. 500 ms for
≤10 s) after dropping the file, surfaces `message`, then deletes the status
file. It also sweeps orphan `status/*` older than a few minutes.

## 5. `action` semantics

| action            | ControlBooth behaviour                                                        |
|-------------------|----------------------------------------------------------------------------- |
| `import`          | create a new pipeline row; if `name` collides, append " 2", " 3", … Do not run. |
| `importAndStart`  | as `import`, then `PipelineRunner.start` the new row.                          |
| `replaceAndStart` | if a pipeline with `name` exists, overwrite its `stages_json` / destination in place; else create. Then start. Restart it if already running. |

AntennaHead's three remaining Audio Devices actions map naturally:
"send to ControlBooth" from a quick‑tune context → `importAndStart`; a plain
"edit this in ControlBooth" → `import`.

## 6. Trigger

After the inbox file is in place, AntennaHead pokes ControlBooth:

1. **Preferred — URL scheme.** ControlBooth registers `controlbooth:` (Info.plist
   `CFBundleURLTypes`). AntennaHead calls
   `NSWorkspace.shared.open(URL(string: "controlbooth://handoff?id=<id>")!)`.
   Launches ControlBooth if not running; works from the sandbox with no
   Automation consent prompt. ControlBooth's URL handler scans `inbox/` (or just
   `<id>`).
2. **While ControlBooth is already running** it also keeps a
   `DispatchSource.makeFileSystemObjectSource` (or `FSEventStream`) watch on
   `inbox/`, so a missed/again‑delivered poke is harmless — the watch picks the
   file up regardless.
3. **Fallback — AppleEvent.** Extend the existing channel with a
   `handoff` verb. Heavier: AntennaHead would need
   `com.apple.security.automation.apple-events` + `NSAppleEventsUsageDescription`
   and would trip a one‑time "AntennaHead wants to control ControlBooth" prompt.
   Only worth it if the URL scheme proves unreliable.

Idempotency: ControlBooth keeps a set of processed `id`s (in‑memory is enough;
the ttl + `processed/` move covers restarts) and ignores a second delivery of
the same `id`.

## 7. ControlBooth not installed

Before writing anything, AntennaHead checks
`NSWorkspace.shared.urlForApplication(toOpen: URL(string: "controlbooth://")!)`
(or `...withBundleIdentifier: "com.dsward.ControlBooth"`). If nil: no file,
show "ControlBooth isn't installed" with a link, and — per the app‑division
plan — hide or disable the "send to ControlBooth" controls entirely.

## 8. Lifecycle summary

```
AntennaHead                          ControlBooth
-----------                          ------------
resolve container (off main)
write inbox/.<id>.tmp
rename → inbox/<id>.pipeline.json
NSWorkspace.open controlbooth://…  → (launch if needed)
                                     URL handler / FS watch sees <id>
                                     parse; validate specVersion, tasks
                                     create/replace Pipeline row
                                     write status/<id> = accepted
                                     PipelineRunner.start (if action starts)
                                     write status/<id> = started | failed
poll status/<id> (≤10 s)
show message; delete status/<id>
                                     move inbox/<id> → processed/ (or delete)
periodic: sweep own orphan status/*  periodic: sweep expired inbox/*, processed/*
```

## 9. Open decisions

- **Stale destination port on a re‑used pipeline row.** *Resolved — not a real
  problem.* The premise ("AntennaHead's PCM‑in port floats") was wrong. That
  port does not float: it is a fixed default of 6019 in three places
  (`PortSettings.controlBoothUDP`, `SDRController.controlBoothReceivePort`, the
  `updatePorts` parameter default), persisted in `app_config` as
  `AntennaHeadControlBoothPort` and reloaded verbatim on every launch by
  `PortSettings.load()`. Nothing auto‑assigns it, binds it ephemerally
  (port 0), or bumps it on collision — the only retry path in the codebase
  (`AntennaHeadHTTPServer`'s `EADDRINUSE` backoff) rebinds the *same* port.

  It is now a **user‑editable setting**. As of the change that accompanied this
  spec (AntennaHead `3bc59f3`), the "Change Configuration…" sheet
  (`EditConfigurationSheet`, "Other Ports" section) has editable fields for
  **both** `controlBoothUDP` and `airPlayUDP` — previously each was persisted in
  `PortSettings`/`app_config` but had no editing UI, so short of a manual
  `app_config` edit they were effectively constants (6019 and 6022). Both are
  read‑only in the Configuration list and now editable in the sheet;
  `portsAreValid` enforces non‑zero and mutually distinct across all eight
  listener ports before Save is enabled. They still persist and reload verbatim
  on launch, so the only way either moves is a deliberate edit. An `import`ed
  pipeline row therefore keeps working across AntennaHead restarts. AntennaHead
  still sends the value in every handoff so ControlBooth stays decoupled from
  the number, but no ephemeral‑row / re‑query / port‑pinning mechanism is
  needed.

  **Consequence of it now being editable:** if the user changes it in the
  sheet, any already‑`import`ed pipeline rows on the ControlBooth side hold the
  old port and send PCM nowhere until re‑sent from AntennaHead. This is
  acceptable — same class of staleness as editing any saved connection detail —
  and ControlBooth surfaces it: a run against a dead destination shows up
  through the `failed` status path / `PipelineRunner` logging, not silently.
  If this becomes a nuisance in practice, the lightest fix is for ControlBooth
  to re‑query the current port over the AppleEvent channel just before starting
  a handed‑off row.

  (Whatever "6019/60xx floating" impression originally prompted this was likely
  a mix‑up with the transient `EADDRINUSE` retry window on the HTTP port, or
  with stale helper processes from the PCM memory‑leak episode holding sockets.)
- **`audioHints`.** Keep as advisory only, or drop? ControlBooth's `Pipeline`
  has no per‑pipeline sample‑rate/buffer fields; AntennaHead's `CustomTask`
  does. If ControlBooth never uses them, omitting them keeps the format honest.
- **`processed/` vs delete.** Keeping consumed files aids debugging but needs a
  sweeper. Delete‑on‑consume is simpler.
- **Spec home.** This file, or split into `ControlBooth/HANDOFF.md` +
  a pointer from `AntennaHead/README.md`.
```
