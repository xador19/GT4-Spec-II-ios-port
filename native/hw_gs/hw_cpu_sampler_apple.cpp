// MIT License. Copyright (c) 2026 GT4Recomp contributors.
// iOS and macOS stand-in for hw_cpu_sampler.cpp, the Windows-only CPU survey sampler (GT4_CPU_SAMPLER, a diagnostic
// that is off by default): nothing is sampled.
#include "hw_cpu_sampler.hpp"

namespace gt4::hw::sampler {

void name_current_thread(const char *) {}
bool start_from_env() { return false; }
void note_vblank(std::uint64_t) {}
void finish(std::FILE *) {}

}  // namespace gt4::hw::sampler
