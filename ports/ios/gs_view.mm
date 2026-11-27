// SPDX-License-Identifier: MIT
// iOS: the view the in-app PCSX2 GS draws into (GT4_RENDERER=pcsx2). It lies over the SDL view of the game window,
// fills it, and takes no touches. The Metal layer is created here, on the main thread, and handed to the GS library
// (gt4gs_ios_set_host, gt4recomp-gs pcsx2-gt4gs/IOSPresentation.mm) before the GS thread starts: the GS then draws from
// its own thread and never needs the main thread, which runs the game.
#include <SDL3/SDL.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include "settings_screen.h"

extern "C" void gt4gs_ios_set_host(void *view, void *layer, float scale);

namespace {
CAMetalLayer *g_picture_layer = nil;  // the layer the chosen stream renderer draws into
}

// CoreGS 2.0 (native/hw_gs/hw_gs_stream_sink.cpp) makes its Vulkan surface on this layer.
extern "C" void *gt4_ios_picture_layer() { return (__bridge void *)g_picture_layer; }

// Keeps the Metal layer the size of the view (rotation, fold changes). The drawable size is the GS's business.
@interface GT4GSHostView : UIView
@property(nonatomic, strong) CAMetalLayer *metalLayer;
@end

@implementation GT4GSHostView
- (void)layoutSubviews {
  [super layoutSubviews];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.metalLayer.frame = self.bounds;
  [CATransaction commit];
}
@end

void gt4_ios_prepare_gs_view(SDL_Window *window) {
  const char *renderer = std::getenv("GT4_RENDERER");
  const bool pcsx2 = renderer && std::strcmp(renderer, "pcsx2") == 0, hw = renderer && std::strcmp(renderer, "hw") == 0;
  if (!pcsx2 && !hw)
    return;  // the built-in renderer draws into the SDL view itself
  UIWindow *ui_window = (__bridge UIWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window),
                                                                    SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, nullptr);
  UIView *root = ui_window.rootViewController.view;
  if (!root) {
    std::fprintf(stderr, "[ios] no root view for the GS picture\n");
    return;
  }
  GT4GSHostView *view = [[GT4GSHostView alloc] initWithFrame:root.bounds];
  view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  view.userInteractionEnabled = NO;
  view.backgroundColor = UIColor.blackColor;
  CAMetalLayer *layer = [CAMetalLayer layer];
  layer.frame = view.bounds;
  layer.contentsScale = ui_window.screen.nativeScale;
  layer.opaque = YES;
  // Lower input lag: at most one frame waiting for the screen besides the one shown (the default is three drawables).
  layer.maximumDrawableCount = 2;
  [view.layer addSublayer:layer];
  view.metalLayer = layer;
  [root addSubview:view];
  // Retained by the view hierarchy; the GS keeps its own references.
  g_picture_layer = layer;
  if (pcsx2)
    gt4gs_ios_set_host((__bridge void *)view, (__bridge void *)layer, static_cast<float>(ui_window.screen.nativeScale));
  std::fprintf(stderr, "[ios] GS picture view %.0fx%.0f points, scale %.1f\n", root.bounds.size.width,
               root.bounds.size.height, ui_window.screen.nativeScale);
}

// The on-screen controls and the settings gear sit over the picture, whichever renderer draws it.
void gt4_ios_prepare_touch_controls(SDL_Window *window) {
  UIWindow *ui_window = (__bridge UIWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window),
                                                                    SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, nullptr);
  if (ui_window.rootViewController)
    gt4_ios_install_touch_controls(ui_window.rootViewController);
}
