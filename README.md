# AntennaHead Workspace

Umbrella project for the AntennaHead family of repos. This repo holds only a
manifest and a bootstrap script — each project stays an independent git repo
with its own history, issues, and PRs.

## Projects

- [AntennaHead](https://github.com/dsward2/AntennaHead) — sandboxed macOS app (the main project)
- [LiveAudioServer](https://github.com/dsward2/LiveAudioServer) — headless audio server; runs as a subprocess of AntennaHead, and also works standalone in the terminal with tools like Gqrx and `rtl_fm`
- [ControlBooth](https://github.com/dsward2/ControlBooth) — similar processing to AntennaHead, but unsandboxed, for experimental radio tools like `nrsc5`
- [PipelineHelpers](https://github.com/dsward2/PipelineHelpers) — shared Unix pipeline management tools/modules used by AntennaHead and ControlBooth
- [SharedLogging](https://github.com/dsward2/SharedLogging) — shared log store + viewer window used by AntennaHead and ControlBooth
- [AirPlayReceiver](https://github.com/dsward2/AirPlayReceiver) — shared AirPlay 1 (RAOP) audio-receiver package used by AntennaHead and ControlBooth
- [antennahead-librtlsdr](https://github.com/dsward2/antennahead-librtlsdr) — librtlsdr build/vendoring for AntennaHead
- [AntennaHeadAPI](https://github.com/dsward2/AntennaHeadAPI) — Codable JSON-API contract types shared between AntennaHead's HTTP server and future non-WebKit clients (tvOS, watchOS)

## Setup

```bash
git clone https://github.com/dsward2/antennahead-workspace.git
./antennahead-workspace/bootstrap.sh
```

This clones every project in `repos.txt` as a sibling of `antennahead-workspace/`.
Re-running `bootstrap.sh` fetches updates for any repo that's already cloned.

**Use this bootstrap to lay out the workspace, not an ad hoc checkout
location.** AntennaHead's and ControlBooth's Xcode projects reference
PipelineHelpers, SharedLogging, and AirPlayReceiver (and AntennaHead also
references LiveAudioServer) as **local Swift packages by relative path**
(`../PipelineHelpers`, `../SharedLogging`, `../AirPlayReceiver`,
`../LiveAudioServer` — see each `.xcodeproj/project.pbxproj`'s
`XCLocalSwiftPackageReference` entries). Those relative paths only resolve
when every project is a sibling directory one level below where each
`.xcodeproj` lives, i.e. exactly the layout `bootstrap.sh` produces. Cloning
these repos individually into arbitrary folders will make Xcode fail to
resolve the local package dependencies (or silently fall back to fetching
from GitHub instead of your local checkout, for packages whose `Package.swift`
has a GitHub-fallback like AirPlayReceiver's and LiveAudioServer's).

## Adding a project

Add a line to `repos.txt`: `name  url  ref`.
