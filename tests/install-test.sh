#!/usr/bin/env bash
# The installer applies each setting once and leaves a matching config alone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() {
  echo "not ok - $*" >&2
  exit 1
}

[[ -f $ROOT/hypr/touchpad.lua ]] || fail "missing touchpad snippet"
[[ -f $ROOT/hypr/cursor.lua ]] || fail "missing cursor snippet"
luac -p "$ROOT/hypr/touchpad.lua"
luac -p "$ROOT/hypr/cursor.lua"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export HOME="$tmpdir"
export XDG_CONFIG_HOME="$tmpdir/.config"
unset XCURSOR_THEME || true
mkdir -p "$HOME/.config/hypr" "$HOME/.config/omarchy" "$tmpdir/bin"
printf '24\n' >"$HOME/.cursor-size"
printf 'bottom\n' >"$HOME/.bar-position"
printf 'ddd d MMM h:mm AP\n' >"$HOME/.clock-format"
printf '[]\n' >"$HOME/.plugins"
printf 'left\n' >"$HOME/.dock-position"
printf 'on\n' >"$HOME/.dock-autohide"
printf 'chromium\norg.gnome.Nautilus\nomawrite\n' >"$HOME/.dock-pinned"
printf '10\n' >"$HOME/.text-px"

cat >"$tmpdir/bin/hyprctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/.hyprctl-log"
exit 0
EOF

cat >"$tmpdir/bin/gsettings" <<'EOF'
#!/bin/bash
key=$3
if [[ $1 == get && $key == cursor-size ]]; then
  tr -d '[:space:]' <"$HOME/.cursor-size"
  printf '\n'
  exit 0
fi
if [[ $1 == set && $key == cursor-size ]]; then
  printf '%s\n' "$4" >"$HOME/.cursor-size"
  printf 'set %s\n' "$4" >>"$HOME/.gsettings-log"
  exit 0
fi
echo "unexpected gsettings: $*" >&2
exit 1
EOF

cat >"$tmpdir/bin/omarchy" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOME/.omarchy-log"
if [[ $1 == bar && $2 == position && -z ${3:-} ]]; then
  cat "$HOME/.bar-position"
  exit 0
fi
if [[ $1 == bar && $2 == position && $3 == bottom ]]; then
  printf 'bottom\n' >"$HOME/.bar-position"
  exit 0
fi
if [[ $1 == bar && $2 == get && $3 == omarchy.clock && $4 == format ]]; then
  cat "$HOME/.clock-format"
  exit 0
fi
if [[ $1 == bar && $2 == set && $3 == omarchy.clock && $4 == format ]]; then
  printf '%s\n' "$5" >"$HOME/.clock-format"
  exit 0
fi
if [[ $1 == plugin && $2 == list && $3 == --json ]]; then
  cat "$HOME/.plugins"
  exit 0
fi
if [[ $1 == plugin && $2 == disable ]]; then
  printf 'disable %s\n' "$3" >>"$HOME/.plugin-disable-log"
  exit 0
fi
if [[ $1 == dock && $2 == position && -z ${3:-} ]]; then
  cat "$HOME/.dock-position"
  exit 0
fi
if [[ $1 == dock && $2 == position ]]; then
  printf '%s\n' "$3" >"$HOME/.dock-position"
  exit 0
fi
if [[ $1 == dock && $2 == autohide && -z ${3:-} ]]; then
  cat "$HOME/.dock-autohide"
  exit 0
fi
if [[ $1 == dock && $2 == autohide ]]; then
  printf '%s\n' "$3" >"$HOME/.dock-autohide"
  exit 0
fi
if [[ $1 == dock && $2 == pinned && -z ${3:-} ]]; then
  cat "$HOME/.dock-pinned"
  exit 0
fi
if [[ $1 == dock && $2 == pinned ]]; then
  printf '%s\n' "$3" >"$HOME/.dock-pinned"
  shift 2
  printf '%s\n' "$@" >"$HOME/.dock-pinned"
  exit 0
