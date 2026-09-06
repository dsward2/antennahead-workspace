# AntennaHead Umbrella — Network Port Report

Surveyed repos: `AirPlayReceiver`, `AntennaHead`, `ControlBooth`, `LiveAudioServer`, `PipelineHelpers`, `antennahead-librtlsdr`.

System summary: AntennaHead (sandboxed) is the primary SDR app with a web UI and an
embedded LiveAudioServer subprocess. ControlBooth (unsandboxed) runs arbitrary audio pipelines
and its own AirPlay receiver, and talks to AntennaHead over Apple Events (control) and UDP
(audio). AntennaHead no longer runs an embedded AirPlay receiver of its own — that role is
ControlBooth's, which forwards its audio to AntennaHead over UDP. Most UDP traffic is
loopback-only, same-machine IPC between helper CLI tools
(`PCMUDPSender`/`PCMUDPReceiver`); only the HTTP(S) servers and the AirPlay RTSP port are
intended to be LAN-reachable.

## Port table

| Port | Proto | Default | Service / purpose | Configurable? | Source |
|---|---|---|---|---|---|
| 5000 | TCP | shairport-sync RTSP/RAOP control port (classic AirPlay 1) | No — hardcoded in vendored shairport-sync binary | `AirPlayReceiver` — `AirPlayReceiverController.swift:27,57,86,112,129-152`; `ControlBooth` `AirPlaySettingsView.swift:30` |
| 6019 | UDP | AntennaHead's `PCMUDPReceiver` — receives PCM audio from ControlBooth | Yes (SQLite `app_config`) | `AntennaHead/Services/PortSettings.swift:10-29`, `SDRController.swift:65`; `ControlBooth` default in `AirPlaySettings.swift`, `Pipeline.swift:33` |
| 6020 | UDP | PCM input into LiveAudioServer from the active SDR/audio pipeline | Yes (`--udp-input-port`) | `AntennaHead/Services/PortSettings.swift`, `LiveAudioServerProcessManager.swift:52`; `LiveAudioServerCore/Config.swift:27-49` |
| 6021 | UDP | rtl_fm status feed (`-c <port>`) — frequency / RMS power ASCII lines | Yes | `AntennaHead/Services/PortSettings.swift`, `SDRController.swift:102`, `RTLSDRStatusListener.swift` |
| 6023 | UDP | AntennaHead's optional `PCMTranscriber` tap sends newline-delimited speech-recognition JSON here (`{"type":"partial"\|"final","text",…}`), loopback, for a future in-app caption listener | No — fixed constant, not in Configuration UI | `AntennaHead/Services/SDRController.swift` (`transcriptionUDPPort`), `PipelineHelpers/Sources/PCMTranscriber/main.swift` |
| 6024 | UDP | AntennaHead → its optional spatial-audio `PCMDistanceGain` stage — live `dist <value>` updates from the Now Playing distance slider | No — fixed constant, not in Configuration UI | `AntennaHead/Services/SDRController.swift` (`spatialGainControlPort`), `PipelineHelpers/Sources/PCMDistanceGain/main.swift` |
| 6025 | UDP | AntennaHead → its optional spatial-audio `PCMBinauralPanner` stage — live `pos <az> <el>` / `dist <value>` updates from the Now Playing direction pad | No — fixed constant, not in Configuration UI | `AntennaHead/Services/SDRController.swift` (`binauralControlPort`), `PipelineHelpers/Sources/PCMBinauralPanner/main.swift` |
| 6026 | UDP | AntennaHead → the filler pipeline's own `PCMDistanceGain` stage — `dist <value>` ramps that fade the Monitor Beacon (or user filler) in on start and out when a real source is selected | No — fixed constant, not in Configuration UI | `AntennaHead/Services/SDRController.swift` (`fillerControlPort`), `PipelineHelpers/Sources/PCMDistanceGain/main.swift` |
| 8080 | TCP | LiveAudioServer HTTP stream (MP3/AAC/HLS) + status page | Yes (`-p/--port`) | `LiveAudioServerCore/Config.swift:58`; `AntennaHead/Services/LiveAudioServerProcessManager.swift:48`, `LiveAudioServerClient.swift:26` |
| 8090 | TCP | AntennaHead's own web UI (HTTP), Bonjour-advertised as `_http._tcp` | Yes | `AntennaHead/Services/AntennaHeadHTTPServer.swift:19` |
| 8094 | TCP | AntennaHead's own web UI (HTTPS/TLS), Bonjour-advertised as `_https._tcp` | Yes | `AntennaHead/Services/AntennaHeadHTTPServer.swift:20` |
| 8443 | TCP | LiveAudioServer HTTPS stream (TLS); disabled unless `--tls-port` given | Yes — AntennaHead sets it to 8443 when launching the subprocess | `LiveAudioServerCore/Config.swift:106`; `AntennaHead/Services/LiveAudioServerProcessManager.swift:30` |
| dynamic (OS-assigned) | UDP | shairport-sync's own RAOP audio/control/timing RTP channels | No | `AirPlayReceiver/Sources/AirPlayReceiver/ShairportSyncArguments.swift` (no `--udp-port-base` passed) |
| user-supplied, no default | UDP | `PCMUDPSender`/`PCMUDPReceiver` generic helper tools — every caller above supplies the actual port | `--port` required | `PipelineHelpers/Sources/PCMUDPSender/main.swift`, `PCMUDPReceiver/main.swift` |

