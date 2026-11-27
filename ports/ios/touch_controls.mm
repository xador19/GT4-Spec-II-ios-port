// SPDX-License-Identifier: MIT
// iOS: on-screen controls over the game picture, laid out like a phone racing game. One view tracks every finger: a
// floating steering stick that appears wherever a thumb lands on the left half of the screen, gas and brake pedals that
// are simply on or off, a D-pad, the face and shoulder buttons, Start, Select and the gear that opens the settings screen. A touch anywhere else falls through to the views below. In the Auto mode the controls
// show only while no controller is connected; the gear always stays.
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

#include "ios_ui.h"
#include "settings_screen.h"

#include <algorithm>
#include <atomic>
#include <cmath>

namespace {

// PS2 button bits (native/controls.hpp).
enum : int {
  kSelect = 0, kStart = 3, kUp = 4, kRight = 5, kDown = 6, kLeft = 7, kL2 = 8, kR2 = 9, kL1 = 10, kR1 = 11,
  kTriangle = 12, kCircle = 13, kCross = 14, kSquare = 15,
};

enum class Kind { button, dpad, stick, gas, brake, gear };

std::atomic<std::uint64_t> g_state{(std::uint64_t{128} << 16) | (std::uint64_t{128} << 24)};
std::atomic<bool> g_controller{false};
std::atomic<bool> g_landscape_left{false};  // the interface orientation, for the sign of the tilt
CMMotionManager *g_motion = nil;

std::uint64_t pack(const GT4IosTouch &t) {
  return std::uint64_t{t.buttons} | (std::uint64_t{t.lx} << 16) | (std::uint64_t{t.ly} << 24) |
         (std::uint64_t{t.gas} << 32) | (std::uint64_t{t.brake} << 40) | (std::uint64_t{t.stick ? 1u : 0u} << 48);
}

} // namespace

GT4IosTouch gt4_ios_touch_read() {
  const std::uint64_t v = g_state.load(std::memory_order_relaxed);
  GT4IosTouch t;
  t.buttons = static_cast<std::uint16_t>(v);
  t.lx = static_cast<std::uint8_t>(v >> 16);
  t.ly = static_cast<std::uint8_t>(v >> 24);
  t.gas = static_cast<std::uint8_t>(v >> 32);
  t.brake = static_cast<std::uint8_t>(v >> 40);
  t.stick = ((v >> 48) & 1u) != 0;
  return t;
}

bool gt4_ios_tilt_axis(std::uint8_t *axis) {
  if (!gt4_ios_tilt_enabled())
    return false;
  CMDeviceMotion *motion = g_motion.deviceMotion;
  if (!motion)
    return false;
  // In landscape the device's y axis runs along the screen's width, so gravity on it is how far the phone is turned
  // like a steering wheel: right side down is a right turn. The angle ignores how far the phone leans back.
  const CMAcceleration g = motion.gravity;
  const double side = g_landscape_left.load(std::memory_order_relaxed) ? g.y : -g.y;
  const double degrees = std::atan2(side, std::hypot(g.x, g.z)) * 180.0 / M_PI;
  constexpr double kCentre = 1.5;  // holds the car straight against small hand movements
  const double past = std::max(0.0, std::abs(degrees) - kCentre) / std::max(1.0, gt4_ios_tilt_angle() - kCentre);
  const double value = std::copysign(std::min(1.0, past), degrees);
  *axis = static_cast<std::uint8_t>(std::clamp(128.0 + value * 127.0, 0.0, 255.0));
  return true;
}

void gt4_ios_touch_set_controller_connected(bool connected) { g_controller.store(connected, std::memory_order_relaxed); }

@interface GT4Control : NSObject
@property(nonatomic) Kind kind;
@property(nonatomic) int bit;
@property(nonatomic) CGRect rect;
@property(nonatomic, strong) CAShapeLayer *shape;
@property(nonatomic, strong) CATextLayer *text;
@property(nonatomic, strong) CALayer *fill;  // pedal level or stick knob
@property(nonatomic) BOOL round;
@end
@implementation GT4Control
@end

@interface GT4TouchOverlay : UIView
@property(nonatomic, weak) UIViewController *presenter;
- (void)applySettings;
@end

