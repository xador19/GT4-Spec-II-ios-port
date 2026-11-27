// SPDX-License-Identifier: MIT
// iOS entry point. The pinned donor main.cpp is compiled with `main` renamed to gt4_donor_main (as native/game_main.cpp
// does on Windows); this file builds the command line the launcher would pass and calls it inside SDL's app loop.
//
// The app's Documents folder (Files app > On My iPhone > GT4 Spec II) holds everything the player owns:
//   *.iso            the player's own Gran Turismo 4 Spec II 1.10 disc image (the first .iso found is used)
//   memcards/        the memory card (spec2.ps2; a missing card is blank and the game creates it on first save)
//   env.txt          optional NAME=value lines (GT4_* options of docs/, for example GT4_PACING=audio)
//   gt4.log          the log of the last session
// The translated game ELF (SCUS_974.36) and the GS shaders are inside the app bundle.
#include "ios_ui.h"
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <unistd.h>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

int gt4_donor_main(int argc, char **argv);

namespace {

std::filesystem::path documents_folder() {
  NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  return std::filesystem::path(paths.firstObject.UTF8String);
}

std::filesystem::path bundle_folder() { return std::filesystem::path(NSBundle.mainBundle.resourcePath.UTF8String); }

// NAME=value per line; blank lines and lines starting with # are ignored. Values never override the environment.
void apply_env_file(const std::filesystem::path &file) {
  std::ifstream input(file);
  std::string line;
  while (std::getline(input, line)) {
    if (!line.empty() && line.back() == '\r')
      line.pop_back();
    if (line.empty() || line[0] == '#')
      continue;
    const auto equals = line.find('=');
    if (equals == std::string::npos || equals == 0)
      continue;
    setenv(line.substr(0, equals).c_str(), line.substr(equals + 1).c_str(), 0);
    std::fprintf(stderr, "[ios] env.txt: %s\n", line.c_str());
  }
}

std::filesystem::path find_disc(const std::filesystem::path &folder) {
  std::error_code error;
  for (const auto &entry : std::filesystem::directory_iterator(folder, error)) {
    std::string extension = entry.path().extension().string();
    for (char &c : extension)
      c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (entry.is_regular_file(error) && extension == ".iso")
      return entry.path();
  }
  return {};
}

// Documents/gt4-gs.ini: the PCSX2 GS settings (the keys of gs-settings-allowlist.json in gt4recomp-gs). Edits made in
// the Files app are kept; only the folder paths are refreshed. A file from older defaults (no kDefaultsMarker line) is
// replaced by the current ones.
//   upscale_multiplier 3: 1920x1344, about the 2034x1398 screen. 4 held 60 fps in one race but fell to 40 fps for a
//   minute on another track (GPU-bound: 12-15 ms/frame of GS back-pressure), so 3 is the default.
//   accurate_blending_unit 3 (High): the level the PCSX2 game database recommends for GT4.
//   LoadTextureReplacements: texture packs in Documents/gt4-gs/textures/SCUS-97436/replacements, loaded in the
//   background (a pack is far larger than memory, so nothing is precached).
constexpr const char *kDefaultsMarker = "; defaults 2";

std::filesystem::path write_default_gs_config(const std::filesystem::path &documents) {
  const std::filesystem::path data = documents / "gt4-gs";
  const std::filesystem::path config = documents / "gt4-gs.ini";
  std::filesystem::create_directories(data / "cache");
  std::filesystem::create_directories(data / "textures");
  // PCSX2 first sets up $HOME/Library/Application Support/PCSX2 and creates only its last folder; a fresh app container
  // has no Application Support folder.
  std::filesystem::create_directories(documents.parent_path() / "Library" / "Application Support");
  if (std::filesystem::exists(config)) {
    // iOS moves the app's data container on every install: point the folder keys at this container again and keep
    // every other line the user may have edited.
    std::ifstream input(config);
    std::string text, line;
    bool current = false;
    while (std::getline(input, line)) {
      if (line == kDefaultsMarker)
        current = true;
      else if (line.rfind("Cache =", 0) == 0)
        line = "Cache = " + (data / "cache").string();
      else if (line.rfind("Textures =", 0) == 0)
        line = "Textures = " + (data / "textures").string();
      else if (line.rfind("DataRoot =", 0) == 0)
        line = "DataRoot = " + data.string();
      text += line + "\n";
    }
    input.close();
    if (current) {
      std::ofstream(config) << text;
      return config;
    }
  }
  std::ofstream output(config);
  output << "; PCSX2 GS settings of GT4 Spec II (iOS). Delete this file to get the defaults back.\n"
         << kDefaultsMarker << "\n"
            "[EmuCore/GS]\n"
            "Renderer = 14\n"
            "upscale_multiplier = 3\n"
            "accurate_blending_unit = 3\n"
            "MaxAnisotropy = 16\n"
            "hw_mipmap = true\n"
            "deinterlace_mode = 0\n"
            "AspectRatio = 16:9\n"
            "VsyncEnable = true\n"
            "HWDownloadMode = 0\n"
            "LoadTextureReplacements = true\n"
            "LoadTextureReplacementsAsync = true\n"
            "PrecacheTextureReplacements = false\n"
            "\n"
            "[Folders]\n"
            "Cache = " << (data / "cache").string() << "\n"
            "Textures = " << (data / "textures").string() << "\n"
            "\n"
            "[GT4GS]\n"
            "DataRoot = " << data.string() << "\n";
  std::fprintf(stderr, "[ios] wrote the default GS settings %s\n", config.c_str());
  return config;
}

// Documents/controls.toml (docs/CONTROLS.md): written once, then the user's. GT4 scales the PS2 pressure buttons up
// (it was tuned for the DualShock 2's analog buttons), so a trigger pulled about halfway already counts as full
// throttle or brake. Scaling the trigger pressure to 0.55 makes a nearly full pull reach 100%, the way Silent's
// "Adjusted triggers sensitivity" patch describes it (that patch is a reference only; the game code is unchanged).
// The smaller deadzone (0.04 instead of 30/255) keeps the first part of the travel usable.
std::filesystem::path write_default_controls(const std::filesystem::path &documents) {
  const std::filesystem::path controls = documents / "controls.toml";
  if (std::filesystem::exists(controls))
    return controls;
  std::ofstream(controls) << "# GT4 Spec II controls (docs/CONTROLS.md). Delete this file to get the defaults back.\n"
                             "# Triggers: scale 0.55 makes a nearly full pull reach the game's 100% throttle/brake;\n"
                             "# raise it toward 1.0 if the triggers feel too weak, lower it if full comes too early.\n"
                             "schema = 1\n"
                             "\n"
                             "[bindings]\n"
                             "r2 = [\"xinput:RT | deadzone=0.04 scale=0.55\"]\n"
                             "l2 = [\"xinput:LT | deadzone=0.04 scale=0.55\"]\n";
  std::fprintf(stderr, "[ios] wrote the default controls %s\n", controls.c_str());
  return controls;
}

// The value of a key of gt4-gs.ini, or `fallback`.
std::string ini_value(const std::filesystem::path &config, const char *key, const char *fallback) {
  std::ifstream input(config);
  const std::string prefix = std::string(key) + " =";
  std::string line;
  while (std::getline(input, line))
    if (line.rfind(prefix, 0) == 0) {
      std::string value = line.substr(prefix.size());
      value.erase(0, value.find_first_not_of(' '));
      return value;
    }
  return fallback;
}

int show_problem(const char *text) {
  std::fprintf(stderr, "[ios] %s\n", text);
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Gran Turismo 4 Spec II", text, nullptr);
  return 1;
}

} // namespace

