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
[[ -f $ROOT/hypr/floating-size.lua ]] || fail "missing floating size snippet"
[[ -f $ROOT/hypr/rounding.lua ]] || fail "missing rounding snippet"
luac -p "$ROOT/hypr/touchpad.lua"
luac -p "$ROOT/hypr/cursor.lua"
luac -p "$ROOT/hypr/floating-size.lua"
luac -p "$ROOT/hypr/rounding.lua"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export HOME="$tmpdir"
export XDG_CONFIG_HOME="$tmpdir/.config"
export XDG_DATA_HOME="$tmpdir/.local/share"
export XDG_STATE_HOME="$tmpdir/.local/state"
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
# Superwhisper checks must not see the real package or the real user service.
cat >"$tmpdir/bin/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ $1 == superwhisper-bin && -f $HOME/.superwhisper-pkg ]]
EOF

cat >"$tmpdir/bin/systemctl" <<'EOF'
#!/bin/bash
if [[ $1 == --user && $3 == --quiet && $4 == superwhisper.service ]]; then
  case $2 in
    is-enabled) [[ -f $HOME/.superwhisper-enabled ]]; exit ;;
    is-active) [[ -f $HOME/.superwhisper-active ]]; exit ;;
  esac
fi
echo "unexpected systemctl: $*" >&2
exit 1
EOF

# Stands in for Omarchy's remover: clear the traces the installer looks for.
cat >"$tmpdir/bin/omarchy-remove-dictation-superwhisper" <<'EOF'
#!/bin/bash
printf 'remove\n' >>"$HOME/.superwhisper-log"
rm -f "$HOME/.superwhisper-pkg" "$HOME/.superwhisper-enabled" "$HOME/.superwhisper-active"
dictation="$HOME/.config/omarchy/defaults/dictation"
if [[ -f $dictation && $(<"$dictation") == superwhisper ]]; then
  rm -f "$dictation"
fi
unlink_package_link() {
  if [[ -L $1 && $(readlink -- "$1") == "$2" ]]; then
    rm "$1"
  fi
}
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
unlink_package_link "$HOME/.local/bin/superwhisper" /usr/bin/superwhisper
unlink_package_link "$data_home/superwhisper/app/current" /opt/superwhisper
unlink_package_link "$config_home/omarchy/plugins/superwhisper-panel" /opt/superwhisper/assets/omarchy-plugin/superwhisper-panel
for agent in .agents .claude .codex .pi/agent; do
  unlink_package_link "$HOME/$agent/skills/superwhisper" /opt/superwhisper/assets/agent-skill/superwhisper
done
EOF

chmod +x "$tmpdir/bin/hyprctl" "$tmpdir/bin/gsettings" "$tmpdir/bin/omarchy" "$tmpdir/bin/jq" "$tmpdir/bin/pkill" \
  "$tmpdir/bin/omarchy-pkg-present" "$tmpdir/bin/systemctl" "$tmpdir/bin/omarchy-remove-dictation-superwhisper"
export PATH="$tmpdir/bin:$PATH"

INPUT="$HOME/.config/hypr/input.lua"
HYPRLAND="$HOME/.config/hypr/hyprland.lua"
FLOATING="$HOME/.config/hypr/floating-size.lua"
ROUNDING="$HOME/.config/hypr/rounding.lua"
FLAGS="$HOME/.config/chromium-flags.conf"

reset_logs() {
  rm -f "$HOME/.hyprctl-log" "$HOME/.gsettings-log" "$HOME/.omarchy-log" "$HOME/.plugin-disable-log" "$HOME/.pkill-log"
}

assert_quiet_hypr() {
  [[ ! -f $HOME/.hyprctl-log ]] || fail "hyprctl ran when the config was unchanged: $(cat "$HOME/.hyprctl-log")"
}