@implementation GT4TouchOverlay {
  NSMutableArray<GT4Control *> *_controls;
  GT4Control *_gear;
  NSMapTable<UITouch *, GT4Control *> *_touches;
  CALayer *_group;
  BOOL _controlsVisible;
  NSTimer *_timer;
  GT4Control *_stick;
  UITouch *_stickTouch;
  CGPoint _stickOrigin;  // where the stick's centre is while a thumb is on it
  CGPoint _stickRest;    // where the faint stick waits
  CGFloat _stickSize;
  NSArray<GT4Control *> *_face;
  int _buttonStyle;
  // The gear fades out a few seconds after the last touch anywhere on the screen and comes back with the next one.
  CFTimeInterval _lastTouch;
  BOOL _gearShown;
  BOOL _gearRevealTouch;  // the touch that brought the gear back only shows it
}

- (GT4Control *)addKind:(Kind)kind bit:(int)bit label:(NSString *)label round:(BOOL)round {
  GT4Control *c = [GT4Control new];
  c.kind = kind;
  c.bit = bit;
  c.round = round;
  c.shape = [CAShapeLayer layer];
  c.shape.fillColor = [UIColor colorWithWhite:0.08 alpha:0.55].CGColor;
  c.shape.strokeColor = [UIColor colorWithWhite:1 alpha:0.75].CGColor;
  c.shape.lineWidth = 1.5;
  c.text = [CATextLayer layer];
  c.text.string = label;
  c.text.font = (__bridge CFTypeRef)[UIFont systemFontOfSize:15 weight:UIFontWeightBold];
  c.text.fontSize = 15;
  c.text.alignmentMode = kCAAlignmentCenter;
  c.text.foregroundColor = UIColor.whiteColor.CGColor;
  c.text.contentsScale = UIScreen.mainScreen.nativeScale;
  if (kind == Kind::stick || kind == Kind::gas || kind == Kind::brake) {
    c.fill = [CALayer layer];
    c.fill.backgroundColor = (kind == Kind::brake ? UIColor.systemRedColor : kind == Kind::gas ? UIColor.systemGreenColor
                                                                                                : UIColor.whiteColor)
                                 .CGColor;
    c.fill.opacity = kind == Kind::stick ? 0.7f : 0.6f;
    [c.shape addSublayer:c.fill];
  }
  [_group addSublayer:c.shape];
  [_group addSublayer:c.text];
  [_controls addObject:c];
  return c;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self)
    return nil;
  self.multipleTouchEnabled = YES;
  self.backgroundColor = UIColor.clearColor;
  self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  _controls = [NSMutableArray array];
  _touches = [NSMapTable strongToStrongObjectsMapTable];
  _group = [CALayer layer];
  [self.layer addSublayer:_group];
  _stick = [self addKind:Kind::stick bit:0 label:@"" round:YES];
  [self addKind:Kind::dpad bit:0 label:@"" round:NO];
  [self addKind:Kind::brake bit:0 label:@"BRAKE" round:NO];
  [self addKind:Kind::gas bit:0 label:@"GAS" round:NO];
  // Top, right, bottom, left: the labels follow the Button style setting (applySettings).
  _face = @[
    [self addKind:Kind::button bit:kTriangle label:@"△" round:YES],
    [self addKind:Kind::button bit:kCircle label:@"○" round:YES],
    [self addKind:Kind::button bit:kCross label:@"✕" round:YES],
    [self addKind:Kind::button bit:kSquare label:@"□" round:YES],
  ];
  [self addKind:Kind::button bit:kL2 label:@"L2" round:NO];
  [self addKind:Kind::button bit:kL1 label:@"L1" round:NO];
  [self addKind:Kind::button bit:kR1 label:@"R1" round:NO];
  [self addKind:Kind::button bit:kR2 label:@"R2" round:NO];
  [self addKind:Kind::button bit:kSelect label:@"SELECT" round:NO];
  [self addKind:Kind::button bit:kStart label:@"START" round:NO];
  _gear = [GT4Control new];
  _gear.kind = Kind::gear;
  _gear.shape = [CAShapeLayer layer];
  _gear.shape.fillColor = [UIColor colorWithWhite:0.08 alpha:0.55].CGColor;
  _gear.shape.strokeColor = [UIColor colorWithWhite:1 alpha:0.75].CGColor;
  _gear.shape.lineWidth = 1.5;
  _gear.text = [CATextLayer layer];
  _gear.text.string = @"⚙︎";
  _gear.text.fontSize = 20;
  _gear.text.alignmentMode = kCAAlignmentCenter;
  _gear.text.foregroundColor = UIColor.whiteColor.CGColor;
  _gear.text.contentsScale = UIScreen.mainScreen.nativeScale;
  [self.layer addSublayer:_gear.shape];
  [self.layer addSublayer:_gear.text];
  // The controller can come and go at any moment.
  _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(applySettings) userInfo:nil repeats:YES];
  _buttonStyle = -1;
  _gearShown = YES;
  _lastTouch = CACurrentMediaTime();
  [self applySettings];
  return self;
}

