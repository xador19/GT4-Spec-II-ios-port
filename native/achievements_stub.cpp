// RetroAchievements are not part of this port (no online service is contacted). The calls the game windows make are
// no-ops, so a session behaves as with achievements turned off.
#include "achievements.hpp"

namespace gt4::achievements {

void initialize(HostWindow, const uint8_t *, size_t, const uint8_t *, size_t) {}
void on_vblank(HostWindow, const uint8_t *, size_t, const uint8_t *, size_t) {}
void on_window_pos_changed(HostWindow) {}
void reset_session() {}
void shutdown() {}
bool is_active() { return false; }

} // namespace gt4::achievements
