# AntennaHead Workspace

Umbrella project for the AntennaHead family of repos. This repo holds only a
manifest and a bootstrap script — each project stays an independent git repo
with its own history, issues, and PRs.

## Projects

- [AntennaHead](https://github.com/dsward2/AntennaHead) — sandboxed macOS app (the main project)
- [LiveAudioServer](https://github.com/dsward2/LiveAudioServer) — headless audio server; runs as a subprocess of AntennaHead, and also works standalone in the terminal with tools like Gqrx and `rtl_fm`
- [ControlBooth](https://github.com/dsward2/ControlBooth) — similar processing to AntennaHead, but unsandboxed, for experimental radio tools like `nrsc5`
- [PipelineHelpers](https://github.com/dsward2/PipelineHelpers) — shared Unix pipeline management tools/modules used by AntennaHead and ControlBooth
- [antennahead-librtlsdr](https://github.com/dsward2/antennahead-librtlsdr) — librtlsdr build/vendoring for AntennaHead

## Setup

```bash
git clone https://github.com/dsward2/antennahead-workspace.git
./antennahead-workspace/bootstrap.sh
```

This clones every project in `repos.txt` as a sibling of `antennahead-workspace/`.
Re-running `bootstrap.sh` fetches updates for any repo that's already cloned.

## Adding a project

Add a line to `repos.txt`: `name  url  ref`.