- (void)place:(GT4Control *)c rect:(CGRect)rect {
  c.rect = rect;
  c.shape.frame = rect;
  CGRect local = CGRectMake(0, 0, rect.size.width, rect.size.height);
  c.shape.path = (c.round ? [UIBezierPath bezierPathWithOvalInRect:local]
                          : [UIBezierPath bezierPathWithRoundedRect:local cornerRadius:10])
                     .CGPath;
  const CGFloat lineHeight = 20;
  c.text.frame = CGRectMake(rect.origin.x, CGRectGetMidY(rect) - lineHeight / 2, rect.size.width, lineHeight);
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _group.frame = self.bounds;
  const UIEdgeInsets safe = self.safeAreaInsets;
  const CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
  const CGFloat left = std::max<CGFloat>(safe.left, 12) + 4, right = W - std::max<CGFloat>(safe.right, 12) - 4;
  const CGFloat bottom = H - std::max<CGFloat>(safe.bottom, 8) - 6, top = std::max<CGFloat>(safe.top, 8) + 34;
  const CGFloat pedalW = 84, pedalH = std::min<CGFloat>(190, H * 0.42);
  const CGFloat dpad = std::min<CGFloat>(96, H * 0.22), face = 44, reach = 46;
  _stickSize = std::min<CGFloat>(130, H * 0.29);
  NSEnumerator *e = [_controls objectEnumerator];
  [e nextObject];  // the stick places itself below
  // The stick's touch area is the whole left half below the menu row; the other controls there win over it.
  const CGFloat zoneTop = std::max<CGFloat>(safe.top, 8) + 34;
  _stick.rect = CGRectMake(0, zoneTop, W / 2, H - zoneTop);
  _stickRest = CGPointMake(left + 24 + _stickSize / 2, bottom - _stickSize / 2);
  [self place:e.nextObject rect:CGRectMake(left + 6, top + 34 + 10, dpad, dpad)];
  [self place:e.nextObject rect:CGRectMake(right - 2 * pedalW - 12, bottom - pedalH, pedalW, pedalH)];
  [self place:e.nextObject rect:CGRectMake(right - pedalW, bottom - pedalH, pedalW, pedalH)];
  const CGFloat faceX = right - pedalW - 6, faceY = bottom - pedalH - 16 - reach - face / 2;
  for (NSValue *offset in @[ @(CGPointMake(0, -reach)), @(CGPointMake(reach, 0)), @(CGPointMake(0, reach)), @(CGPointMake(-reach, 0)) ]) {
    const CGPoint o = offset.CGPointValue;
    [self place:e.nextObject rect:CGRectMake(faceX + o.x - face / 2, faceY + o.y - face / 2, face, face)];
  }
  const CGFloat shoulderW = 56, shoulderH = 34;
  [self place:e.nextObject rect:CGRectMake(left, top, shoulderW, shoulderH)];
  [self place:e.nextObject rect:CGRectMake(left + shoulderW + 8, top, shoulderW, shoulderH)];
  [self place:e.nextObject rect:CGRectMake(right - 2 * shoulderW - 8, top, shoulderW, shoulderH)];
  [self place:e.nextObject rect:CGRectMake(right - shoulderW, top, shoulderW, shoulderH)];
  const CGFloat menuW = 70, menuH = 30, menuY = std::max<CGFloat>(safe.top, 8);
  [self place:e.nextObject rect:CGRectMake(W / 2 - menuW - 34, menuY, menuW, menuH)];
  [self place:e.nextObject rect:CGRectMake(W / 2 + 34, menuY, menuW, menuH)];
  _gear.round = YES;
  [self place:_gear rect:CGRectMake(W / 2 - 18, menuY - 3, 36, 36)];
  [CATransaction commit];
  [self refresh];
}