# A stock input file gains the touchpad block, the gesture, and the cursor.
cat >"$HYPRLAND" <<'EOF'
-- personal config stays
-- end stays
EOF
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
mkdir -p "$HOME/.config/omarchy/plugins/io.github.dtpietrzak.workspace-control"
cat >"$HOME/.config/omarchy/shell.json" <<'EOF'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [
        {"id": "dtpietrzak.menu"},
        {"id": "io.github.dtpietrzak.workspace-control"}
      ]
    }
  }
}
EOF
reset_logs

"$ROOT/install.sh" >/dev/null
grep -q 'scroll_factor = 0.3' "$INPUT" || fail "touchpad scroll factor was not written"
grep -q 'natural_scroll = true' "$INPUT" || fail "natural scroll was not written"
grep -q 'tap_and_drag = false' "$INPUT" || fail "double-tap-to-drag was not turned off"
grep -qx 'hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })' "$INPUT" || fail "4-finger gesture was not written"
grep -q 'hl.env("XCURSOR_SIZE", "20")' "$INPUT" || fail "cursor size was not written"
grep -c -F 'hl.env("XCURSOR_SIZE"' "$INPUT" | grep -qx 1 || fail "cursor size was written more than once"
grep -q 'warp_on_change_workspace = 0' "$INPUT" || fail "mouse setting was not written"
grep -q '"hotkeys": true' "$HOME/.config/omarchy/io.github.dtpietrzak.workspace-control.json" || fail "workspace hotkeys were not turned on"
grep -c -F 'warp_on_change_workspace' "$INPUT" | grep -qx 1 || fail "mouse setting was written more than once"
grep -qx -- '--disable-features=AcceleratedVideoDecoder' "$FLAGS" || fail "chromium flag was not written"
grep -qx 'reload' "$HOME/.hyprctl-log" || fail "hyprctl reload was not run"
grep -qx 'configerrors' "$HOME/.hyprctl-log" || fail "hyprctl configerrors was not run"
grep -qx 'setcursor default 20' "$HOME/.hyprctl-log" || fail "cursor was not applied: $(cat "$HOME/.hyprctl-log")"
grep -qx -- '-- personal config stays' "$HYPRLAND" || fail "the hyprland.lua header was dropped"
grep -qx -- '-- end stays' "$HYPRLAND" || fail "the hyprland.lua trailer was dropped"
grep -q 'require("hypr.floating-size")' "$HYPRLAND" || fail "floating size was not required"
grep -c -F 'require("hypr.floating-size")' "$HYPRLAND" | grep -qx 1 || fail "floating size was required more than once"
cmp -s "$ROOT/hypr/floating-size.lua" "$FLOATING" || fail "floating-size.lua was not installed"
grep -c -F 'require("hypr.rounding")' "$HYPRLAND" | grep -qx 1 || fail "rounding was not required exactly once"
cmp -s "$ROOT/hypr/rounding.lua" "$ROUNDING" || fail "rounding.lua was not installed"
grep -qx 'set 20' "$HOME/.gsettings-log" || fail "GTK cursor size was not set"
grep -q 'bar position bottom' "$HOME/.omarchy-log" || fail "bar position was not set"
grep -q 'display text size 10' "$HOME/.omarchy-log" || fail "text size was not set"
grep -q 'disable omarchy.indicators' "$HOME/.plugin-disable-log" || fail "indicators were not disabled"
grep -q 'dock position left' "$HOME/.omarchy-log" || fail "dock position was not set"
grep -q 'dock autohide on' "$HOME/.omarchy-log" || fail "dock autohide was not set"
python3 - "$HOME/.config/omarchy/shell.json" <<'PY' || fail "a gap was put between the menu button and the workspace widget"
import json, sys
ids = [entry["id"] for entry in json.load(open(sys.argv[1]))["bar"]["layout"]["left"]]
assert ids == ["dtpietrzak.menu", "io.github.dtpietrzak.workspace-control"], ids
PY
if grep -q 'disable omarchy.weather' "$HOME/.plugin-disable-log"; then
  fail "a widget that was already off was disabled again"
fi

