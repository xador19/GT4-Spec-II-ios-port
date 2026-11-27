// iOS: an app cannot start the separate gt4-gs renderer process, so there is no remote picture to host. The game uses
// the built-in renderer; a GT4_RENDERER=pcsx2 request fails at the process start and reports it as on other platforms.
#include "gs_layer_host_mac.hpp"

namespace gt4::gs_stream {

bool host_presentation(SDL_Window *, std::uint64_t) { return false; }
void remove_presentation() {}

} // namespace gt4::gs_stream