int main(int, char **) {
  const std::filesystem::path documents = documents_folder();
  const std::filesystem::path log = documents / "gt4.log";
  std::freopen(log.c_str(), "w", stderr);
  std::setvbuf(stderr, nullptr, _IOLBF, 0);
  // The PCSX2 GS thread writes its console to stdout: into the same log.
  dup2(fileno(stderr), fileno(stdout));
  std::setvbuf(stdout, nullptr, _IOLBF, 0);
  std::filesystem::current_path(documents);
  apply_env_file(documents / "env.txt");
  // Timing report in gt4.log every 5 s (window_sdl.cpp, ios_interval_report); GT4_PERF=0 in env.txt turns it off.
  setenv("GT4_PERF", "1", 0);
  // The renderer from the settings screen: the PCSX2 GS inside the app (gs_stream_ipc.cpp runs it on a thread) or
  // CoreGS 2.0 (native/hw_gs, on MoltenVK). GT4_RENDERER in env.txt wins; donor picks the old built-in one.
  setenv("GT4_RENDERER", gt4_ios_renderer_choice(), 0);
  const std::filesystem::path gs_config = write_default_gs_config(documents);
  setenv("GT4_GS_CONFIG", gs_config.c_str(), 0);
  if (std::strcmp(std::getenv("GT4_RENDERER"), "hw") == 0) {
    // CoreGS 2.0 reads its options from the environment (the PC launcher's coregs20_environment): the resolution of
    // the settings screen, the texture pack folder (scanned recursively) and its own compiled-pipeline cache.
    setenv("GT4_HW_CORE", "2", 0);
    setenv("GT4_HW_SCALE", ini_value(gs_config, "upscale_multiplier", "3").c_str(), 0);
    if (ini_value(gs_config, "LoadTextureReplacements", "true") != "false")
      setenv("GT4_HW_TEXTURES", (documents / "gt4-gs" / "textures" / "SCUS-97436").c_str(), 0);
    std::filesystem::create_directories(documents / "gt4-gs" / "coregs2-cache");
    setenv("GT4_HW_SHADER_CACHE", (documents / "gt4-gs" / "coregs2-cache").c_str(), 0);
  }
  // Lower input lag: the game waits for the GS to finish one frame before it sends the next (the default lets two
  // queue up). The game uses about half of each frame, so this costs no speed.
  setenv("GT4_GS_FRAMES_IN_FLIGHT", "1", 0);
  const std::filesystem::path controls = write_default_controls(documents);
  setenv("GT4_CONTROLS_FILE", controls.c_str(), 0);

  SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
  SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");

  const std::filesystem::path elf = bundle_folder() / "SCUS_974.36";
  const std::filesystem::path disc = find_disc(documents);
  if (disc.empty())
    return show_problem("Copy your Gran Turismo 4 Spec II 1.10 disc image (.iso) into this app's folder in the "
                        "Files app (On My iPhone > GT4 Spec II), then open the app again.");
  std::filesystem::create_directories(documents / "memcards");
  const std::filesystem::path card = documents / "memcards" / "spec2.ps2";
  std::fprintf(stderr, "[ios] disc %s\n[ios] card %s\n", disc.c_str(), card.c_str());

  std::vector<std::string> arguments = {"gt4vulkan-spec2", elf.string(), "--disc", disc.string(), "--memcard",
                                        card.string(), "--fullscreen"};
  // Unattended checks (ios/build.sh --check): stop after N frames and save every 300th frame into Documents/frames.
  if (const char *frames = std::getenv("GT4_IOS_CHECK_FRAMES"); frames && *frames) {
    std::filesystem::create_directories(documents / "frames");
    arguments.insert(arguments.end(), {"--frames", frames, "--frames-dir", (documents / "frames").string(),
                                       "--frame-every", "300"});
  }
  std::vector<char *> argv;
  for (std::string &argument : arguments)
    argv.push_back(argument.data());
  argv.push_back(nullptr);
  const int result = gt4_donor_main(static_cast<int>(arguments.size()), argv.data());
  std::fprintf(stderr, "[ios] game exited with %d\n", result);
  return result;
}
