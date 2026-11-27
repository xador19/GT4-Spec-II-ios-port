// MIT License. Copyright (c) 2026 GT4Recomp contributors.
// iOS and macOS: the few MSVC runtime calls CoreGS 2.0 uses for paths, in POSIX terms.
#pragma once

#ifndef _WIN32
#include <cstdlib>
#include <filesystem>
#include <map>
#include <mutex>
#include <string>

// _wgetenv: the variable as a wide string (paths are UTF-8 here), kept alive for the process like getenv's result.
inline const wchar_t *gt4_hw_wgetenv(const wchar_t *name) {
  static std::mutex mutex;
  static std::map<std::wstring, std::wstring> values;
  const std::string narrow = std::filesystem::path(name).string();
  const char *value = std::getenv(narrow.c_str());
  if (!value) return nullptr;
  const std::lock_guard<std::mutex> lock(mutex);
  std::wstring &kept = values[name];
  kept = std::filesystem::path(value).wstring();
  return kept.c_str();
}
#define _wgetenv gt4_hw_wgetenv
#endif

#if !defined(_M_X64) && !defined(__x86_64__)
#include <chrono>
// __rdtsc on hosts without a TSC (ARM): a steady clock in nanoseconds. Callers only use differences and calibrate
// ticks against the steady clock, so any constant rate works.
inline unsigned long long gt4_hw_rdtsc() {
  return static_cast<unsigned long long>(std::chrono::steady_clock::now().time_since_epoch().count());
}
#define __rdtsc gt4_hw_rdtsc
#endif
