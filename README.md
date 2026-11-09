# omarchy-dtp-config

Personal Omarchy settings. `omarchy-dtp-install` runs this after the other features.

The app list, the hidden dock, and the floating title-bar limits stay in their own repos. This one is the rest of the desktop settings.

## Settings

- Cursor size 20. Omarchy's default is 24.
- Touchpad: natural scroll, three-finger drag, scroll factor 0.3, and the touchpad stays on while typing.
- Four-finger horizontal swipe changes workspace.
- Text size 10px, through `omarchy display text size`. Alacritty, Foot, and Kitty follow at 8pt. Ghostty stays at 10pt.
- Bar on the bottom. Clock format `ddd d MMM h:mm AP`.
- Indicators, Elsewhen, and Weather are off.
- Dock on the left, auto-hide on, pinned to Chromium, Files, and omawrite. The dock stays off until its own feature turns it back on. The pins are here for that day.
- Chromium starts with `--disable-features=AcceleratedVideoDecoder`.

## Install

```bash
git clone https://github.com/dtpietrzak/omarchy-dtp-install.git
cd omarchy-dtp-install
./install.sh
```

From a local checkout:

```bash
./install.sh
```

Running it again leaves a setting that already matches untouched. A running app keeps its old cursor until it is opened again.

## Left out

Git name, email, and the GitHub credential helper stay on the machine that created them. The Claude tray pin is a session icon name, so it stays too. Monitors are unchanged from Omarchy and are not copied.

## Check

```bash
bash tests/install-test.sh
```