# The second run leaves matching files alone and does not reload Hyprland.
before_input="$(cat "$INPUT")"
before_flags="$(cat "$FLAGS")"
before_hyprland="$(cat "$HYPRLAND")"
before_floating="$(cat "$FLOATING")"
before_rounding="$(cat "$ROUNDING")"
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
[[ "$(cat "$HYPRLAND")" == "$before_hyprland" ]] || fail "the second run changed hyprland.lua"
[[ "$(cat "$FLOATING")" == "$before_floating" ]] || fail "the second run changed floating-size.lua"
[[ "$(cat "$ROUNDING")" == "$before_rounding" ]] || fail "the second run changed rounding.lua"
[[ "$(cat "$HOME/.config/ghostty/config")" == "font-size = 10" ]] || fail "the second run changed Ghostty"
assert_quiet_hypr
[[ ! -f $HOME/.gsettings-log ]] || fail "gsettings ran when the cursor size already matched"
[[ ! -f $HOME/.pkill-log ]] || fail "Ghostty was signaled when its font size already matched"
if grep -E -q 'position bottom|position left|autohide on|text size 10|bar set ' "$HOME/.omarchy-log"; then
  fail "a setting that already matched was written again: $(cat "$HOME/.omarchy-log")"
fi
[[ ! -f $HOME/.superwhisper-log ]] || fail "Superwhisper was removed when it was already gone"

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

# An older touchpad block gains tap_and_drag = false and keeps the lines around it.
cat >"$INPUT" <<'EOF'
-- header stays
-- Left-click-and-drag with three fingers on the trackpad.
hl.config({
  input = {
    touchpad = {
      drag_3fg = 1,
      scroll_factor = 0.3,
      natural_scroll = true,
      disable_while_typing = false,
    },
  },
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })

-- omarchy-dtp-config: cursor size. Omarchy's default is 24.
hl.env("XCURSOR_SIZE", "20")
hl.env("HYPRCURSOR_SIZE", "20")
-- trailing stays
EOF
reset_logs
"$ROOT/install.sh" >/dev/null
grep -q 'tap_and_drag = false' "$INPUT" || fail "an older touchpad block did not turn off double-tap-to-drag"
grep -qx -- '-- header stays' "$INPUT" || fail "the header around the touchpad block was dropped"
grep -qx -- '-- trailing stays' "$INPUT" || fail "the trailer around the touchpad block was dropped"
grep -qx 'reload' "$HOME/.hyprctl-log" || fail "replacing the touchpad block did not reload Hyprland"

# An older copy of the floating size script is replaced, and the lines around
# its require stay.
printf '%s\n' '-- stale' >"$FLOATING"
cat >"$HYPRLAND" <<'EOF'
-- header stays
-- omarchy-dtp-config: floating windows reopen at the size the app last had.
require("hypr.old")
-- trailing stays
EOF
reset_logs
"$ROOT/install.sh" >/dev/null
cmp -s "$ROOT/hypr/floating-size.lua" "$FLOATING" || fail "the old floating size script was not replaced"
grep -q 'require("hypr.floating-size")' "$HYPRLAND" || fail "the old floating size require was not replaced"
grep -qx -- '-- header stays' "$HYPRLAND" || fail "the header around the floating size block was dropped"
grep -qx -- '-- trailing stays' "$HYPRLAND" || fail "the trailer around the floating size block was dropped"
grep -qx 'reload' "$HOME/.hyprctl-log" || fail "replacing the floating size script did not reload Hyprland"
if grep -q 'require("hypr.old")' "$HYPRLAND"; then
  fail "the old floating size require was left in place"
fi

# An older copy of the rounding snippet is replaced and Hyprland reloads.
printf '%s\n' '-- stale' >"$ROUNDING"
reset_logs
"$ROOT/install.sh" >/dev/null
cmp -s "$ROOT/hypr/rounding.lua" "$ROUNDING" || fail "the old rounding snippet was not replaced"
grep -qx 'reload' "$HOME/.hyprctl-log" || fail "replacing the rounding snippet did not reload Hyprland"