### Not part of the shipped product (for completeness)

| Port | Proto | Where | Note |
|---|---|---|---|
| 1234 | TCP | `antennahead-librtlsdr/librtlsdr-src/src/rtl_tcp.c:111,739,976` | Upstream `rtl_tcp` default control port — vendored source only, not compiled into the shipped `librtlsdr.xcframework` |
| user-specified | UDP/TCP | `rtl_udp.c`, `rtl_rpcd.c`, `controlThread.c` | Same vendored-but-unbuilt upstream tools |
| 17002 | TCP | `AntennaHead/Services/PortSettings.swift:7-9` | Legacy `LocalRadioServerHTTPPort` key seeded into the skeleton SQLite DB by the predecessor "LocalRadio" app; not read by current code, flagged only so it isn't mistaken for an active port |
| 7355 | UDP | `LiveAudioServer/README.md:121-123` | Documented as Gqrx's own default remote-control port, for interoperability notes only — not opened by LiveAudioServer itself |

## Inter-service communication map

| Link | Mechanism | Port |
|---|---|---|
| ControlBooth → AntennaHead (start/stop/status control) | Apple Events (`'AntH'`) | none — local IPC |
| AntennaHead → ControlBooth (start/stop/status control) | Apple Events (`'CBth'`) | none — local IPC |
| ControlBooth → AntennaHead (audio) | `PCMUDPSender` → `PCMUDPReceiver` | UDP 6019 |
| ControlBooth's embedded AirPlayReceiver → ControlBooth pipeline | sox → `PCMUDPSender` → `PCMUDPReceiver` | UDP — configurable, default 6019 |
| SDR/audio pipeline → LiveAudioServer | UDP input | UDP 6020 |
| rtl_fm → AntennaHead status listener | ASCII status lines | UDP 6021 |
| `PCMTranscriber` tap → AntennaHead caption listener (not yet built) | newline-delimited JSON | UDP 6023 |
| AntennaHead Now Playing → spatial-audio `PCMDistanceGain` / `PCMBinauralPanner` stages | `dist` / `pos` ASCII lines | UDP 6024 / 6025 |
| AntennaHead → filler `PCMDistanceGain` (fade in/out) | `dist` ASCII lines | UDP 6026 |
| Browser/phone → AntennaHead web UI | HTTP/HTTPS, Bonjour `_http._tcp`/`_https._tcp` | TCP 8090 / 8094 |
| Browser/phone → LiveAudioServer stream | HTTP/HTTPS, optional Bonjour (`_http._tcp`/`_https._tcp`, `_liveaudio-pcm` for inputs) | TCP 8080 / 8443 |
| AirPlay sender (iPhone/Mac) → shairport-sync | RAOP/RTSP | TCP 5000 + dynamic RTP UDP |

## Notes / things worth flagging

- All UDP traffic in the AntennaHead/ControlBooth/PipelineHelpers chain defaults to
  `127.0.0.1` loopback (`PCMUDPReceiver --bind` and `PCMUDPSender --host` both default to
  `127.0.0.1`) — it's same-machine IPC over UDP sockets, not a LAN protocol. Only the HTTP(S)
  servers (8090/8094/8080/8443) and AirPlay RTSP (5000) are meant to be LAN-reachable.
- Since shairport-sync's RTSP port (5000) is hardcoded and not configurable, ControlBooth's
  AirPlay receiver and macOS's own built-in AirPlay Receiver are mutually exclusive on one
  Mac — only one can hold TCP 5000 at a time. (This mutual exclusion is why AntennaHead
  dropped its own embedded receiver and defers the role to ControlBooth.)
- `AntennaHead/README.md`'s "Default Ports" table documents the configurable ports
  (8090/8094/8080/8443/6021/6020/6019). The fixed internal constants not exposed in the
  Configuration sheet are the speech-to-text caption feed (6023), the two spatial-audio
  control ports (6024/6025), and the filler fade control (6026) — all loopback, both ends
  owned by AntennaHead.
- `rtl_fm_localradio_src/rtl_fm_localradio.m:2253` hardcoded `port = 6020` for the legacy
  Objective-C `retune_socket_thread_fn`'s own status socket to the predecessor "LocalRadio.app".
  On inspection this whole function (lines 2240–2479) is inside a `/* ... */` block comment, so
  it's dead code, never compiled — but it collided numerically with AntennaHead's live
  `audioUDP` setting, which was confusing to read. Changed the literal to **6023** (unused,
  outside the 6019–6022 live range) so it no longer looks like an active duplicate if the code
  is ever revived.

*Generated 2026-07-28 by surveying source across the six repos in `antennahead-umbrella/`.*