fi
if [[ $1 == display && $2 == text && $3 == size ]]; then
  printf '%s\n' "$4" >"$HOME/.text-px"
  exit 0
fi
echo "unexpected omarchy: $*" >&2
exit 1
EOF

cat >"$tmpdir/bin/jq" <<'EOF'
#!/usr/bin/env bash
# Enough of `jq -e --arg id ID 'any(...)'` for this installer.
id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e) shift ;;
    --arg)
      if [[ ${2:-} == id ]]; then
        id=$3
      fi
      shift 3
      ;;
    *) shift ;;
  esac
done
python3 -c '
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)
ok = any(item.get("id") == want and item.get("enabled") is True for item in data)
sys.exit(0 if ok else 1)
' "$id"
EOF

cat >"$tmpdir/bin/pkill" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/.pkill-log"
exit 0
EOF
chmod +x "$tmpdir/bin/hyprctl" "$tmpdir/bin/gsettings" "$tmpdir/bin/omarchy" "$tmpdir/bin/jq" "$tmpdir/bin/pkill"
export PATH="$tmpdir/bin:$PATH"

INPUT="$HOME/.config/hypr/input.lua"
FLAGS="$HOME/.config/chromium-flags.conf"

reset_logs() {
  rm -f "$HOME/.hyprctl-log" "$HOME/.gsettings-log" "$HOME/.omarchy-log" "$HOME/.plugin-disable-log" "$HOME/.pkill-log"
}

assert_quiet_hypr() {
  [[ ! -f $HOME/.hyprctl-log ]] || fail "hyprctl ran when the config was unchanged: $(cat "$HOME/.hyprctl-log")"
}

# A stock input file gains the touchpad block, the gesture, and the cursor.
cat >"$INPUT" <<'EOF'
-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Keyboard layout and options.
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
EOF
printf '%s\n' '--ozone-platform=wayland' >"$FLAGS"
rm -f "$HOME/.config/omarchy/shell.toml"
printf '12\n' >"$HOME/.text-px"
printf 'top\n' >"$HOME/.bar-position"
printf 'HH:mm\n' >"$HOME/.clock-format"
printf '[{"id":"omarchy.indicators","enabled":true},{"id":"omarchy.weather","enabled":false}]\n' >"$HOME/.plugins"
printf 'bottom\n' >"$HOME/.dock-position"
printf 'off\n' >"$HOME/.dock-autohide"
printf 'foot\n' >"$HOME/.dock-pinned"
printf '24\n' >"$HOME/.cursor-size"
reset_logs

"$ROOT/install.sh" >/dev/null
grep -q 'scroll_factor = 0.3' "$INPUT" || fail "touchpad scroll factor was not written"
grep -q 'natural_scroll = true' "$INPUT" || fail "natural scroll was not written"
grep -qx 'hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })' "$INPUT" || fail "4-finger gesture was not written"
grep -q 'hl.env("XCURSOR_SIZE", "20")' "$INPUT" || fail "cursor size was not written"
grep -c -F 'hl.env("XCURSOR_SIZE"' "$INPUT" | grep -qx 1 || fail "cursor size was written more than once"
grep -qx -- '--disable-features=AcceleratedVideoDecoder' "$FLAGS" || fail "chromium flag was not written"
grep -qx 'reload' "$HOME/.hyprctl-log" || fail "hyprctl reload was not run"
grep -qx 'configerrors' "$HOME/.hyprctl-log" || fail "hyprctl configerrors was not run"
grep -qx 'setcursor default 20' "$HOME/.hyprctl-log" || fail "cursor was not applied: $(cat "$HOME/.hyprctl-log")"
grep -qx 'set 20' "$HOME/.gsettings-log" || fail "GTK cursor size was not set"
grep -q 'bar position bottom' "$HOME/.omarchy-log" || fail "bar position was not set"
grep -q 'display text size 10' "$HOME/.omarchy-log" || fail "text size was not set"
grep -q 'disable omarchy.indicators' "$HOME/.plugin-disable-log" || fail "indicators were not disabled"
grep -q 'dock position left' "$HOME/.omarchy-log" || fail "dock position was not set"
grep -q 'dock autohide on' "$HOME/.omarchy-log" || fail "dock autohide was not set"
if grep -q 'disable omarchy.weather' "$HOME/.plugin-disable-log"; then
  fail "a widget that was already off was disabled again"