- (void)applySettings {
  g_landscape_left.store(self.window.windowScene.interfaceOrientation == UIInterfaceOrientationLandscapeLeft,
                         std::memory_order_relaxed);
  if (gt4_ios_tilt_enabled() != static_cast<bool>(g_motion.deviceMotionActive)) {
    if (!g_motion)
      g_motion = [CMMotionManager new];
    if (gt4_ios_tilt_enabled()) {
      g_motion.deviceMotionUpdateInterval = 1.0 / 60.0;
      [g_motion startDeviceMotionUpdates];
    } else {
      [g_motion stopDeviceMotionUpdates];
    }
  }
  const int mode = gt4_ios_touch_mode();
  const BOOL show = mode == 1 || (mode == 0 && !g_controller.load(std::memory_order_relaxed));
  if (show != _controlsVisible) {
    _controlsVisible = show;
    if (!show) {
      // Fingers on controls that vanish must not leave anything pressed.
      NSMutableArray<UITouch *> *drop = [NSMutableArray array];
      for (UITouch *touch in _touches)
        if ([_touches objectForKey:touch] != _gear)
          [drop addObject:touch];
      for (UITouch *touch in drop)
        [_touches removeObjectForKey:touch];
      _stickTouch = nil;
      [self refresh];
    }
  }
  const int style = gt4_ios_button_style();
  if (style != _buttonStyle) {
    _buttonStyle = style;
    // Top, right, bottom, left in each style's own labels.
    NSArray<NSString *> *labels = style == 1 ? @[ @"Y", @"B", @"A", @"X" ] : style == 2 ? @[ @"X", @"A", @"B", @"Y" ]
                                                                                    : @[ @"△", @"○", @"✕", @"□" ];
    for (NSUInteger i = 0; i < _face.count; ++i)
      _face[i].text.string = labels[i];
  }
  const BOOL gear = CACurrentMediaTime() - _lastTouch < 4.0;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _group.hidden = !show;
  _group.opacity = static_cast<float>(gt4_ios_touch_opacity());
  [CATransaction commit];
  if (gear != _gearShown) {
    _gearShown = gear;
    [CATransaction begin];
    [CATransaction setAnimationDuration:gear ? 0.15 : 0.6];
    _gear.shape.opacity = _gear.text.opacity = gear ? std::max(0.35f, static_cast<float>(gt4_ios_touch_opacity())) : 0.0f;
    [CATransaction commit];
  }
}

- (GT4Control *)controlAt:(CGPoint)point {
  if (CGRectContainsPoint(CGRectInset(_gear.rect, -6, -6), point))
    return _gear;
  if (!_controlsVisible)
    return nil;
  for (GT4Control *c in _controls) {
    const CGFloat slack = c.kind == Kind::button ? -4 : -8;
    if (c != _stick && CGRectContainsPoint(CGRectInset(c.rect, slack, slack), point))
      return c;
  }
  return CGRectContainsPoint(_stick.rect, point) ? _stick : nil;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  if (!_gearShown && event.type == UIEventTypeTouches && CGRectContainsPoint(CGRectInset(_gear.rect, -6, -6), point))
    _gearRevealTouch = YES;
  // Every touch on the screen counts as activity for the gear, also the ones the game's own view receives.
  if (event.type == UIEventTypeTouches)
    [self noteTouch];
  return [self controlAt:point] ? self : nil;
}

- (void)noteTouch {
  _lastTouch = CACurrentMediaTime();
  if (!_gearShown)
    [self applySettings];
}

