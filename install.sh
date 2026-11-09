#!/usr/bin/env bash
# Apply personal Omarchy settings. Safe to run again: a file or setting that
# already matches is left alone.
#
#   ./install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOUCHPAD="$ROOT/hypr/touchpad.lua"
CURSOR="$ROOT/hypr/cursor.lua"
INPUT="$HOME/.config/hypr/input.lua"
FLAGS="$HOME/.config/chromium-flags.conf"
CHROMIUM_FLAG="--disable-features=AcceleratedVideoDecoder"
CLOCK_FORMAT="ddd d MMM h:mm AP"
TEXT_PX=10
# omarchy display text size maps 12px to 9pt. 10px lands on 8pt.
TEXT_PT=8
# Ghostty stays one step larger than the other terminals.
GHOSTTY_PT=10

fail() {
  echo "install: $*" >&2
  exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: install.sh"
  echo "Applies the personal Omarchy settings in this repo."
  exit 0
fi
[[ $# -eq 0 ]] || fail "unknown argument: $1"
[[ -f $TOUCHPAD && -f $CURSOR ]] || fail "missing hypr snippets"
[[ -f $INPUT ]] || fail "$INPUT must already exist"
[[ -f $FLAGS ]] || fail "$FLAGS must already exist"

CURSOR_SIZE="$(sed -n 's/.*hl\.env("XCURSOR_SIZE", "\([0-9][0-9]*\)").*/\1/p' "$CURSOR")"
[[ $CURSOR_SIZE =~ ^[0-9]+$ ]] || fail "cursor snippet has no XCURSOR_SIZE"

status="$(python3 - "$TOUCHPAD" "$CURSOR" "$INPUT" "$FLAGS" "$CHROMIUM_FLAG" <<'PY'
import re
import sys
from pathlib import Path

touchpad_path, cursor_path, input_path, flags_path, chromium_flag = sys.argv[1:]
touchpad = Path(touchpad_path).read_text()
cursor = Path(cursor_path).read_text()
if not touchpad.endswith("\n"):
    touchpad += "\n"
if not cursor.endswith("\n"):
    cursor += "\n"

start = "-- Left-click-and-drag with three fingers on the trackpad."
if touchpad.count(start) != 1 or not touchpad.rstrip().endswith("})"):
    raise SystemExit("install: touchpad snippet must be the three-finger block")
if 'hl.env("XCURSOR_SIZE"' not in cursor or 'hl.env("HYPRCURSOR_SIZE"' not in cursor:
    raise SystemExit("install: cursor snippet must set both cursor size variables")

gesture = 'hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })'
active_gesture = re.compile(
    r'^hl\.gesture\(\{ fingers = \d+, direction = "horizontal", action = "workspace" \}\)\s*$'
)
commented_gesture = re.compile(
    r'^-- hl\.gesture\(\{ fingers = \d+, direction = "horizontal", action = "workspace" \}\)\s*$'
)

def finish(text):
    if text and not text.endswith("\n"):
        text += "\n"
    return text

def replace_touchpad(text):
    if touchpad in text:
        return text, False
    lines = text.splitlines(keepends=True)
    idxs = [i for i, line in enumerate(lines) if line.startswith(start)]
    if len(idxs) > 1:
        raise SystemExit("install: input.lua contains the touchpad block more than once")
    if len(idxs) == 1:
        end = None
        for j in range(idxs[0] + 1, len(lines)):
            if lines[j].rstrip("\r\n") == "})":
                end = j
                break
        if end is None:
            raise SystemExit("install: touchpad block has no closing })")
        new = "".join(lines[: idxs[0]]) + touchpad + "".join(lines[end + 1 :])
        return new, True
    lines = text.splitlines(keepends=True)
    insert_at = 0
    for i, line in enumerate(lines[:4]):
        if line.startswith("-- replace Omarchy's defaults."):
            insert_at = i + 1
            if insert_at < len(lines) and lines[insert_at].strip() == "":
                insert_at += 1
            break
    new = "".join(lines[:insert_at]) + touchpad + "\n" + "".join(lines[insert_at:])
    return new, True

def replace_gesture(text):
    lines = text.splitlines(keepends=True)
    desired = None
    active = []
    commented = []
    for i, line in enumerate(lines):
        body = line.rstrip("\r\n")
        if body == gesture:
            desired = i
        elif active_gesture.match(body):
            active.append(i)
        elif commented_gesture.match(body):
            commented.append(i)
    if desired is not None:
        return text, False
    if active:
        if len(active) > 1:
            raise SystemExit("install: input.lua has more than one horizontal workspace gesture")
        newline = "\n" if lines[active[0]].endswith("\n") else ""
        lines[active[0]] = gesture + newline
        return "".join(lines), True
    if commented:
        newline = "\n" if lines[commented[0]].endswith("\n") else ""
        lines[commented[0]] = gesture + newline
        return "".join(lines), True
    new = finish(text)
    if new and not new.endswith("\n\n"):
        new += "\n"
    return new + gesture + "\n", True

def replace_cursor(text):
    if cursor in text:
        return text, False
    lines = text.splitlines(keepends=True)
    marker = "-- omarchy-dtp-config: cursor size."
    idxs = [i for i, line in enumerate(lines) if line.startswith(marker)]
    if len(idxs) > 1:
        raise SystemExit("install: input.lua contains the cursor block more than once")
    if len(idxs) == 1:
        end = idxs[0]
        while end + 1 < len(lines) and 'hl.env("HYPRCURSOR_SIZE"' not in lines[end]:
            end += 1
            if end - idxs[0] > 6:
                raise SystemExit("install: cursor block does not set HYPRCURSOR_SIZE")
        if 'hl.env("HYPRCURSOR_SIZE"' not in lines[end]:
            raise SystemExit("install: cursor block does not set HYPRCURSOR_SIZE")
        new = "".join(lines[: idxs[0]]) + cursor + "".join(lines[end + 1 :])
        return new, True
    new = finish(text)
    if new and not new.endswith("\n\n"):
        new += "\n"
    return new + cursor, True

path = Path(input_path)
original = path.read_text()
updated, touchpad_changed = replace_touchpad(original)
updated, gesture_changed = replace_gesture(updated)
updated, cursor_changed = replace_cursor(updated)
input_changed = updated != original
if input_changed:
    path.write_text(updated)
    print("Updated input.lua")
else:
    print("input.lua already matches")

flags = Path(flags_path)
flag_text = flags.read_text()
if chromium_flag in flag_text.splitlines():
    print("Chromium flag already set")
    flag_changed = False
else:
    new_flags = finish(flag_text) + chromium_flag + "\n"
    flags.write_text(new_flags)
    print("Updated chromium-flags.conf")
    flag_changed = True

print(f"STATUS input_changed={1 if input_changed or touchpad_changed or gesture_changed or cursor_changed else 0}")
print(f"STATUS chromium_changed={1 if flag_changed else 0}")
PY
)"
printf '%s\n' "$status"

input_changed=0
chromium_changed=0
if grep -q '^STATUS input_changed=1$' <<<"$status"; then
  input_changed=1
fi
if grep -q '^STATUS chromium_changed=1$' <<<"$status"; then
  chromium_changed=1
fi

plugin_enabled() {
  local id=$1
  omarchy plugin list --json | jq -e --arg id "$id" 'any(.[]; .id == $id and .enabled == true)' >/dev/null
}

disable_plugin() {
  local id=$1
  if plugin_enabled "$id"; then
    omarchy plugin disable "$id"
  else
    echo "$id is already off"
  fi
}

bar_position="$(omarchy bar position)"
if [[ $bar_position == "bottom" ]]; then
  echo "Bar position is already bottom"
else
  omarchy bar position bottom
fi

clock_format="$(omarchy bar get omarchy.clock format || true)"
if [[ $clock_format == "$CLOCK_FORMAT" ]]; then
  echo "Clock format is already set"
else
  omarchy bar set omarchy.clock format "$CLOCK_FORMAT"
fi

echo "==> bar widgets"
disable_plugin omarchy.indicators
disable_plugin omarchy.elsewhen
disable_plugin omarchy.weather

dock_position="$(omarchy dock position)"
if [[ $dock_position == "left" ]]; then
  echo "Dock position is already left"
else
  omarchy dock position left
fi

dock_autohide="$(omarchy dock autohide)"
if [[ $dock_autohide == "on" ]]; then
  echo "Dock auto-hide is already on"
else
  omarchy dock autohide on
fi

dock_pinned="$(omarchy dock pinned)"
want_pinned=$'chromium\norg.gnome.Nautilus\nomawrite'
if [[ $dock_pinned == "$want_pinned" ]]; then
  echo "Dock pins already match"
else
  omarchy dock pinned chromium org.gnome.Nautilus omawrite
fi

base_size=""
shell_toml="$HOME/.config/omarchy/shell.toml"
if [[ -f $shell_toml ]]; then
  base_size="$(awk '
    /^[[:space:]]*\[/ { in_font = ($0 ~ /^[[:space:]]*\[font\]([[:space:]]|$)/); next }
    in_font && /^[[:space:]]*base-size[[:space:]]*=/ {
      v = $0
      sub(/^[^=]*=[[:space:]]*/, "", v)
      sub(/[[:space:]]*(#.*)?$/, "", v)
      print v
      exit
    }
  ' "$shell_toml")"
fi

terminal_needs_size=0
if [[ -f $HOME/.config/alacritty/alacritty.toml ]] &&
  ! grep -qE '^size[[:space:]]*=[[:space:]]*'"$TEXT_PT"'$' "$HOME/.config/alacritty/alacritty.toml"; then
  terminal_needs_size=1
fi
if [[ -f $HOME/.config/foot/foot.ini ]] &&
  ! grep -qE ":size=$TEXT_PT([^0-9]|$)" "$HOME/.config/foot/foot.ini"; then
  terminal_needs_size=1
fi
if [[ -f $HOME/.config/kitty/kitty.conf ]] &&
  ! grep -qE '^[[:space:]]*font_size[[:space:]]+'"$TEXT_PT"'\.0[[:space:]]*$' "$HOME/.config/kitty/kitty.conf"; then
  terminal_needs_size=1
fi

if [[ $base_size == "$TEXT_PX" && $terminal_needs_size -eq 0 ]]; then
  echo "Text size is already ${TEXT_PX}px"
else
  omarchy display text size "$TEXT_PX"
fi

# The text-size command writes the same point size into every terminal, which
# puts Ghostty at 8pt. This machine keeps Ghostty at 10pt.
ghostty_config="$HOME/.config/ghostty/config"
if [[ -f $ghostty_config ]]; then
  if grep -qE '^font-size = '"$GHOSTTY_PT"'$' "$ghostty_config"; then
    echo "Ghostty font size is already ${GHOSTTY_PT}pt"
  else
    if grep -qE '^font-size = ' "$ghostty_config"; then
      sed -i -E "s/^font-size = .*/font-size = $GHOSTTY_PT/" "$ghostty_config"
    else
      printf '\nfont-size = %s\n' "$GHOSTTY_PT" >>"$ghostty_config"
    fi
    pkill -SIGUSR2 ghostty 2>/dev/null || true
    echo "Ghostty font size set to ${GHOSTTY_PT}pt"
  fi
fi

cursor_now="$(gsettings get org.gnome.desktop.interface cursor-size | awk '{print $NF}')"
if [[ $cursor_now == "$CURSOR_SIZE" ]]; then
  echo "GTK cursor size is already $CURSOR_SIZE"
  gsettings_changed=0
else
  gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE"
  echo "GTK cursor size set to $CURSOR_SIZE"
  gsettings_changed=1
fi

if [[ $input_changed -eq 1 || $gsettings_changed -eq 1 ]]; then
  if [[ $input_changed -eq 1 ]]; then
    hyprctl reload >/dev/null
    errors="$(hyprctl configerrors 2>&1 || true)"
    if [[ -n ${errors//[[:space:]]/} ]]; then
      printf '%s\n' "$errors" >&2
      fail "Hyprland reported config errors"
    fi
    echo "Hyprland config reloaded with no errors"
  fi
  theme="${XCURSOR_THEME:-default}"
  hyprctl setcursor "$theme" "$CURSOR_SIZE" >/dev/null
  echo "Cursor size set to $CURSOR_SIZE"
elif [[ $chromium_changed -eq 0 ]]; then
  echo "Hyprland config already matches"
fi
