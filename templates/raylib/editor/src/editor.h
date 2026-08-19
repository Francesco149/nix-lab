// editor.h — cubeforge-raylib core header
#pragma once

#include <cstdint>
#include <cstddef>

struct lua_State;

// ── Lua VM ───────────────────────────────────────────────────────────────────
void lua_init(const char* root_dir);
void lua_frame();
void lua_shutdown();
lua_State* lua_state();

// ── ImGui bindings ───────────────────────────────────────────────────────────
void ig_register(lua_State* L);
void ig_clear_draw_lists();
void ig_balance_check();

// ── App ──────────────────────────────────────────────────────────────────────
void app_log(const char* fmt, ...);
