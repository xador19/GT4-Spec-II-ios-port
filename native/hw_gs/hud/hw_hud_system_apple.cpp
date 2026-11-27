// MIT License. Copyright (c) 2026 GT4Recomp contributors.
// iOS and macOS stand-in for hw_hud_system.cpp, which draws the performance HUD's font with GDI and reads the processor,
// graphics and memory figures from Windows. Here the HUD has no glyphs and no system figures ("--"), so asking for it
// (GT4_HW_HUD) shows nothing; the game and the renderer are unaffected. The app's own frame-rate counter stays.
#include "hw_hud_system.hpp"

namespace gt4::hw::hud {

GlyphAtlas make_glyph_atlas(int) { return {}; }

SystemSampler::SystemSampler(void *window, std::function<void(const SystemReading &)> publish)
    : window_(window), publish_(std::move(publish)) {}

SystemSampler::~SystemSampler() = default;

void SystemSampler::run() {}

}  // namespace gt4::hw::hud
