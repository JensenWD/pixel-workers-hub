<p align="center"><img src="Support/icon.png" width="128" alt=""></p>

<h1 align="center">Pixel Workers Hub</h1>

<p align="center">Your Claude Code sessions in the macOS menu bar, each one a pixel worker at a desk.<br>
Click one to jump straight to its terminal tab.</p>

<p align="center">
  <img src="docs/panel-light.png" width="360" alt="The panel in light mode: five sessions, each with a pixel worker at a desk and a status such as Needs you, Working or Your turn">
  <img src="docs/panel-dark.png" width="360" alt="The same panel with the dark appearance">
</p>

- **Every open session at a glance**, with its name, folder and terminal.
- **Workers act out the status:** typing while Claude works, waving when it needs you, sipping coffee
  when it's your turn.
- **A count on the menu-bar icon** when a session is waiting on a permission prompt or has failed.
- **No setup, no account, no network requests.** It reads what Claude Code already reports.

## Install

Needs macOS 13 or later and a recent [Claude Code](https://claude.com/claude-code) (run `claude update`).

1. [Download Pixel-Workers-Hub.zip](https://github.com/JensenWD/pixel-workers-hub/releases/latest/download/Pixel-Workers-Hub.zip),
   unzip it and drag the app into **Applications**.
2. Open it. The first time, macOS blocks it because it isn't notarized by Apple. Go to
   **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
3. Click the pixel worker in your menu bar.

If macOS says the app is damaged, run this and open it again:

```sh
xattr -dr com.apple.quarantine "/Applications/Pixel Workers Hub.app"
```

**Or build it yourself** (needs only `xcode-select --install`):

```sh
git clone https://github.com/JensenWD/pixel-workers-hub.git
cd pixel-workers-hub
make install
```

## Using it

- **Click a session** to jump to its tab. The first time, macOS asks to let the app control your
  terminal. Click **Allow**.
- **Ghostty 1.3+** (what it's built for), **iTerm2** and **Terminal** open the exact tab. Other terminals
  just come to the front.
- **Options** (in the panel, or right-click the icon) has **Open at Login**, **Appearance** and
  **Detailed Status**.

**Detailed status (optional):** click **Turn on detailed status** at the bottom of the panel. It adds
hooks to `~/.claude/settings.json` (backed up first), so statuses update instantly and also show when a
turn **failed**. The hooks save only each session's ID, status, folder and title, never prompts or
transcripts. Restart open sessions to include them.

## Troubleshooting

- **No sessions show up:** run `claude update`. If the app still can't find `claude`, run this, then quit
  and reopen the app:
  ```sh
  defaults write io.github.jensenwd.pixel-workers-hub claudePath "$(command -v claude)"
  ```
- **Clicking does nothing:** allow the app under **System Settings → Privacy & Security → Automation**.
- **"No Ghostty tab is titled …":** remove any fixed `title` from your Ghostty config. Naming a session
  with `/rename` makes the match exact.

## Uninstall

Turn off **Detailed Status** in Options, quit the app and move it to the Trash. If you built it, run
`make uninstall`.

## Development

```sh
make run          # run from source
make test         # unit tests (needs full Xcode)
make screenshot   # redraw the README screenshots
```

Pushing a `v*` tag builds and publishes a release.

## License

[MIT](LICENSE)
