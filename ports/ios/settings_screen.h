// SPDX-License-Identifier: MIT
// iOS: the settings screen and the on-screen controls, for code that also uses UIKit.
#pragma once

#import <UIKit/UIKit.h>

void gt4_ios_install_touch_controls(UIViewController *controller);
void gt4_ios_open_settings(UIViewController *presenter);
// 0 Auto (only without a controller), 1 always on, 2 off.
int gt4_ios_touch_mode();
double gt4_ios_touch_opacity();
bool gt4_ios_tilt_enabled();
// Touch face buttons: 0 PlayStation (✕ ○ □ △), 1 Xbox (A B X Y), 2 Nintendo (B A Y X).
int gt4_ios_button_style();
// Degrees of tilt for full steering lock.
double gt4_ios_tilt_angle();
