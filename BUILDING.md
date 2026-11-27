# Building GT4 Spec II for iPhone, step by step

This guide assumes you've never built an app before. The first build takes 10 to 60 minutes depending on your Mac,
plus the time to install Xcode.

## 1. Set up your Mac (once)

You need a Mac with Apple silicon (M1 or newer).

1. **Install Xcode** from the App Store (it's free and large). Open it once, accept the licence, and let it install
   its components. In **Xcode → Settings → Components**, make sure an **iOS** platform is installed.
2. **Install Homebrew**, a tool that installs other tools. Open the **Terminal** app and paste the command from
   [brew.sh](https://brew.sh). Follow what it prints at the end (it may ask you to run two more lines).
3. **Install the build tools.** In Terminal:

   ```bash
   brew install bash cmake ninja python rust glslang
   ```

## 2. Get the code

Download this repository: on GitHub, **Code → Download ZIP**, then unzip it. Or, in Terminal:

```bash
git clone https://github.com/xador19/GT4-Spec-II-ios-port.git
```

**Optional, for a build with no downloads:** from this repository's **Releases** page on GitHub, download the sources bundle
(`gt4spec2-ios-deps-1.tar`, about 120 MB) and put it in a `deps` folder inside the repository folder. The build then
takes everything from it; without it, the build fetches the same pinned sources from their official sites.

Put the folder somewhere **without spaces in its path** (for example `~/GT4SpecII`, not `~/My Games/GT4 Spec II`).

## 3. Make your Spec II disc image

The app is built from **Gran Turismo 4 Spec II v1.10**, a community mod of GT4. You make it from your own disc:

1. Dump your **Gran Turismo 4 Online Public Beta (USA)** disc (SCUS-97436) to an `.iso`.
2. Download the **Spec II v1.10** patch from the [Spec II website](https://www.theadmiester.co.uk/specii/) and apply
   it to that `.iso` as its instructions describe (it's an xdelta patch; the site links patching tools).
3. You now have something like `Gran Turismo 4 (USA) (Spec II v1.10).iso`.

The build checks this file. If it says the image doesn't match, the patch was applied to a different disc or a
different Spec II version; this port needs exactly v1.10.

## 4. Build the app

In Terminal, go into the folder and run the build with your disc image (drag the `.iso` onto the Terminal window to
paste its path):

```bash
cd ~/GT4SpecII
./make_ipa.sh "/path/to/Gran Turismo 4 (USA) (Spec II v1.10).iso"
```

It goes through seven steps and prints what it's doing. The first run downloads and builds everything it needs,
which takes 10 to 60 minutes depending on your Mac. Every download is locked to an exact version and checked
before it's used; if one doesn't match, the build stops. If a step fails, it shows the end of that step's log and the log's name in
`build/logs/`.

When it's done you'll have **`dist/GT4SpecII.ipa`**.

Options:

- `--icon picture.png` uses your own square picture as the home screen icon.
- `--clean` starts over from nothing (for example after a failed first run you can't make sense of).

## 5. Put it on your iPhone

The `.ipa` isn't signed. A sideloading tool signs it with your Apple ID:

- **[Sideloadly](https://sideloadly.io):** connect your iPhone, drag `GT4SpecII.ipa` into Sideloadly, enter your
  Apple ID and press Start.
- **[AltStore](https://altstore.io):** install AltStore on the phone, then open `GT4SpecII.ipa` with it.

On the iPhone, the first time: **Settings → General → VPN & Device Management**, trust your Apple ID, and turn on
**Settings → Privacy & Security → Developer Mode** if iOS asks for it.

With a free Apple ID the app stops opening after 7 days; refresh it with Sideloadly or AltStore. Your save stays.

## 6. Copy your files to the phone

Connect the iPhone to the Mac, open **Finder**, click your iPhone in the sidebar, then the **Files** tab. You'll see
**GT4 Spec II**. Drag files onto it:

| What | Where in the GT4 Spec II folder |
|---|---|
| The same `.iso` you built from (needed) | anywhere at the top level |
| Your memory card (optional) | `memcards/spec2.ps2` |
| An HD texture pack (optional) | `gt4-gs/textures/SCUS-97436/` |

- **The disc image** is about 3.4 GB; copying takes a few minutes.
- **A memory card** from PCSX2 (`Mcd001.ps2`) or another emulator works as is; rename it to `spec2.ps2`. Without one,
  the app makes a new card. Make a copy of your card first, in case anything goes wrong.
- **Texture packs** are PCSX2 packs for SCUS-97436, such as the
  [Gran Turismo 4 Retexture Mod](https://www.gtplanet.net/forum/threads/gran-turismo-4-retexture-mod-v3-0-4.408852/) or the
  [HD HUD pack](https://www.gtplanet.net/forum/threads/gt4-hd-hud-and-user-interface-texture-pack-for-pcsx2.417873).
  The folder must end up as `gt4-gs/textures/SCUS-97436/replacements/...`. A full pack is many thousands of files; if
  you already have it on the phone (for example in another emulator's folder), move it with the Files app instead of
  copying it again from the Mac.

The folders `memcards` and `gt4-gs/textures` appear after the first start; you can also create them yourself.

## 7. Play

Open **GT4 Spec II**. The first start takes a little longer while it scans your texture pack. A counter in the top
left shows the frame rate (60 is full speed).

- **Controller:** connect it in the iPhone's Bluetooth settings before opening the game, or plug it in. PlayStation,
  Xbox and MFi controllers work.
- **Touch:** the controls appear when no controller is connected. Put your left thumb anywhere on the left half to
  steer; hold the GAS and BRAKE pedals on the right.
- **Settings:** tap the gear at the top (it hides after a few seconds; touch the screen to bring it back). The game
  pauses while settings are open.

### Settings

| Setting | What it does | Applies |
|---|---|---|
| Touch controls | Auto (only without a controller), On or Off | now |
| Button style | PlayStation, Xbox or Nintendo labels on the touch buttons | now |
| Opacity | how see-through the touch controls are | now |
| Tilt steering | steer by turning the phone; Tilt sensitivity sets how far | now |
| Trigger range | lower it if the throttle reaches 100% too early on your controller | now |
| Triggers as right stick | throttle and brake on the triggers (see below) | now |
| Vibration | controller vibration strength | now |
| Renderer | PCSX2 (default) or CoreGS 2.0 (experimental) | next start |
| Resolution | 2×, 3× or 4× (4× is the sharpest, but heavy) | next start |
| Blending, Sharpening | picture quality (PCSX2) | next start |
| Texture pack | turn the HD textures off or on | next start |
| Frame rate counter | the number in the top left | now |

**Close the game now** restarts it with new picture settings. Save in the game first.

### Analog throttle and brake on the triggers

GT4 treats a half-pressed trigger as full throttle. To get the whole trigger range:

1. Keep **Triggers as right stick** on (it is by default).
2. In GT4: **Options → Controller**, set **accelerator and brake to the right analog stick**.

Now RT is gas and LT is brake, smooth across the whole pull. The touch pedals also drive the right stick, so they keep
working with this setting.

## Troubleshooting

- **"this is not the Gran Turismo 4 Spec II v1.10 image":** see step 3. Only Spec II v1.10 on the Online Public
  Beta (USA) disc works.
- **"missing tools":** run the `brew install` line it prints.
- **The build stops at a step:** open the log it names in `build/logs/`. Running `./make_ipa.sh` again continues where
  it stopped. If something got into a bad state, add `--clean`.
- **The app says to copy your disc image into its folder:** the `.iso` isn't in the GT4 Spec II folder on the phone
  yet (step 6).
- **The app closes right away on an older iPhone:** it may be running out of memory. Try 2× resolution.
- **Stutters:** the first time each car or track is drawn, its shaders are built; after that they're remembered.
  If a whole track runs slow, lower the resolution.
- **Buttons stick or the controller stops responding for a few seconds:** usually the controller's Bluetooth link.
  Check whether it happens in other games, try re-pairing, or use a cable.
- **Throttle jumps to 100%:** see *Analog throttle and brake on the triggers*. Some controllers also have a "hair
  trigger" mode that makes triggers act on/off; turn it off in the controller.
- **Something else:** the app writes a log, `gt4.log`, in the GT4 Spec II folder. Attach it to an issue on GitHub.
