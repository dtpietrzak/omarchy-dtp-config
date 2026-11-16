-- Left-click-and-drag with three fingers on the trackpad.
hl.config({
  input = {
    touchpad = {
      drag_3fg = 1,
      -- Closer to macOS. Omarchy's default is 0.4.
      scroll_factor = 0.05,
      natural_scroll = true,
      disable_while_typing = false,
      -- A drag starts from a press and hold.
      tap_and_drag = false,
    },
  },
})
