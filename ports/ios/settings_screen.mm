// SPDX-License-Identifier: MIT
// iOS: the settings screen, a standard iOS list opened from the gear button. The game waits while it is open. Controls,
// vibration and the frame-rate counter apply at once and are kept in NSUserDefaults; the picture settings are lines of
// Documents/gt4-gs.ini, which the renderer reads when the game starts.
#import <UIKit/UIKit.h>

#include "ios_ui.h"
#include "settings_screen.h"

#include <atomic>

namespace {

NSString *const kTouchMode = @"gt4.touch.mode", *const kTouchOpacity = @"gt4.touch.opacity";
NSString *const kRumbleGain = @"gt4.rumble.gain", *const kTriggersToStick = @"gt4.triggers.rstick";
NSString *const kShowFps = @"gt4.fps.visible", *const kPedalRange = @"gt4.pedal.range";
NSString *const kTilt = @"gt4.tilt.enabled", *const kTiltAngle = @"gt4.tilt.angle";
NSString *const kButtonStyle = @"gt4.buttons.style", *const kRenderer = @"gt4.renderer";

std::atomic<bool> g_paused{false};

NSUserDefaults *defaults() {
  static NSUserDefaults *values = [] {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d registerDefaults:@{kTouchMode : @0, kTouchOpacity : @0.6, kRumbleGain : @1.3, kTriggersToStick : @YES, kShowFps : @YES,
                            kPedalRange : @1.0, kTilt : @NO, kTiltAngle : @35.0, kButtonStyle : @0, kRenderer : @0}];
    return d;
  }();
  return values;
}

NSString *ini_path() {
  NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  return [documents stringByAppendingPathComponent:@"gt4-gs.ini"];
}

