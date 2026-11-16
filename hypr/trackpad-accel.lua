-- Apple's trackpad curve (IOHID parametric acceleration, tracking speed 0.875,
-- from a 14" MacBook Pro), sampled into libinput's custom profile for this
-- pad at 97 units/mm and this panel (2560x1600 at scale 2). Slow movement
-- stays under 1 screen-mm per finger-mm; a flick crosses the screen.
-- Scroll is left alone.
local macos_trackpad_accel = "custom 0.5124 0.000000 0.018743 0.041512 0.068309 0.099140 0.134010 0.172922 0.215882 0.262895 0.313964 0.369094 0.428291 0.491558 0.558900 0.630323 0.705829 0.785424 0.869113 0.956901 1.048790 1.144788 1.244897 1.349123 1.457470 1.569942 1.686545 1.807283 1.932160 2.061182 2.194352 2.331676 2.473157 2.618801 2.768612 2.922594 3.080753 3.243093 3.409619 3.580334 3.755244 3.934353 4.117666 4.305188 4.496923 4.692875 4.893050 5.097451 5.306084 5.518953 5.736062 5.957417 6.183021 6.412880 6.646998 6.885379 7.128029 7.374951 7.626151 7.881633 8.141401 8.405461 8.673816 8.946472 9.221244"

hl.device({ name = "apple-mtp-multi-touch", accel_profile = macos_trackpad_accel })
-- Palm rejection grabs the real pad and forwards this virtual one, so the
-- curve has to live here while rejection is on.
hl.device({ name = "apple-mtp-multi-touch-(palm-rejection)", accel_profile = macos_trackpad_accel })
