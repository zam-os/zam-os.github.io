# zam-os.org

Landing page for **ZAM** — the symbiotic learning layer for your AI agent.
Served at [zam-os.org](https://zam-os.org) via GitHub Pages.

Plain static HTML/CSS/JS in `index.html` — no build step, no external
dependencies (privacy-safe: no third-party fonts or trackers). Edit and push
to `main` to deploy.

## Install scripts

`install.sh` (macOS/Linux) and `install.ps1` (Windows) are served at the site
root so users can run:

```sh
curl -fsSL https://zam-os.org/install.sh | sh      # macOS · Linux
irm https://zam-os.org/install.ps1 | iex           # Windows (PowerShell)
```

Each fetches the correct desktop-app installer for the OS/CPU from the latest
GitHub release and installs the `zam` CLI (`zam-core` from npm). Fetching via
curl/iwr instead of a browser avoids the macOS quarantine flag and Windows
Mark-of-the-Web, so Gatekeeper/SmartScreen don't fire; the scripts also clear
those flags defensively. Pass `ZAM_DRY_RUN=1` to preview without installing.

> **Maintenance:** the scripts build download URLs from the release **asset
> naming pattern** defined by `.github/workflows/release.yml` in
> [zam-os/zam](https://github.com/zam-os/zam). If those asset names change,
> update the `asset=`/`$asset` lines in both scripts to match.

- Product & source: https://github.com/zam-os/zam
