#pragma once
// RetroAchievements are not part of this port: it never contacts a server. The game windows still call these hooks
// (native/window.cpp, native/window_sdl.cpp); native/achievements_stub.cpp makes them no-ops.
#include <cstddef>
#include <cstdint>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
struct SDL_Window;
#endif

namespace gt4::achievements {

#ifdef _WIN32
using HostWindow = HWND;
#else
using HostWindow = SDL_Window *;
#endif

void initialize(HostWindow game_window, const uint8_t* ram, size_t ram_size, const uint8_t* spr, size_t spr_size);
void on_vblank(HostWindow game_window, const uint8_t* ram, size_t ram_size, const uint8_t* spr, size_t spr_size);
void on_window_pos_changed(HostWindow game_window);
void reset_session();
void shutdown();
bool is_active();

} // namespace gt4::achievements
