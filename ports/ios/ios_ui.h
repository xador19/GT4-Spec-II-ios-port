// SPDX-License-Identifier: MIT
// iOS: what the touch controls and the settings screen (touch_controls.mm, settings_screen.mm) share with the game's
// input code and window loop. Every function here may be called from any thread.
#pragma once

#include <cstdint>

struct GT4IosTouch {
  std::uint16_t buttons = 0;  // PS2 button bits (native/controls.hpp)
  std::uint8_t lx = 128, ly = 128;  // left stick, PS2 bytes
  std::uint8_t gas = 0, brake = 0;  // pedals, 0..255
  bool stick = false;  // a finger is on the stick
};

GT4IosTouch gt4_ios_touch_read();
void gt4_ios_touch_set_controller_connected(bool connected);

// Settings the game reads while it runs.
double gt4_ios_rumble_gain();
bool gt4_ios_triggers_to_rstick();
bool gt4_ios_fps_visible();
// The renderer chosen on the settings screen, as a GT4_RENDERER value: "pcsx2" or "hw" (CoreGS 2.0).
const char *gt4_ios_renderer_choice();
// Gas and brake from the controller's triggers are scaled by this (0.2..1) before they reach the game.
double gt4_ios_pedal_range();
// Tilt steering: true and a PS2 left-stick byte (0 left, 128 centre, 255 right) while the setting is on and the
// motion sensor has data.
bool gt4_ios_tilt_axis(std::uint8_t *axis);
// True while the settings screen is open: the window loop holds the game.
bool gt4_ios_ui_paused();
