#!/usr/bin/env bash
# Apply personal Omarchy settings. Safe to run again: a file or setting that
# already matches is left alone.
#
#   ./install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOUCHPAD="$ROOT/hypr/touchpad.lua"
CURSOR="$ROOT/hypr/cursor.lua"
FLOATING="$ROOT/hypr/floating-size.lua"
ROUNDING="$ROOT/hypr/rounding.lua"
INPUT="$HOME/.config/hypr/input.lua"
HYPRLAND="$HOME/.config/hypr/hyprland.lua"
FLOATING_CONFIG="$HOME/.config/hypr/floating-size.lua"
ROUNDING_CONFIG="$HOME/.config/hypr/rounding.lua"
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
[[ -f $TOUCHPAD && -f $CURSOR && -f $FLOATING && -f $ROUNDING ]] || fail "missing hypr snippets"
[[ -f $INPUT ]] || fail "$INPUT must already exist"
[[ -f $HYPRLAND ]] || fail "$HYPRLAND must already exist"
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

SHELL_JSON="$HOME/.config/omarchy/shell.json"

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

# Copy a hypr module into place and keep one marked require for it at the end
# of hyprland.lua. Prints "match" or "updated".
require_module() {
  python3 - "$HYPRLAND" "$1" "$2" <<'PY'
import sys
from pathlib import Path

path, marker, module = sys.argv[1:]
path = Path(path)
require = f'require("hypr.{module}")'
block = marker + "\n" + require + "\n"
text = path.read_text()
if not text.endswith("\n"):
    text += "\n"

if text.count(marker) > 1:
    raise SystemExit(f"install: hyprland.lua contains the {module} block more than once")

if marker in text:
    lines = text.splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if line.startswith(marker))
    end = start + 1
    if end >= len(lines) or not lines[end].startswith("require("):
        raise SystemExit(f"install: {module} block does not require a module")
    updated = "".join(lines[:start]) + block + "".join(lines[end + 1 :])
else:
    updated = text
    if not updated.endswith("\n\n"):
        updated += "\n"
    updated += block

if updated == path.read_text():
    print("match")
else:
    path.write_text(updated)
    print("updated")
PY
}

floating_changed=0
if cmp -s "$FLOATING" "$FLOATING_CONFIG"; then
  echo "Floating window sizes already match"
else
  cp "$FLOATING" "$FLOATING_CONFIG"
  echo "Updated floating-size.lua"
  floating_changed=1
fi

floating_status="$(require_module "-- omarchy-dtp-config: floating windows reopen at the size the app last had." floating-size)"
case "$floating_status" in
  match)
    echo "Floating size rule already matches"
    ;;
  updated)
    echo "Floating windows will reopen at the size the app last had"
    floating_changed=1
    ;;
  *)
    fail "could not install the floating size rule"
    ;;
esac

rounding_changed=0
if cmp -s "$ROUNDING" "$ROUNDING_CONFIG"; then
  echo "Window rounding already matches"
else
  cp "$ROUNDING" "$ROUNDING_CONFIG"
  echo "Updated rounding.lua"
  rounding_changed=1
fi

rounding_status="$(require_module "-- omarchy-dtp-config: round window corners." rounding)"
case "$rounding_status" in
  match)
    echo "Window rounding rule already matches"
    ;;
  updated)
    echo "Window corners will be rounded"
    rounding_changed=1
    ;;
  *)
    fail "could not install the window rounding rule"
    ;;
esac

echo "==> workspace control"
WORKSPACE_PLUGIN="io.github.dtpietrzak.workspace-control"
OLD_WORKSPACE_PLUGIN="dtpietrzak.workspacecontrol"
OLD_WORKSPACE_GESTURE="$HOME/.config/hypr/workspace-control.lua"
workspace_changed=0

# Before 2.0 the gesture was installed into the Hyprland config, where it would
# hold the gesture the plugin now registers itself.
if [[ -f $OLD_WORKSPACE_GESTURE ]] || grep -qxF 'require("hypr.workspace-control")' "$HYPRLAND"; then
  rm -f "$OLD_WORKSPACE_GESTURE"
  sed -i -e '/^-- Four finger workspace control panel (omarchy-dtp-workspace-control)\.$/d' \
    -e '/^require("hypr\.workspace-control")$/d' "$HYPRLAND"
  echo "Removed the old workspace gesture from the Hyprland config"
  workspace_changed=1
fi

