# iOS port: Gran Turismo 4 Spec II as an app for the player's own iPhone or iPad (ports/ios/README.md). Built by
# ports/ios/build.sh with the Xcode generator; the root CMakeLists.txt hands off here when CMAKE_SYSTEM_NAME is iOS.
#
# The same game as the macOS build (ports/macos/CMakeLists.txt, GT4_TARGET=spec2): the translated Spec II library, the
# donor runtime with the slice276 capsule (MTVU, GS stream hooks, the Spec II IOP reboot rule), the slice277 license
# guard and the VU1/VU0 AOT tables. Differences: MoltenVK is linked statically (no Vulkan loader), SDL3 is built from
# source, the built-in GS renderer is the only renderer (iOS apps cannot start the gt4-gs process), and RetroAchievements
# are left out (the app never contacts a server). No host-side controls are built here; they run in the macOS build.
enable_language(C OBJCXX)
set(CMAKE_OBJCXX_STANDARD 20)

set(GT4_NATIVE "${CMAKE_SOURCE_DIR}/native")
set(GT4_IOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(GT4_WARNINGS -Wall -Wextra)
add_compile_definitions(GT4_IOS GT4_TARGET_SPEC2)

set(GT4_IOS_CPU "apple-a20" CACHE STRING "-mcpu for every target (clang --print-supported-cpus)")
add_compile_options(-mcpu=${GT4_IOS_CPU})
set(GT4_IOS_BUNDLE_ID "com.example.gt4spec2" CACHE STRING "App identifier, unique to your team")

# Private inputs, generated on the Mac from the player's disc (ports/ios/build.sh). The same paths as the macOS build.
set(GT4_DONOR "${CMAKE_SOURCE_DIR}/private/references/ps2-web-recomp" CACHE PATH "MIT donor checkout (CRLF)")
set(GT4_IOS_PORT_DIR "${CMAKE_SOURCE_DIR}/private/macos-port" CACHE PATH "prepare_external_vulkan.py --gs-stream-hooks")
set(GT4_IOS_SHADER_DIR "${CMAKE_SOURCE_DIR}/private/macos-shaders" CACHE PATH "gt4-wgsl-spirv output")
set(GT4_IOS_RUNTIME_CAPSULE "${CMAKE_SOURCE_DIR}/private/spec2-runtime" CACHE PATH
    "prepare_perf_runtime.py --mtvu --gs-stream --frame-cost --spec2-iop")
set(GT4_IOS_LICENSE_GUARD "${CMAKE_SOURCE_DIR}/private/spec2-license-guard" CACHE PATH
    "prepare_license_guard.py --display-aspect --frame-counters")
set(GT4_IOS_VU_DIR "${CMAKE_SOURCE_DIR}/private/spec2-vu" CACHE PATH "ports/macos/spec2_vu_generate.py")
# The race HUD fits any screen ratio: the derived ELF with the HUD constants patched into loads from the HUD block
# (scripts/spec2_ios_hud_patch.py), translated with the same entry seeds.
set(GT4_IOS_EE_GENERATED "${CMAKE_SOURCE_DIR}/private/spec2-aspect-gen" CACHE PATH "Spec II translator output")
set(GT4_IOS_ELF "${CMAKE_SOURCE_DIR}/private/spec2-aspect-elf/SCUS_974.36" CACHE FILEPATH "Spec II aspect ELF")

# Every input is checked against the same pins as the macOS Spec II build.
function(gt4_require_pin file expected label)
    file(SHA256 "${file}" actual)
    if(NOT actual STREQUAL expected)
        message(FATAL_ERROR "${label} (${file}) differs from its pin; regenerate it with ports/ios/build.sh")
    endif()
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${file}")
endfunction()
file(READ "${CMAKE_SOURCE_DIR}/docs/inputs/spec2-aspect-elf.json" elf_pin)
string(JSON elf_sha GET "${elf_pin}" aspect sha256)
gt4_require_pin("${GT4_IOS_ELF}" "${elf_sha}" "Spec II aspect ELF")
file(READ "${CMAKE_SOURCE_DIR}/docs/inputs/slice191-gs-stream-runtime.json" port_pins)
foreach(port_file IN ITEMS gpu.cpp gpu.hpp gs.cpp)
    file(READ "${GT4_IOS_PORT_DIR}/${port_file}" port_text)
    string(REPLACE "\r\n" "\n" port_text "${port_text}")
    string(REPLACE "\n" "\r\n" port_text "${port_text}")
    string(SHA256 port_actual "${port_text}")
    string(JSON port_expected GET "${port_pins}" inputs PORT "${port_file}")
    if(NOT port_actual STREQUAL port_expected)
        message(FATAL_ERROR "${GT4_IOS_PORT_DIR}/${port_file} differs from the slice191 pin")
    endif()
endforeach()
set(gt4_shader_names upload copy_read copy_write load_clut display raster resolve snapshot decode)
set(gt4_shader_files)
foreach(shader IN LISTS gt4_shader_names)
    string(JSON shader_expected GET "${port_pins}" inputs SHADERS "${shader}.spv")
    gt4_require_pin("${GT4_IOS_SHADER_DIR}/${shader}.spv" "${shader_expected}" "Shader ${shader}")
    list(APPEND gt4_shader_files "${GT4_IOS_SHADER_DIR}/${shader}.spv")
endforeach()

# The in-app PCSX2 GS (gt4recomp-gs, branch ios: ports/ios/build_gs.sh builds it into build/ios-gs) and the static
# libraries it needs (ports/ios/build_gs_deps.sh, private/ios-gs-deps). SDL3 comes from there too, so the game window
# and the GS core share one SDL. MoltenVK's static library: ports/ios/fetch_deps.sh.
set(GT4_IOS_GS_BUILD "${CMAKE_SOURCE_DIR}/build/ios-gs" CACHE PATH "gt4recomp-gs iOS build (libgt4-gs.a and the core)")
set(GT4_IOS_GS_DEPS "${CMAKE_SOURCE_DIR}/private/ios-gs-deps" CACHE PATH "ports/ios/build_gs_deps.sh output")
set(GT4_IOS_GS_SOURCE "${CMAKE_SOURCE_DIR}/private/references/gt4recomp-gs" CACHE PATH "gt4recomp-gs checkout")
if(NOT EXISTS "${GT4_IOS_GS_BUILD}/pcsx2-gt4gs/libgt4-gs.a" OR NOT EXISTS "${GT4_IOS_GS_DEPS}/lib/libSDL3.a")
    message(FATAL_ERROR "The iOS GS is not built: run ports/ios/build_gs_deps.sh and ports/ios/build_gs.sh")
endif()
add_library(gt4_sdl3 INTERFACE)
target_include_directories(gt4_sdl3 INTERFACE "${GT4_IOS_GS_DEPS}/include")
target_link_libraries(gt4_sdl3 INTERFACE "${GT4_IOS_GS_DEPS}/lib/libSDL3.a"
    "-framework AVFoundation" "-framework AudioToolbox" "-framework CoreAudio" "-framework CoreBluetooth"
    "-framework CoreGraphics" "-framework CoreHaptics" "-framework CoreMotion" "-framework Foundation"
    "-framework GameController" "-framework Metal" "-framework QuartzCore" "-framework UIKit" "-framework OpenGLES"
    "-framework UniformTypeIdentifiers" "-framework CoreMedia" "-framework CoreVideo" "-framework IOSurface")
file(GLOB_RECURSE gt4_gs_libraries "${GT4_IOS_GS_BUILD}/*.a")
file(GLOB gt4_gs_dep_libraries "${GT4_IOS_GS_DEPS}/lib/*.a")
list(REMOVE_ITEM gt4_gs_dep_libraries "${GT4_IOS_GS_DEPS}/lib/libSDL3.a")
set(gt4_gs_metallib "${GT4_IOS_GS_BUILD}/metal-ios/Metal23.metallib")
set(GT4_MOLTENVK_DIR "${GT4_IOS_DIR}/deps/MoltenVK/MoltenVK" CACHE PATH "unpacked MoltenVK-ios.tar")
set(GT4_MOLTENVK_LIBRARY "${GT4_MOLTENVK_DIR}/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a")
if(NOT EXISTS "${GT4_MOLTENVK_LIBRARY}")
    message(FATAL_ERROR "MoltenVK for iOS not found in ${GT4_MOLTENVK_DIR}: run ports/ios/fetch_deps.sh")
endif()
add_library(gt4_moltenvk STATIC IMPORTED)
set_target_properties(gt4_moltenvk PROPERTIES IMPORTED_LOCATION "${GT4_MOLTENVK_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${GT4_MOLTENVK_DIR}/include")
target_link_libraries(gt4_moltenvk INTERFACE "-framework Metal" "-framework IOSurface" "-framework QuartzCore"
    "-framework UIKit" "-framework Foundation" "-framework CoreGraphics" c++)

# CoreGS 2.0, the project's own Vulkan GS renderer (native/hw_gs), on MoltenVK: GT4_RENDERER=hw with GT4_HW_CORE=2.
# native/hw_gs/CMakeLists.txt is the Windows build (MSVC flags, vulkan-1.lib, the Win32 HUD), so the sources are listed
# here; the Apple stand-ins replace the Windows-only HUD system readings and CPU sampler. Shaders: GLSL compiled by the
# host's glslangValidator into embedded SPIR-V, which MoltenVK turns into Metal when the pipelines are made.
set(GT4_HW_DIR "${GT4_NATIVE}/hw_gs")
set(GT4_HW_SHADERS_ONLY ON)
set(GT4_HW_GLSLANG_SHA256 "" CACHE STRING "SHA-256 of the host glslangValidator (set by ports/ios/build.sh)")
if(NOT GT4_HW_GLSLANG_SHA256)
    find_program(gt4_glslang_probe glslangValidator REQUIRED)
    file(SHA256 "${gt4_glslang_probe}" gt4_glslang_hash)
    set(GT4_HW_GLSLANG_SHA256 "${gt4_glslang_hash}" CACHE STRING "" FORCE)
endif()
add_subdirectory("${GT4_HW_DIR}/shaders" "${CMAKE_BINARY_DIR}/hw_gs_shaders")
add_library(gt4_coregs2 STATIC
    "${GT4_HW_DIR}/cpuref/cpuref_memory.cpp" "${GT4_HW_DIR}/cpuref/cpuref_draw.cpp" "${GT4_HW_DIR}/memory/hw_memory.cpp"
    "${GT4_HW_DIR}/clut/hw_clut.cpp" "${GT4_HW_DIR}/frontend/hw_gs_registers.cpp" "${GT4_HW_DIR}/frontend/hw_gif_parser.cpp"
    "${GT4_HW_DIR}/frontend/hw_transfers.cpp" "${GT4_HW_DIR}/frontend/hw_batch.cpp" "${GT4_HW_DIR}/frontend/hw_front_end.cpp"
    "${GT4_HW_DIR}/pixel/hw_gs_pixel.cpp" "${GT4_HW_DIR}/display/hw_gs_display.cpp"
    "${GT4_HW_DIR}/core2/core2_upload.cpp" "${GT4_HW_DIR}/core2/core2_depth_alias.cpp"
    "${GT4_HW_DIR}/writeback/hw_gs_writeback_gpu.cpp" "${GT4_HW_DIR}/writeback/hw_gs_vulkan_device_table.cpp"
    "${GT4_HW_DIR}/writeback/hw_gs_writeback.cpp" "${GT4_HW_DIR}/writeback/hw_gs_present_scheduler.cpp"
    "${GT4_HW_DIR}/core2/core2_renderer.cpp" "${GT4_HW_DIR}/core2/core2_gpu.cpp" "${GT4_HW_DIR}/core2/core2_replace.cpp"
    "${GT4_HW_DIR}/lod/hw_gs_lod.cpp"
    "${GT4_HW_DIR}/replace/src/gs_types.cpp" "${GT4_HW_DIR}/replace/src/xxh3.cpp" "${GT4_HW_DIR}/replace/src/xxh3_impl.cpp"
    "${GT4_HW_DIR}/replace/src/clut.cpp" "${GT4_HW_DIR}/replace/src/keys.cpp" "${GT4_HW_DIR}/replace/src/names.cpp"
    "${GT4_HW_DIR}/replace/src/packs.cpp" "${GT4_HW_DIR}/replace/src/images.cpp" "${GT4_HW_DIR}/replace/src/stb_image_impl.cpp"
    "${GT4_HW_DIR}/replace/tests/png_encode.cpp"
    "${GT4_HW_DIR}/hw_gs_options.cpp" "${GT4_HW_DIR}/hw_gs_vulkan_loader.cpp"
    "${GT4_HW_DIR}/hw_gs_backend.cpp" "${GT4_HW_DIR}/hw_gs_dispatch.cpp"
    "${GT4_HW_DIR}/hud/hw_hud.cpp" "${GT4_HW_DIR}/hud/hw_hud_layer.cpp" "${GT4_HW_DIR}/hud/hw_hud_system_apple.cpp"
    "${GT4_HW_DIR}/hw_gs_stream_sink.cpp" "${GT4_HW_DIR}/hw_gs_prepare.cpp" "${GT4_HW_DIR}/hw_cpu_sampler_apple.cpp")
target_include_directories(gt4_coregs2 PUBLIC
    "${GT4_HW_DIR}" "${GT4_HW_DIR}/cpuref" "${GT4_HW_DIR}/memory" "${GT4_HW_DIR}/clut" "${GT4_HW_DIR}/frontend"
    "${GT4_HW_DIR}/pixel" "${GT4_HW_DIR}/display" "${GT4_HW_DIR}/lod" "${GT4_HW_DIR}/replace/include"
    "${GT4_HW_DIR}/replace/tests" "${GT4_NATIVE}" "${GT4_NATIVE}/gs_stream")
target_include_directories(gt4_coregs2 PRIVATE "${GT4_HW_DIR}/replace/third_party")
target_link_libraries(gt4_coregs2 PUBLIC gt4_hw_shaders gt4_moltenvk)

# Host libraries (the subset of ports/macos/CMakeLists.txt the game links).
add_library(gt4_host STATIC
    "${GT4_NATIVE}/pacing.cpp" "${GT4_NATIVE}/window_mode.cpp" "${GT4_NATIVE}/race_display.cpp"
    "${GT4_NATIVE}/race_widescreen.cpp" "${GT4_NATIVE}/cursor_autohide.cpp" "${GT4_NATIVE}/display_aspect.cpp"
    "${GT4_NATIVE}/flare_limits.cpp" "${GT4_NATIVE}/vulkan_extensions.cpp" "${GT4_NATIVE}/install_paths.cpp"
    "${GT4_NATIVE}/license_guard.cpp" "${GT4_NATIVE}/perf_probe.cpp" "${GT4_NATIVE}/mtvu_measure.cpp"
    "${GT4_NATIVE}/mtvu_journal.cpp" "${GT4_NATIVE}/mtvu_runtime.cpp" "${GT4_NATIVE}/pad_mapping.cpp"
    "${GT4_NATIVE}/frame_clock.cpp" "${GT4_NATIVE}/host_io.cpp" "${GT4_NATIVE}/controls.cpp"
    "${GT4_NATIVE}/achievements_stub.cpp" "${GT4_NATIVE}/perf_clock.cpp" "${GT4_NATIVE}/pad_choice.cpp"
    "${GT4_NATIVE}/input_recording.cpp" "${GT4_NATIVE}/fov_adjust.cpp" "${GT4_NATIVE}/camera_360.cpp"
    "${GT4_NATIVE}/trigger_range.cpp"
    "${GT4_NATIVE}/gs_stream/gs_stream_ipc.cpp" "${GT4_NATIVE}/gs_stream/gs_stream_file.cpp"
    "${GT4_NATIVE}/gs_stream/gs_readback_probe.cpp" "${GT4_NATIVE}/gs_stream/gs_stream_client.cpp"
    "${GT4_NATIVE}/gs_stream/gs_layer_host_stub.cpp")
target_include_directories(gt4_host PUBLIC "${GT4_NATIVE}" "${GT4_NATIVE}/gs_stream")
target_compile_definitions(gt4_host PUBLIC GT4_PERF_PROBE GT4_PERF_VU_SPLIT GT4_VU1_AOT GT4_VU0_AOT)
target_link_libraries(gt4_host PUBLIC gt4_sdl3 gt4_coregs2)
# GT4_RENDERER=hw: the GS stream client hands every hook to CoreGS 2.0 in the app (native/hw_gs/hw_gs_stream_sink.cpp).
set_property(SOURCE "${GT4_NATIVE}/gs_stream/gs_stream_client.cpp" APPEND PROPERTY COMPILE_DEFINITIONS GT4_GS_STREAM_HW)

# Donor runtime with the Spec II capsule, the license guard and the VU tables (pins as in the macOS build).
set(runtime_files)
foreach(source IN ITEMS memory dispatch system kernel hw cop disc dmac vif vu_micro vu_jit vu_jit_web
                        ipu/ipu gs/gif gs/queue gs/raster iop/cpu iop/kernel iop/libs iop/hw iop/spu2 iop/sio2
                        iop/io iop/cdvd iop/sif iop/cdvdfsv)
    list(APPEND runtime_files "${GT4_DONOR}/runtime/src/${source}.cpp")
endforeach()
function(gt4_replace_runtime_source capsule source pin_json)
    string(JSON expected GET "${pin_json}" source_sha256 "${source}.cpp")
    gt4_require_pin("${capsule}/${source}.cpp" "${expected}" "Runtime source ${source}.cpp")
    # The donor file each capsule source replaces (kernel and hw also exist under iop/, which stay).
    set(donor_path "${source}")
    if(source STREQUAL "gif")
        set(donor_path "gs/gif")
    elseif(source STREQUAL "sif" OR source STREQUAL "cdvdfsv")
        set(donor_path "iop/${source}")
    endif()
    list(REMOVE_ITEM runtime_files "${GT4_DONOR}/runtime/src/${donor_path}.cpp")
    list(APPEND runtime_files "${capsule}/${source}.cpp")
    set(runtime_files "${runtime_files}" PARENT_SCOPE)
endfunction()
file(READ "${CMAKE_SOURCE_DIR}/docs/inputs/slice276-spec2-iop-runtime.json" runtime_pin)
foreach(source IN ITEMS system vif vu_micro gif memory hw dmac sif)
    gt4_replace_runtime_source("${GT4_IOS_RUNTIME_CAPSULE}" "${source}" "${runtime_pin}")
endforeach()
file(READ "${CMAKE_SOURCE_DIR}/docs/inputs/slice277-license-guard-runtime.json" guard_pin)
foreach(source IN ITEMS cdvdfsv dispatch kernel)
    gt4_replace_runtime_source("${GT4_IOS_LICENSE_GUARD}" "${source}" "${guard_pin}")
endforeach()
file(READ "${CMAKE_SOURCE_DIR}/docs/inputs/slice157-vu1-all.json" vu1_manifest)
string(JSON vu1_table_pin GET "${vu1_manifest}" vu1_aot generated_source_sha256)
gt4_require_pin("${GT4_IOS_VU_DIR}/vu1-gen/vu1_generated.cpp" "${vu1_table_pin}" "VU1 table")
file(READ "${GT4_IOS_VU_DIR}/summary.json" vu_summary)
string(JSON vu0_table_pin GET "${vu_summary}" vu0_table_sha256)
gt4_require_pin("${GT4_IOS_VU_DIR}/vu0-gen/vu0_generated.cpp" "${vu0_table_pin}" "Spec II VU0 table")
file(GLOB vu_generated_sources CONFIGURE_DEPENDS "${GT4_IOS_VU_DIR}/vu1-gen/vu1_generated*.cpp"
    "${GT4_IOS_VU_DIR}/vu0-gen/vu0_generated*.cpp")
set_source_files_properties(${vu_generated_sources} PROPERTIES COMPILE_OPTIONS "-Wno-unused-label")
# Xcode names object files by their base name, so iop/kernel.cpp and iop/hw.cpp would replace kernel.o and hw.o in one
# archive: the IOP sources get their own library.
set(iop_runtime_files ${runtime_files})
list(FILTER iop_runtime_files INCLUDE REGEX "/iop/|/(sif|cdvdfsv)\\.cpp$")
list(FILTER runtime_files EXCLUDE REGEX "/iop/|/(sif|cdvdfsv)\\.cpp$")
add_library(ps2runtime_iop STATIC ${iop_runtime_files})
add_library(ps2runtime_vulkan STATIC ${runtime_files} ${vu_generated_sources}
    "${CMAKE_SOURCE_DIR}/tools/vu_recomp/src/sha256.cpp" "${GT4_NATIVE}/mtvu_bridge.cpp"
    "${GT4_IOS_PORT_DIR}/gs.cpp" "${GT4_IOS_PORT_DIR}/gpu.cpp" "${GT4_NATIVE}/native_vulkan.cpp")
target_include_directories(ps2runtime_vulkan PUBLIC "${GT4_DONOR}/runtime/include" "${GT4_DONOR}/runtime/src"
    "${GT4_DONOR}/runtime/src/gs" "${GT4_IOS_PORT_DIR}" "${CMAKE_SOURCE_DIR}/tools/vu_recomp/src")
# An empty build-time shader folder: the shaders are bundle resources (install_paths.cpp, GT4_IOS).
target_compile_definitions(ps2runtime_vulkan PUBLIC PS2_GPU GT4_MTVU_RUNTIME GT4_VULKAN_SHADER_DIR="")
target_link_libraries(ps2runtime_vulkan PUBLIC gt4_host gt4_moltenvk ps2runtime_iop)
# The two libraries call each other; the IOP side shares the runtime's include folders and definitions.
target_include_directories(ps2runtime_iop PUBLIC "${GT4_DONOR}/runtime/include" "${GT4_DONOR}/runtime/src"
    "${GT4_DONOR}/runtime/src/gs" "${GT4_IOS_PORT_DIR}")
target_compile_definitions(ps2runtime_iop PUBLIC PS2_GPU GT4_MTVU_RUNTIME)
target_link_libraries(ps2runtime_iop PUBLIC gt4_host)
set_target_properties(ps2runtime_vulkan ps2runtime_iop PROPERTIES LINK_INTERFACE_MULTIPLICITY 3)

# The game window (SDL3) and the translated Spec II library.
add_library(gt4_window STATIC "${GT4_NATIVE}/window_sdl.cpp")
target_link_libraries(gt4_window PUBLIC ps2runtime_vulkan)
target_compile_definitions(gt4_window PRIVATE GT4_GS_STREAM_CLIENT GT4_MTVU_MEASURE)
file(GLOB generated_sources CONFIGURE_DEPENDS "${GT4_IOS_EE_GENERATED}/*.cpp")
if(NOT EXISTS "${GT4_IOS_EE_GENERATED}/table.cpp")
    message(FATAL_ERROR "No translated Spec II code in ${GT4_IOS_EE_GENERATED}: run ports/ios/build.sh")
endif()
add_library(ps2game STATIC ${generated_sources})
target_include_directories(ps2game PRIVATE "${GT4_IOS_EE_GENERATED}" "${GT4_DONOR}/runtime/include")
# TASK-134: the donor's runtime headers with exact faster forms of the soft float and the VU0 macro operations
# (scripts/prepare_fast_headers.py, which also provides ps2/fp4.hpp for the generated VU0 code). fp4.hpp computes the
# four lanes with SSE4.1 on x86 and lane by lane elsewhere, with the same bits as the donor either way.
find_program(GT4_IOS_PYTHON NAMES python3 PATHS "${CMAKE_SOURCE_DIR}/private/tooling-venv/bin" NO_DEFAULT_PATH)
if(NOT GT4_IOS_PYTHON)
    find_program(GT4_IOS_PYTHON python3 REQUIRED)
endif()
set(GT4_IOS_FAST_HEADERS "${CMAKE_BINARY_DIR}/fast_headers")
execute_process(COMMAND "${GT4_IOS_PYTHON}" -I "${CMAKE_SOURCE_DIR}/scripts/prepare_fast_headers.py" "${GT4_DONOR}"
                        "${GT4_IOS_FAST_HEADERS}" RESULT_VARIABLE gt4_fast_headers_result)
if(NOT gt4_fast_headers_result EQUAL 0)
    message(FATAL_ERROR "scripts/prepare_fast_headers.py failed")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/scripts/prepare_fast_headers.py"
                                                             "${GT4_NATIVE}/fp4.hpp")