# Any leftover Superwhisper trace is removed once. The next run leaves it alone.
clear_superwhisper() {
  rm -f "$HOME/.superwhisper-pkg" "$HOME/.superwhisper-enabled" "$HOME/.superwhisper-active" "$HOME/.superwhisper-log"
  rm -f "$HOME/.config/omarchy/defaults/dictation"
  rm -f "$HOME/.local/bin/superwhisper" \
    "$HOME/.local/share/superwhisper/app/current" \
    "$HOME/.config/omarchy/plugins/superwhisper-panel" \
    "$HOME/.agents/skills/superwhisper" \
    "$HOME/.claude/skills/superwhisper" \
    "$HOME/.codex/skills/superwhisper" \
    "$HOME/.pi/agent/skills/superwhisper"
}

assert_removed_once() {
  local label=$1
  [[ -f $HOME/.superwhisper-log ]] || fail "$label: Superwhisper was not removed"
  [[ $(wc -l <"$HOME/.superwhisper-log") -eq 1 ]] || fail "$label: Superwhisper was removed more than once"
  reset_logs
  rm -f "$HOME/.superwhisper-log"
  "$ROOT/install.sh" >/dev/null
  [[ ! -f $HOME/.superwhisper-log ]] || fail "$label: Superwhisper was removed again"
}

mkdir -p "$HOME/.config/omarchy/defaults" "$HOME/.local/bin" "$HOME/.local/share/superwhisper/app" \
  "$HOME/.config/omarchy/plugins" "$HOME/.agents/skills" "$HOME/.claude/skills" \
  "$HOME/.codex/skills" "$HOME/.pi/agent/skills"

clear_superwhisper
printf 'installed\n' >"$HOME/.superwhisper-pkg"
printf 'enabled\n' >"$HOME/.superwhisper-enabled"
printf 'active\n' >"$HOME/.superwhisper-active"
printf 'superwhisper\n' >"$HOME/.config/omarchy/defaults/dictation"
ln -s /usr/bin/superwhisper "$HOME/.local/bin/superwhisper"
ln -s /opt/superwhisper "$HOME/.local/share/superwhisper/app/current"
ln -s /opt/superwhisper/assets/omarchy-plugin/superwhisper-panel "$HOME/.config/omarchy/plugins/superwhisper-panel"
ln -s /opt/superwhisper/assets/agent-skill/superwhisper "$HOME/.agents/skills/superwhisper"
reset_logs
"$ROOT/install.sh" >/dev/null
[[ ! -f $HOME/.superwhisper-pkg ]] || fail "the Superwhisper package was still present"
[[ ! -f $HOME/.config/omarchy/defaults/dictation ]] || fail "the dictation default was not cleared"
[[ ! -L $HOME/.local/bin/superwhisper ]] || fail "the Superwhisper command link was left in place"
[[ ! -L $HOME/.config/omarchy/plugins/superwhisper-panel ]] || fail "the Superwhisper panel link was left in place"
[[ ! -L $HOME/.agents/skills/superwhisper ]] || fail "the Superwhisper skill link was left in place"
assert_removed_once "a full Superwhisper install"

clear_superwhisper
printf 'superwhisper\n' >"$HOME/.config/omarchy/defaults/dictation"
reset_logs
"$ROOT/install.sh" >/dev/null
[[ ! -f $HOME/.config/omarchy/defaults/dictation ]] || fail "a leftover dictation default was not cleared"
assert_removed_once "a leftover dictation default"

clear_superwhisper
ln -s /opt/superwhisper/assets/agent-skill/superwhisper "$HOME/.claude/skills/superwhisper"
reset_logs
"$ROOT/install.sh" >/dev/null
[[ ! -L $HOME/.claude/skills/superwhisper ]] || fail "a leftover skill link was left in place"
assert_removed_once "a leftover skill link"

echo "ok"