- (void)refresh {
  GT4IosTouch state;
  CGPoint stickAt = CGPointZero;
  BOOL stickActive = NO;
  CGFloat gas = 0, brake = 0;
  std::uint16_t pressed = 0;
  NSMutableSet<GT4Control *> *held = [NSMutableSet set];
  for (UITouch *touch in _touches) {
    GT4Control *c = [_touches objectForKey:touch];
    const CGPoint p = [touch locationInView:self];
    [held addObject:c];
    const CGPoint center = CGPointMake(CGRectGetMidX(c.rect), CGRectGetMidY(c.rect));
    switch (c.kind) {
      case Kind::button:
        pressed |= static_cast<std::uint16_t>(1u << c.bit);
        break;
      case Kind::dpad: {
        // Eight directions: an axis counts once the finger is off the centre by a third of the pad's half size.
        const CGFloat dx = p.x - center.x, dy = p.y - center.y, dead = c.rect.size.width / 6;
        if (dx > dead) pressed |= 1u << kRight;
        if (dx < -dead) pressed |= 1u << kLeft;
        if (dy > dead) pressed |= 1u << kDown;
        if (dy < -dead) pressed |= 1u << kUp;
        break;
      }
      case Kind::stick: {
        // The centre stays where the thumb landed, and is pulled along when the thumb slides past the edge, so
        // turning back responds at once.
        const CGFloat r = _stickSize / 2;
        CGFloat x = (p.x - _stickOrigin.x) / r, y = (p.y - _stickOrigin.y) / r;
        const CGFloat length = std::hypot(x, y);
        if (length > 1) {
          x /= length;
          y /= length;
          _stickOrigin = CGPointMake(p.x - x * r, p.y - y * r);
        }
        stickAt = CGPointMake(x, y);
        stickActive = YES;
        state.lx = static_cast<std::uint8_t>(std::clamp(128.0 + x * 127.0, 0.0, 255.0));
        state.ly = static_cast<std::uint8_t>(std::clamp(128.0 + y * 127.0, 0.0, 255.0));
        state.stick = true;
        break;
      }
      case Kind::gas:
      case Kind::brake: {
        // On or off, like a phone racing game: a finger anywhere on the pedal is full.
        if (c.kind == Kind::gas) gas = 1;
        else brake = 1;
        break;
      }
      case Kind::gear:
        break;
    }
  }
  state.buttons = pressed;
  state.gas = static_cast<std::uint8_t>(gas * 255.0);
  state.brake = static_cast<std::uint8_t>(brake * 255.0);
  g_state.store(pack(state), std::memory_order_relaxed);

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (GT4Control *c in _controls) {
    const BOOL on = [held containsObject:c];
    c.shape.fillColor = [UIColor colorWithWhite:on ? 0.55 : 0.08 alpha:on ? 0.75 : 0.55].CGColor;
    const CGFloat w = c.rect.size.width, h = c.rect.size.height;
    if (c.kind == Kind::stick) {
      const CGFloat size = _stickSize, knob = size * 0.42, r = (size - knob) / 2;
      const CGPoint at = stickActive ? stickAt : CGPointZero;
      const CGPoint centre = stickActive ? _stickOrigin : _stickRest;
      c.shape.frame = CGRectMake(centre.x - size / 2, centre.y - size / 2, size, size);
      c.shape.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)].CGPath;
      c.shape.opacity = stickActive ? 1.0f : 0.45f;
      c.fill.frame = CGRectMake(size / 2 - knob / 2 + at.x * r, size / 2 - knob / 2 + at.y * r, knob, knob);
      c.fill.cornerRadius = knob / 2;
    } else if (c.kind == Kind::gas || c.kind == Kind::brake) {
      const CGFloat level = (c.kind == Kind::gas ? gas : brake) * h;
      c.fill.frame = CGRectMake(0, h - level, w, level);
      c.fill.cornerRadius = 10;
    } else if (c.kind == Kind::dpad) {
      // A cross drawn inside the pad's outline.
      UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, h / 3, w, h / 3) cornerRadius:8];
      [path appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(w / 3, 0, w / 3, h) cornerRadius:8]];
      path.usesEvenOddFillRule = NO;
      c.shape.path = path.CGPath;
    }
  }
  [CATransaction commit];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  for (UITouch *touch in touches) {
    GT4Control *c = [self controlAt:[touch locationInView:self]];
    if (!c)
      continue;
    if (c == _gear && _gearRevealTouch) {
      // The gear was hidden when this finger landed: it only comes back, a second tap opens the settings.
      _gearRevealTouch = NO;
      continue;
    }
    if (c == _stick) {
      // One thumb steers; another finger landing in the zone is ignored.
      if (_stickTouch)
        continue;
      _stickTouch = touch;
      _stickOrigin = [touch locationInView:self];
    }
    [_touches setObject:c forKey:touch];
  }
  [self refresh];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  for (UITouch *touch in touches) {
    GT4Control *held = [_touches objectForKey:touch];
    // A finger can slide from one face or shoulder button onto the next.
    if (held.kind == Kind::button) {
      GT4Control *now = [self controlAt:[touch locationInView:self]];
      if (now && now.kind == Kind::button)
        [_touches setObject:now forKey:touch];
    }
  }
  [self refresh];
}

- (void)endTouches:(NSSet<UITouch *> *)touches openGear:(BOOL)open {
  BOOL gearTapped = NO;
  for (UITouch *touch in touches) {
    GT4Control *held = [_touches objectForKey:touch];
    if (held == _gear && open && CGRectContainsPoint(CGRectInset(_gear.rect, -12, -12), [touch locationInView:self]))
      gearTapped = YES;
    if (touch == _stickTouch)
      _stickTouch = nil;
    [_touches removeObjectForKey:touch];
  }
  [self refresh];
  if (gearTapped && self.presenter)
    gt4_ios_open_settings(self.presenter);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self endTouches:touches openGear:YES];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self endTouches:touches openGear:NO];
}

@end

void gt4_ios_install_touch_controls(UIViewController *controller) {
  GT4TouchOverlay *overlay = [[GT4TouchOverlay alloc] initWithFrame:controller.view.bounds];
  overlay.presenter = controller;
  [controller.view addSubview:overlay];
}