fi

# The second run leaves matching files alone and does not reload Hyprland.
before_input="$(cat "$INPUT")"
before_flags="$(cat "$FLAGS")"
mkdir -p "$HOME/.config/alacritty" "$HOME/.config/foot" "$HOME/.config/kitty" "$HOME/.config/ghostty"
printf 'size = 8\n' >"$HOME/.config/alacritty/alacritty.toml"
printf 'font=JetBrainsMono Nerd Font:size=8\n' >"$HOME/.config/foot/foot.ini"
printf 'font_size 8.0\n' >"$HOME/.config/kitty/kitty.conf"
printf 'font-size = 10\n' >"$HOME/.config/ghostty/config"
printf '[font]\nbase-size = 10\n' >"$HOME/.config/omarchy/shell.toml"
printf '[]\n' >"$HOME/.plugins"
reset_logs
"$ROOT/install.sh" >/dev/null
[[ "$(cat "$INPUT")" == "$before_input" ]] || fail "the second run changed input.lua"
[[ "$(cat "$FLAGS")" == "$before_flags" ]] || fail "the second run changed chromium flags"
[[ "$(cat "$HOME/.config/ghostty/config")" == "font-size = 10" ]] || fail "the second run changed Ghostty"
assert_quiet_hypr
[[ ! -f $HOME/.gsettings-log ]] || fail "gsettings ran when the cursor size already matched"
[[ ! -f $HOME/.pkill-log ]] || fail "Ghostty was signaled when its font size already matched"
if grep -E -q 'position bottom|position left|autohide on|text size 10|bar set ' "$HOME/.omarchy-log"; then
  fail "a setting that already matched was written again: $(cat "$HOME/.omarchy-log")"
fi

# Ghostty is restored to 10pt without running the text-size command, which
# would put it back at 8pt with the other terminals.
printf 'font-size = 8\n' >"$HOME/.config/ghostty/config"
reset_logs
"$ROOT/install.sh" >/dev/null
[[ "$(cat "$HOME/.config/ghostty/config")" == "font-size = 10" ]] || fail "Ghostty was not restored to 10pt"
if grep -q 'display text size 10' "$HOME/.omarchy-log"; then
  fail "restoring Ghostty reran the text-size command"
fi
grep -qx -- '-SIGUSR2 ghostty' "$HOME/.pkill-log" || fail "Ghostty was not asked to reload: $(cat "$HOME/.pkill-log" 2>/dev/null)"

# An older cursor size in the same block is replaced, and the lines around it stay.
cat >"$INPUT" <<'EOF'
-- header stays
-- omarchy-dtp-config: cursor size. Omarchy's default is 24.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- trailing stays
EOF
printf '20\n' >"$HOME/.cursor-size"
printf '[font]\nbase-size = 10\n' >"$HOME/.config/omarchy/shell.toml"
reset_logs
"$ROOT/install.sh" >/dev/null
grep -q 'hl.env("XCURSOR_SIZE", "20")' "$INPUT" || fail "old cursor size was not replaced"
grep -q 'hl.env("HYPRCURSOR_SIZE", "20")' "$INPUT" || fail "old hyprcursor size was not replaced"
grep -qx -- '-- header stays' "$INPUT" || fail "the header around the cursor block was dropped"
grep -qx -- '-- trailing stays' "$INPUT" || fail "the trailer around the cursor block was dropped"
grep -qx 'reload' "$HOME/.hyprctl-log" || fail "replacing the cursor size did not reload Hyprland"

echo "ok"