target_include_directories(ps2runtime_vulkan BEFORE PUBLIC "${GT4_IOS_FAST_HEADERS}")
target_include_directories(ps2game BEFORE PRIVATE "${GT4_IOS_FAST_HEADERS}")
target_compile_options(ps2game PRIVATE -Wno-unused-label -Wno-unused-variable -Wno-unused-but-set-variable)

# The app. The pinned donor main.cpp keeps its source; `main` is renamed and ios_main.mm calls it.
set_source_files_properties("${GT4_IOS_PORT_DIR}/main.cpp" PROPERTIES
    COMPILE_DEFINITIONS "main=gt4_donor_main" COMPILE_OPTIONS "-include;${GT4_NATIVE}/posix_compat.hpp")
set(gt4_app_resources ${gt4_shader_files} "${GT4_IOS_ELF}" "${gt4_gs_metallib}")
file(GLOB gt4_icons "${GT4_IOS_DIR}/local-res/AppIcon*.png")
list(APPEND gt4_app_resources ${gt4_icons})
add_executable(gt4 MACOSX_BUNDLE "${GT4_IOS_PORT_DIR}/main.cpp" "${GT4_IOS_DIR}/ios_main.mm"
    "${GT4_IOS_DIR}/fps_overlay.mm" "${GT4_IOS_DIR}/gs_view.mm" "${GT4_IOS_DIR}/touch_controls.mm"
    "${GT4_IOS_DIR}/settings_screen.mm" ${gt4_app_resources})