// The value of a key of gt4-gs.ini, or nil.
NSString *ini_get(NSString *key) {
  NSString *text = [NSString stringWithContentsOfFile:ini_path() encoding:NSUTF8StringEncoding error:nil];
  NSString *prefix = [key stringByAppendingString:@" ="];
  for (NSString *line in [text componentsSeparatedByString:@"\n"])
    if ([line hasPrefix:prefix])
      return [[line substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  return nil;
}

// Replaces a key's line, or adds it to [EmuCore/GS].
void ini_set(NSString *key, NSString *value) {
  NSString *text = [NSString stringWithContentsOfFile:ini_path() encoding:NSUTF8StringEncoding error:nil] ?: @"[EmuCore/GS]\n";
  NSMutableArray<NSString *> *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
  NSString *prefix = [key stringByAppendingString:@" ="];
  NSString *entry = [NSString stringWithFormat:@"%@ = %@", key, value];
  BOOL found = NO;
  for (NSUInteger i = 0; i < lines.count; ++i)
    if ([lines[i] hasPrefix:prefix]) {
      lines[i] = entry;
      found = YES;
    }
  if (!found) {
    const NSUInteger section = [lines indexOfObject:@"[EmuCore/GS]"];
    [lines insertObject:entry atIndex:section == NSNotFound ? lines.count : section + 1];
  }
  [[lines componentsJoinedByString:@"\n"] writeToFile:ini_path() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

} // namespace

int gt4_ios_touch_mode() { return static_cast<int>([defaults() integerForKey:kTouchMode]); }
double gt4_ios_touch_opacity() { return [defaults() doubleForKey:kTouchOpacity]; }
double gt4_ios_rumble_gain() { return [defaults() doubleForKey:kRumbleGain]; }
bool gt4_ios_triggers_to_rstick() { return [defaults() boolForKey:kTriggersToStick]; }
double gt4_ios_pedal_range() { return [defaults() doubleForKey:kPedalRange]; }
const char *gt4_ios_renderer_choice() { return [defaults() integerForKey:kRenderer] == 1 ? "hw" : "pcsx2"; }
int gt4_ios_button_style() { return static_cast<int>([defaults() integerForKey:kButtonStyle]); }
bool gt4_ios_tilt_enabled() { return [defaults() boolForKey:kTilt]; }
double gt4_ios_tilt_angle() { return [defaults() doubleForKey:kTiltAngle]; }
bool gt4_ios_fps_visible() { return [defaults() boolForKey:kShowFps]; }
bool gt4_ios_ui_paused() { return g_paused.load(std::memory_order_relaxed); }

@interface GT4Row : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) UIView *accessory;
@property(nonatomic, copy) void (^tap)(void);
@end
@implementation GT4Row
@end

@interface GT4SettingsController : UITableViewController
@end

@implementation GT4SettingsController {
  NSArray<NSArray<GT4Row *> *> *_sections;
  NSArray<NSString *> *_headers;
  NSArray<NSString *> *_footers;
}

- (GT4Row *)row:(NSString *)title view:(UIView *)view {
  GT4Row *row = [GT4Row new];
  row.title = title;
  row.accessory = view;
  return row;
}

- (GT4Row *)row:(NSString *)title segments:(NSArray<NSString *> *)items selected:(NSInteger)selected changed:(void (^)(NSInteger))changed {
  UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:items];
  control.selectedSegmentIndex = selected;
  [control addAction:[UIAction actionWithHandler:^(UIAction *action) {
             changed(((UISegmentedControl *)action.sender).selectedSegmentIndex);
           }]
      forControlEvents:UIControlEventValueChanged];
  [control sizeToFit];
  return [self row:title view:control];
}

- (GT4Row *)row:(NSString *)title on:(BOOL)on changed:(void (^)(BOOL))changed {
  UISwitch *control = [UISwitch new];
  control.on = on;
  [control addAction:[UIAction actionWithHandler:^(UIAction *action) { changed(((UISwitch *)action.sender).isOn); }]
      forControlEvents:UIControlEventValueChanged];
  return [self row:title view:control];
}

- (GT4Row *)row:(NSString *)title from:(float)low to:(float)high value:(float)value changed:(void (^)(float))changed {
  UISlider *control = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 220, 32)];
  control.minimumValue = low;
  control.maximumValue = high;
  control.value = value;
  [control addAction:[UIAction actionWithHandler:^(UIAction *action) { changed(((UISlider *)action.sender).value); }]
      forControlEvents:UIControlEventValueChanged];
  return [self row:title view:control];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Settings";
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                         target:self
                                                                                         action:@selector(done)];
  NSUserDefaults *d = defaults();
  const NSArray<NSNumber *> *scales = @[ @2, @3, @4 ];
  NSInteger scale = [scales indexOfObject:@(ini_get(@"upscale_multiplier").integerValue)];
  if (scale == NSNotFound)
    scale = 1;
  const NSInteger blending = ini_get(@"accurate_blending_unit").integerValue >= 3 ? 1 : 0;
  const BOOL textures = ![ini_get(@"LoadTextureReplacements") isEqualToString:@"false"];
  const NSInteger cas = ini_get(@"CASMode").integerValue > 0 ? 1 : 0;
  GT4Row *restart = [GT4Row new];
  restart.title = @"Close the game now";
  __weak GT4SettingsController *weakSelf = self;
  restart.tap = ^{ [weakSelf confirmClose]; };
  _sections = @[
    @[
      [self row:@"Touch controls" segments:@[ @"Auto", @"On", @"Off" ] selected:[d integerForKey:kTouchMode] changed:^(NSInteger i) { [d setInteger:i forKey:kTouchMode]; }],
      [self row:@"Button style" segments:@[ @"PlayStation", @"Xbox", @"Nintendo" ] selected:[d integerForKey:kButtonStyle] changed:^(NSInteger i) { [d setInteger:i forKey:kButtonStyle]; }],
      [self row:@"Opacity" from:0.15f to:1.0f value:[d floatForKey:kTouchOpacity] changed:^(float v) { [d setFloat:v forKey:kTouchOpacity]; }],
      [self row:@"Tilt steering" on:[d boolForKey:kTilt] changed:^(BOOL on) { [d setBool:on forKey:kTilt]; }],
      // Right = more sensitive: less tilt for full lock.
      [self row:@"Tilt sensitivity" from:-60.0f to:-15.0f value:-[d floatForKey:kTiltAngle] changed:^(float v) { [d setFloat:-v forKey:kTiltAngle]; }],
    ],
    @[
      [self row:@"Trigger range" from:0.2f to:1.0f value:[d floatForKey:kPedalRange] changed:^(float v) { [d setFloat:v forKey:kPedalRange]; }],
      [self row:@"Triggers as right stick" on:[d boolForKey:kTriggersToStick] changed:^(BOOL on) { [d setBool:on forKey:kTriggersToStick]; }],
      [self row:@"Vibration" from:0.0f to:3.0f value:[d floatForKey:kRumbleGain] changed:^(float v) { [d setFloat:v forKey:kRumbleGain]; }],
    ],
    @[
      [self row:@"Renderer" segments:@[ @"PCSX2", @"CoreGS 2.0" ] selected:[d integerForKey:kRenderer] changed:^(NSInteger i) { [d setInteger:i forKey:kRenderer]; }],
      [self row:@"Resolution" segments:@[ @"2×", @"3×", @"4×" ] selected:scale changed:^(NSInteger i) { ini_set(@"upscale_multiplier", scales[i].stringValue); }],
      [self row:@"Blending" segments:@[ @"Basic", @"High" ] selected:blending changed:^(NSInteger i) { ini_set(@"accurate_blending_unit", i == 1 ? @"3" : @"1"); }],
      [self row:@"Sharpening" on:cas == 1 changed:^(BOOL on) { ini_set(@"CASMode", on ? @"1" : @"0"); }],
      [self row:@"Texture pack" on:textures changed:^(BOOL on) { ini_set(@"LoadTextureReplacements", on ? @"true" : @"false"); }],
      restart,
    ],
    @[
      [self row:@"Frame rate counter" on:[d boolForKey:kShowFps] changed:^(BOOL on) { [d setBool:on forKey:kShowFps]; }],
    ],
  ];
  _headers = @[ @"Touch", @"Controller", @"Picture", @"Display" ];
  _footers = @[
    @"Auto shows the touch controls only while no controller is connected. Button style changes the face button labels; the button in each position does the same thing in the game. Tilt steering works with or without the touch controls.",
    @"For throttle and brake on the triggers, set GT4's accelerator and brake to the right analog stick. If gas reaches 100% too early, lower Trigger range.",
    @"Picture settings apply the next time the game starts. Save your game before closing it. CoreGS 2.0 is the project's own renderer (experimental on iPhone); Blending and Sharpening apply to PCSX2 only.",
    @"",
  ];
}