if [[ -d "$HOME/.config/omarchy/plugins/$WORKSPACE_PLUGIN" ]]; then
  WORKSPACE_SETTINGS="$HOME/.config/omarchy/$WORKSPACE_PLUGIN.json"

  # The plugin was renamed, and its settings file with it.
  if [[ -d "$HOME/.config/omarchy/plugins/$OLD_WORKSPACE_PLUGIN" ]]; then
    omarchy plugin remove "$OLD_WORKSPACE_PLUGIN" --yes
    if [[ -f "$HOME/.config/omarchy/$OLD_WORKSPACE_PLUGIN.json" && ! -f $WORKSPACE_SETTINGS ]]; then
      mv "$HOME/.config/omarchy/$OLD_WORKSPACE_PLUGIN.json" "$WORKSPACE_SETTINGS"
    fi
  fi

  # The plugin leaves its hotkeys off until asked. These are wanted here.
  hotkeys_added="$(python3 - "$WORKSPACE_SETTINGS" <<'PY'
import json
import sys
from pathlib import Path

file = Path(sys.argv[1])
settings = json.loads(file.read_text()) if file.is_file() else {}
if "hotkeys" in settings:
    print(0)
else:
    settings["hotkeys"] = True
    file.write_text(json.dumps(settings, indent=2) + "\n")
    print(1)
PY
)"
  if [[ $hotkeys_added -eq 1 ]]; then
    echo "Turned on the workspace hotkeys"
    workspace_changed=1
  fi

  # The widget brings its own workspace numbers, so the stock ones would be a
  # second row of the same thing.
  if grep -qF "\"$WORKSPACE_PLUGIN\"" "$SHELL_JSON" && plugin_enabled omarchy.workspaces; then
    omarchy plugin disable omarchy.workspaces
    echo "Turned off the stock workspace widget"
  fi
fi

if [[ $input_changed -eq 1 || $gsettings_changed -eq 1 || $floating_changed -eq 1 || $rounding_changed -eq 1 || $workspace_changed -eq 1 ]]; then
  if [[ $input_changed -eq 1 || $floating_changed -eq 1 || $rounding_changed -eq 1 || $workspace_changed -eq 1 ]]; then
    hyprctl reload >/dev/null
    errors="$(hyprctl configerrors 2>&1 || true)"
    if [[ -n ${errors//[[:space:]]/} ]]; then
      printf '%s\n' "$errors" >&2
      fail "Hyprland reported config errors"
    fi
    echo "Hyprland config reloaded with no errors"
  fi
  if [[ $input_changed -eq 1 || $gsettings_changed -eq 1 ]]; then
    theme="${XCURSOR_THEME:-default}"
    hyprctl setcursor "$theme" "$CURSOR_SIZE" >/dev/null
    echo "Cursor size set to $CURSOR_SIZE"
  fi
elif [[ $chromium_changed -eq 0 ]]; then
  echo "Hyprland config already matches"
fi

echo "==> superwhisper"
# Omarchy installs Superwhisper again on update while it is the default
# dictation backend. The stock remover drops the package, the panel, and that
# default. Preferences, history, and models stay.
superwhisper_package_link() {
  [[ -L $1 && $(readlink -- "$1") == "$2" ]]
}

superwhisper_present() {
  local config_home data_home dictation link target
  config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  dictation="$config_home/omarchy/defaults/dictation"

  if omarchy-pkg-present superwhisper-bin; then
    return 0
  fi
  if [[ -f $dictation && $(<"$dictation") == superwhisper ]]; then
    return 0
  fi
  if systemctl --user is-enabled --quiet superwhisper.service 2>/dev/null \
    || systemctl --user is-active --quiet superwhisper.service 2>/dev/null; then
    return 0
  fi

  while IFS='|' read -r link target; do
    superwhisper_package_link "$link" "$target" && return 0
  done <<EOF
$HOME/.local/bin/superwhisper|/usr/bin/superwhisper
$data_home/superwhisper/app/current|/opt/superwhisper
$config_home/omarchy/plugins/superwhisper-panel|/opt/superwhisper/assets/omarchy-plugin/superwhisper-panel
$HOME/.agents/skills/superwhisper|/opt/superwhisper/assets/agent-skill/superwhisper
$HOME/.claude/skills/superwhisper|/opt/superwhisper/assets/agent-skill/superwhisper
$HOME/.codex/skills/superwhisper|/opt/superwhisper/assets/agent-skill/superwhisper
$HOME/.pi/agent/skills/superwhisper|/opt/superwhisper/assets/agent-skill/superwhisper
EOF
  return 1
}

if superwhisper_present; then
  command -v omarchy-remove-dictation-superwhisper >/dev/null \
    || fail "omarchy-remove-dictation-superwhisper is not available"
  omarchy-remove-dictation-superwhisper
  echo "Removed Superwhisper"
else
  echo "Superwhisper is already removed"
fi