set_source_files_properties("${GT4_IOS_DIR}/ios_main.mm" "${GT4_IOS_DIR}/fps_overlay.mm" "${GT4_IOS_DIR}/gs_view.mm"
    "${GT4_IOS_DIR}/touch_controls.mm" "${GT4_IOS_DIR}/settings_screen.mm"
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
target_compile_definitions(gt4 PRIVATE PS2_WINDOW)
target_link_libraries(gt4 PRIVATE ps2game gt4_window ${gt4_gs_libraries} ${gt4_gs_dep_libraries} z iconv)
# PCSX2's resources folder (GameIndex.yaml with the per-game GS fixes, fonts, shaders), without the Windows-only dx11
# shaders, at the bundle root as pcsx2/ (CocoaToolsIOS.mm GetResourcePath; a top-level "resources" folder makes
# codesign refuse the bundle).
add_custom_command(TARGET gt4 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${GT4_IOS_GS_SOURCE}/bin/resources" "$<TARGET_BUNDLE_DIR:gt4>/pcsx2"
    COMMAND ${CMAKE_COMMAND} -E remove_directory "$<TARGET_BUNDLE_DIR:gt4>/pcsx2/shaders/dx11")
set_target_properties(gt4 PROPERTIES
    OUTPUT_NAME gt4
    RESOURCE "${gt4_app_resources}"
    MACOSX_BUNDLE_INFO_PLIST "${GT4_IOS_DIR}/Info.plist.in"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${GT4_IOS_BUNDLE_ID}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${GT4_IOS_BUNDLE_ID}"
    XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${GT4_IOS_DIR}/gt4.entitlements"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_COMBINE_HIDPI_IMAGES NO
    XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING NO
    XCODE_GENERATE_SCHEME ON
    XCODE_SCHEME_LAUNCH_CONFIGURATION Release)