- (void)confirmClose {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Close the game?"
                                                                 message:@"Anything you haven't saved in the game is lost. Open the app again to play with the new settings."
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Close Game" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *) { exit(0); }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)done {
  [self.presentingViewController dismissViewControllerAnimated:YES completion:^{ g_paused.store(false, std::memory_order_relaxed); }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return static_cast<NSInteger>(_sections.count); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return static_cast<NSInteger>(_sections[section].count); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return _headers[section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return _footers[section].length ? _footers[section] : nil; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  GT4Row *row = _sections[indexPath.section][indexPath.row];
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
  cell.textLabel.text = row.title;
  cell.accessoryView = row.accessory;
  if (row.tap)
    cell.textLabel.textColor = UIColor.systemRedColor;
  else
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  GT4Row *row = _sections[indexPath.section][indexPath.row];
  if (row.tap)
    row.tap();
}

@end

void gt4_ios_open_settings(UIViewController *presenter) {
  if (presenter.presentedViewController)
    return;
  g_paused.store(true, std::memory_order_relaxed);
  GT4SettingsController *settings = [[GT4SettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
  UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
  navigation.modalPresentationStyle = UIModalPresentationFormSheet;
  navigation.modalInPresentation = YES;  // only Done closes it, so the game always resumes
  navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
  [presenter presentViewController:navigation animated:YES completion:nil];
}
