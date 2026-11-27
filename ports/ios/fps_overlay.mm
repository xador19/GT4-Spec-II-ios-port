// SPDX-License-Identifier: MIT
// iOS: an on-screen frame-rate counter in the top-left corner. It counts guest VBlanks per second of wall time, which is
// the game's own speed: 60 means full speed, less means the phone cannot keep up. The settings screen can hide it.
#include <SDL3/SDL.h>

#import <UIKit/UIKit.h>

#include "ios_ui.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {

UILabel *g_label = nil;
bool g_disabled = false;
int g_vblanks = 0;
std::chrono::steady_clock::time_point g_window_start;

UILabel *create_label(SDL_Window *window) {
  UIWindow *ui_window = (__bridge UIWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window),
                                                                    SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, nullptr);
  UIView *view = ui_window.rootViewController.view;
  if (!view)
    return nil;
  UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 96, 24)];
  label.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
  label.textColor = UIColor.whiteColor;
  label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
  label.textAlignment = NSTextAlignmentCenter;
  label.layer.cornerRadius = 6;
  label.layer.masksToBounds = YES;
  label.userInteractionEnabled = NO;
  label.text = @"-- FPS";
  label.translatesAutoresizingMaskIntoConstraints = NO;
  [view addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.leadingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.leadingAnchor constant:8],
    [label.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:8],
    [label.widthAnchor constraintEqualToConstant:96],
    [label.heightAnchor constraintEqualToConstant:24],
  ]];
  return label;
}

} // namespace

// The phone's thermal state in gt4.log when it changes (checked once a second): iOS slows the GPU when the phone is
// hot, which looks like a GPU-bound scene in the timing report.
static void log_thermal_state() {
  static NSProcessInfoThermalState last = NSProcessInfoThermalStateNominal;
  static bool logged = false;
  const NSProcessInfoThermalState state = NSProcessInfo.processInfo.thermalState;
  if (logged && state == last)
    return;
  static const char *const names[] = {"nominal", "fair", "serious", "critical"};
  const int index = static_cast<int>(state);
  std::fprintf(stderr, "[ios] thermal state %s\n", index >= 0 && index < 4 ? names[index] : "unknown");
  last = state;
  logged = true;
}

void gt4_ios_count_vblank(SDL_Window *window) {
  static unsigned thermal_countdown = 0;
  if (thermal_countdown-- == 0) {
    thermal_countdown = 60;
    log_thermal_state();
  }
  if (g_disabled)
    return;
  const auto now = std::chrono::steady_clock::now();
  if (!g_label) {
    g_label = create_label(window);
    if (!g_label) {
      g_disabled = true;
      return;
    }
    g_window_start = now;
    g_vblanks = 0;
  }
  g_label.hidden = !gt4_ios_fps_visible();
  ++g_vblanks;
  const double seconds = std::chrono::duration<double>(now - g_window_start).count();
  if (seconds >= 1.0) {
    g_label.text = [NSString stringWithFormat:@"%.0f FPS", g_vblanks / seconds];
    g_window_start = now;
    g_vblanks = 0;
  }
}
