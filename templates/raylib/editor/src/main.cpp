// main.cpp — cubeforge-raylib entry point
// Raylib for windowing + 3D, rlImGui for ImGui overlay, Lua for all logic
//
// ─────────────────────────────────────────────────────────────────────────────
// CRITICAL ARCHITECTURE NOTE FOR C++ EDITING / MAIN LOOP CHANGES:
// Windows OpenGL 3.3 uses an in-loop Win32 window subclass (cf_resize_subclass_proc)
// to provide smooth continuous rendering during modal drag-resizing.
//
// BEFORE modifying render_frame_contents(), present_no_poll(), cf_resize_subclass_proc(),
// or the main loop, MUST read: docs/WINDOWS_OPENGL_RESIZE.md
//
// Key Invariants:
// 1. NEVER call EndDrawing() or glfwPollEvents() re-entrantly from wndproc.
// 2. Always CallWindowProcW(g_orig_proc) FIRST on WM_SIZE before re-rendering.
// 3. Maintain single-thread re-entrancy latch (g_in_subclass_render).
// 4. Time delta trap: raylib GetFrameTime() freezes on Windows because EndDrawing()
//    is skipped; use g_own_dt / update_own_dt() / rlImGuiBeginDelta(g_own_dt).
// 5. Exactly ONE input poll per frame (PollInputEvents on Win, EndDrawing on Linux).
// ─────────────────────────────────────────────────────────────────────────────
#include "editor.h"
#include "app_paths.h"
#include "editor_theme.h"
#include <cstdio>
#include <cstring>
#include <cmath>
#include <vector>
#ifdef _WIN32
// Win32 helpers live in src/winclip.c (windows.h clashes with raylib's
// Rectangle/ShowCursor/CloseWindow when included here).
extern "C" const char* win_clipboard_file_path(void);
extern "C" const char* win_clipboard_text(void);
extern "C" const char* win_open_file_dialog(void);
extern "C" void win_get_workarea(int* out_w, int* out_h);
// Manual Win32 imports for the resize subclass below (same clash rationale:
// windows.h's Rectangle/ShowCursor/CloseWindow macros clash with raylib).
extern "C" {
__declspec(dllimport) void*     __stdcall wglGetCurrentDC(void);
__declspec(dllimport) int       __stdcall SwapBuffers(void* hdc);
__declspec(dllimport) void*     __stdcall GetWindowLongPtrW(void* hwnd, int index);
__declspec(dllimport) long long __stdcall SetWindowLongPtrW(void* hwnd, int index, long long value);
__declspec(dllimport) long long __stdcall CallWindowProcW(long long proc, void* hwnd,
                                                          unsigned msg, unsigned long long wp, long long lp);
}
#endif
#include "raylib.h"
#include "raymath.h"
#include "rlgl.h"
#ifndef _WIN32
#include "vendor/tinyfiledialogs/tinyfiledialogs.h"  // native file picker (Linux only)
#endif
#include "imgui.h"
#include "rlImGui.h"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

// ── Raylib camera state exposed to Lua ──────────────────────────────────────
static Camera3D g_camera = {
    .position = { 5.0f, 5.0f, 5.0f },
    .target = { 0.0f, 0.0f, 0.0f },
    .up = { 0.0f, 1.0f, 0.0f },
    .fovy = 60.0f,
    .projection = CAMERA_PERSPECTIVE,
};

// ── 2D viewport camera (lp.cam2d.*) ─────────────────────────────────────────
// The 2D camera is the doctrine camera for 2D surfaces: pan by target, zoom
// anchored at the screen center. offset is refreshed to the screen center on
// every BeginMode2D / screen<->world conversion so window resizes stay exact.
static Camera2D g_cam2d = { { 0.0f, 0.0f }, { 0.0f, 0.0f }, 0.0f, 1.0f };

static void cam2d_refresh_offset() {
    g_cam2d.offset = { GetScreenWidth() * 0.5f, GetScreenHeight() * 0.5f };
    g_cam2d.rotation = 0.0f;
}

// ── Raylib Lua bindings (lp.rl.*) ───────────────────────────────────────────

static int l_rl_draw_cube(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float z = (float)luaL_checknumber(L, 3);
    float w = (float)luaL_checknumber(L, 4);
    float h = (float)luaL_checknumber(L, 5);
    float d = (float)luaL_checknumber(L, 6);
    int r = (int)luaL_optinteger(L, 7, 100);
    int g = (int)luaL_optinteger(L, 8, 150);
    int b = (int)luaL_optinteger(L, 9, 200);
    int a = (int)luaL_optinteger(L, 10, 255);
    DrawCube({ x, y, z }, w, h, d, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_draw_cube_wires(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float z = (float)luaL_checknumber(L, 3);
    float w = (float)luaL_checknumber(L, 4);
    float h = (float)luaL_checknumber(L, 5);
    float d = (float)luaL_checknumber(L, 6);
    int r = (int)luaL_optinteger(L, 7, 40);
    int g = (int)luaL_optinteger(L, 8, 50);
    int b = (int)luaL_optinteger(L, 9, 70);
    int a = (int)luaL_optinteger(L, 10, 255);
    DrawCubeWires({ x, y, z }, w, h, d, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_draw_grid(lua_State* L) {
    int slices = (int)luaL_checkinteger(L, 1);
    float spacing = (float)luaL_checknumber(L, 2);
    DrawGrid(slices, spacing);
    return 0;
}

static int l_rl_set_camera(lua_State* L) {
    g_camera.position = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    g_camera.target = { (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) };
    g_camera.fovy = (float)luaL_optnumber(L, 7, 60.0);
    return 0;
}

static int l_rl_get_camera(lua_State* L) {
    lua_newtable(L);
    lua_pushnumber(L, g_camera.position.x); lua_setfield(L, -2, "eye_x");
    lua_pushnumber(L, g_camera.position.y); lua_setfield(L, -2, "eye_y");
    lua_pushnumber(L, g_camera.position.z); lua_setfield(L, -2, "eye_z");
    lua_pushnumber(L, g_camera.target.x); lua_setfield(L, -2, "target_x");
    lua_pushnumber(L, g_camera.target.y); lua_setfield(L, -2, "target_y");
    lua_pushnumber(L, g_camera.target.z); lua_setfield(L, -2, "target_z");
    lua_pushnumber(L, g_camera.fovy); lua_setfield(L, -2, "fov");
    return 1;
}

static int l_rl_get_ray(lua_State* L) {
    float mx = (float)luaL_checknumber(L, 1);
    float my = (float)luaL_checknumber(L, 2);
    Ray ray = GetScreenToWorldRay({ mx, my }, g_camera);
    lua_pushnumber(L, ray.position.x);
    lua_pushnumber(L, ray.position.y);
    lua_pushnumber(L, ray.position.z);
    lua_pushnumber(L, ray.direction.x);
    lua_pushnumber(L, ray.direction.y);
    lua_pushnumber(L, ray.direction.z);
    return 6;
}

static int l_rl_draw_line_3d(lua_State* L) {
    Vector3 a = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    Vector3 b = { (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) };
    int r = (int)luaL_optinteger(L, 7, 200);
    int g = (int)luaL_optinteger(L, 8, 200);
    int bi = (int)luaL_optinteger(L, 9, 200);
    int ai = (int)luaL_optinteger(L, 10, 255);
    DrawLine3D(a, b, { (unsigned char)r, (unsigned char)g, (unsigned char)bi, (unsigned char)ai });
    return 0;
}

static int l_rl_draw_sphere(lua_State* L) {
    Vector3 pos = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    float radius = (float)luaL_checknumber(L, 4);
    int r = (int)luaL_optinteger(L, 5, 200);
    int g = (int)luaL_optinteger(L, 6, 100);
    int b = (int)luaL_optinteger(L, 7, 50);
    int a = (int)luaL_optinteger(L, 8, 255);
    DrawSphere(pos, radius, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}
static int l_rl_draw_sphere_wires(lua_State* L) {
    Vector3 pos = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    float radius = (float)luaL_checknumber(L, 4);
    int rings = (int)luaL_optinteger(L, 5, 12);
    int slices = (int)luaL_optinteger(L, 6, 12);
    int r = (int)luaL_optinteger(L, 7, 240);
    int g = (int)luaL_optinteger(L, 8, 120);
    int b = (int)luaL_optinteger(L, 9, 50);
    int a = (int)luaL_optinteger(L, 10, 255);
    DrawSphereWires(pos, radius, rings, slices, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}
static int l_rl_draw_triangle_3d(lua_State* L) {
    Vector3 a = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    Vector3 b = { (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) };
    Vector3 c = { (float)luaL_checknumber(L, 7), (float)luaL_checknumber(L, 8), (float)luaL_checknumber(L, 9) };
    int r = (int)luaL_optinteger(L, 10, 200);
    int g = (int)luaL_optinteger(L, 11, 200);
    int bi = (int)luaL_optinteger(L, 12, 200);
    int ai = (int)luaL_optinteger(L, 13, 255);
    DrawTriangle3D(a, b, c, { (unsigned char)r, (unsigned char)g, (unsigned char)bi, (unsigned char)ai });
    return 0;
}

static int l_rl_draw_cylinder(lua_State* L) {
    Vector3 pos = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    float rTop = (float)luaL_checknumber(L, 4);
    float rBot = (float)luaL_checknumber(L, 5);
    float h = (float)luaL_checknumber(L, 6);
    int slices = (int)luaL_optinteger(L, 7, 16);
    int r = (int)luaL_optinteger(L, 8, 100);
    int g = (int)luaL_optinteger(L, 9, 150);
    int b = (int)luaL_optinteger(L, 10, 200);
    int a = (int)luaL_optinteger(L, 11, 255);
    DrawCylinder(pos, rTop, rBot, h, slices, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_draw_cylinder_wires(lua_State* L) {
    Vector3 pos = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    float rTop = (float)luaL_checknumber(L, 4);
    float rBot = (float)luaL_checknumber(L, 5);
    float h = (float)luaL_checknumber(L, 6);
    int slices = (int)luaL_optinteger(L, 7, 16);
    int r = (int)luaL_optinteger(L, 8, 40);
    int g = (int)luaL_optinteger(L, 9, 50);
    int b = (int)luaL_optinteger(L, 10, 70);
    int a = (int)luaL_optinteger(L, 11, 255);
    DrawCylinderWires(pos, rTop, rBot, h, slices, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_world_to_screen(lua_State* L) {
    // 2 args = 2D world point (uses the current 2D camera); 3 args = 3D point.
    if (lua_gettop(L) == 2) {
        cam2d_refresh_offset();
        Vector2 s = GetWorldToScreen2D({ (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2) }, g_cam2d);
        lua_pushnumber(L, s.x);
        lua_pushnumber(L, s.y);
        return 2;
    }
    Vector3 pos = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    Vector2 s = GetWorldToScreen(pos, g_camera);
    lua_pushnumber(L, s.x);
    lua_pushnumber(L, s.y);
    return 2;
}

// ── Headless input drive — STATE (declared before the input getters) ───────
// When drive mode is active, ALL lp.rl input getters return the injected
// state instead of real input. Enables frame-accurate headless tests with no
// window focus, no xdotool, no synthetic OS events. The Lua drive.lua module
// schedules injections per frame; C++ just stores/overrides.
static bool  g_drive_active = false;
static float g_drive_mx = 0, g_drive_my = 0;
static float g_drive_px = 0, g_drive_py = 0;   // previous-frame pos (for delta)
static bool  g_drive_btn[3] = {};
static bool  g_drive_btn_pressed[3] = {};
static float g_drive_wheel = 0;
static bool  g_drive_key_down[512] = {};
static bool  g_drive_key_pressed[512] = {};

static inline bool drive_overrides() { return g_drive_active; }

static int l_rl_is_mouse_button_down(lua_State* L) {
    int btn = (int)luaL_checkinteger(L, 1);
    if (drive_overrides()) { lua_pushboolean(L, btn >= 0 && btn <= 2 && g_drive_btn[btn]); return 1; }
    lua_pushboolean(L, IsMouseButtonDown(btn));
    return 1;
}

static int l_rl_is_mouse_button_pressed(lua_State* L) {
    int btn = (int)luaL_checkinteger(L, 1);
    if (drive_overrides()) { lua_pushboolean(L, btn >= 0 && btn <= 2 && g_drive_btn_pressed[btn]); return 1; }
    lua_pushboolean(L, IsMouseButtonPressed(btn));
    return 1;
}

static int l_rl_get_mouse_delta(lua_State* L) {
    if (drive_overrides()) {
        lua_pushnumber(L, g_drive_mx - g_drive_px);
        lua_pushnumber(L, g_drive_my - g_drive_py);
        return 2;
    }
    Vector2 d = GetMouseDelta();
    lua_pushnumber(L, d.x);
    lua_pushnumber(L, d.y);
    return 2;
}

static int l_rl_get_mouse_wheel(lua_State* L) {
    if (drive_overrides()) { lua_pushnumber(L, g_drive_wheel); return 1; }
    lua_pushnumber(L, GetMouseWheelMove());
    return 1;
}

static int l_rl_get_mouse_pos(lua_State* L) {
    if (drive_overrides()) {
        lua_pushnumber(L, g_drive_mx);
        lua_pushnumber(L, g_drive_my);
        return 2;
    }
    Vector2 p = GetMousePosition();
    lua_pushnumber(L, p.x);
    lua_pushnumber(L, p.y);
    return 2;
}

static int l_rl_is_key_pressed(lua_State* L) {
    int code = (int)luaL_checkinteger(L, 1);
    if (drive_overrides()) { lua_pushboolean(L, code >= 0 && code < 512 && g_drive_key_pressed[code]); return 1; }
    lua_pushboolean(L, IsKeyPressed(code));
    return 1;
}

static int l_rl_is_key_down(lua_State* L) {
    int code = (int)luaL_checkinteger(L, 1);
    if (drive_overrides()) { lua_pushboolean(L, code >= 0 && code < 512 && g_drive_key_down[code]); return 1; }
    lua_pushboolean(L, IsKeyDown(code));
    return 1;
}
// Own delta time, independent of raylib's EndDrawing (which is skipped on
// Windows in favor of the no-poll present; CORE.Time.frame only advances
// inside EndDrawing, so GetFrameTime() would freeze there). GetTime() is the
// monotonic clock and always advances. Updated once per render_frame_contents.
static float g_own_dt = 1.0f / 60.0f;
static double g_own_dt_prev = -1.0;
static void update_own_dt() {
    double now = GetTime();
    if (g_own_dt_prev < 0.0) g_own_dt_prev = now;
    double dt = now - g_own_dt_prev;
    g_own_dt_prev = now;
    if (dt < 0.0) dt = 0.0;
    if (dt > 0.25) dt = 0.25;   // clamp stalls (breakpoints, modal dialogs)
    g_own_dt = (float)dt;
}

static int l_rl_get_frame_time(lua_State* L) {
    lua_pushnumber(L, g_own_dt);
    return 1;
}

static int l_rl_get_screen_size(lua_State* L) {
    lua_pushinteger(L, GetScreenWidth());
    lua_pushinteger(L, GetScreenHeight());
    return 2;
}
static bool g_lighting_enabled = false;
static int l_rl_set_lighting_enabled(lua_State* L) {
    g_lighting_enabled = lua_toboolean(L, 1);
    return 0;
}
static int l_rl_is_lighting_enabled(lua_State* L) {
    lua_pushboolean(L, g_lighting_enabled);
    return 1;
}

static int l_rl_take_screenshot(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    TakeScreenshot(path);
    char dup[2048];
    snprintf(dup, sizeof(dup), "screenshot%03d.png", 0);
    if (strcmp(dup, path) != 0 && FileExists(dup)) remove(dup);
    return 0;
}


static int l_rl_set_window_size(lua_State* L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    if (w > 0 && h > 0) SetWindowSize(w, h);
    return 0;
}
static int l_rl_set_target_fps(lua_State* L) {
    int fps = (int)luaL_checkinteger(L, 1);
    SetTargetFPS(fps);
    return 0;
}

static int l_rl_get_target_fps(lua_State* L) {
    lua_pushinteger(L, GetFPS());
    return 1;
}

static int l_rl_get_monitor_refresh_rate(lua_State* L) {
    int mon = (int)luaL_optinteger(L, 1, GetCurrentMonitor());
    int hz = GetMonitorRefreshRate(mon);
    lua_pushinteger(L, hz > 0 ? hz : 60);
    return 1;
}


static int l_rl_get_monitor_size(lua_State* L) {
    int mon = (int)luaL_optinteger(L, 1, GetCurrentMonitor());
    int w = GetMonitorWidth(mon);
    int h = GetMonitorHeight(mon);
    lua_pushinteger(L, w);
    lua_pushinteger(L, h);
    return 2;
}

static int l_rl_set_window_position(lua_State* L) {
    int x = (int)luaL_checkinteger(L, 1);
    int y = (int)luaL_checkinteger(L, 2);
    SetWindowPosition(x, y);
    return 0;
}

static int l_rl_get_window_position(lua_State* L) {
    Vector2 p = GetWindowPosition();
    lua_pushinteger(L, (int)p.x);
    lua_pushinteger(L, (int)p.y);
    return 2;
}

// lp.rl.set_mouse_cursor(type) — hover affordance for draggable regions.
// Use lp.rl.CURSOR_* constants (raylib MouseCursor enum).
static int l_rl_set_mouse_cursor(lua_State* L) {
    int type = (int)luaL_optinteger(L, 1, 0);
    if (type < 0 || type > 8) type = 0;
    SetMouseCursor((MouseCursor)type);
    return 0;
}

// ── Complex 3D: models / textures / shaders ────────────────────────────────
// Resources live in C++ registries; Lua holds integer ids. This keeps the
// raylib structs (Model, Texture2D, Shader) opaque to Lua while exposing the
// full 3D surface — the core of the "complex 3D from Lua" hypothesis.

static std::vector<Model>   g_models;
static std::vector<Texture2D> g_texs;
static std::vector<Shader>  g_shaders;

// Standard raylib default vertex shader (GLSL 330). raylib 6.0 removed the
// DEFAULT_VERTEX_SHADER extern, so we embed the canonical text (matches rlgl.c).
static const char* DEFAULT_VS = R"GLSL(
#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
uniform mat4 mvp;
out vec2 fragTexCoord;
out vec4 fragColor;
void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    gl_Position = mvp*vec4(vertexPosition, 1.0);
}
)GLSL";

static const char* LIGHTING_VS = R"GLSL(
#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
in vec3 vertexNormal;
uniform mat4 mvp;
uniform mat4 matModel;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragNormal;
void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    fragNormal = normalize((matModel * vec4(vertexNormal, 0.0)).xyz);
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
)GLSL";

static const char* LIGHTING_FS = R"GLSL(
#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
out vec4 finalColor;
void main() {
    vec4 texelColor = texture(texture0, fragTexCoord);
    vec3 n = length(fragNormal) > 0.01 ? normalize(fragNormal) : vec3(0.0, 1.0, 0.0);
    vec3 l = normalize(vec3(0.5, 0.8, 0.6));
    float diff = max(0.0, dot(n, l));
    vec3 lighting = vec3(0.40) + vec3(0.60) * diff;
    finalColor = vec4((fragColor * colDiffuse * texelColor).rgb * min(lighting, vec3(1.0)), 1.0);
}
)GLSL";

static int l_rl_load_model_cube(lua_State* L) {
    float w = (float)luaL_checknumber(L, 1);
    float h = (float)luaL_checknumber(L, 2);
    float d = (float)luaL_checknumber(L, 3);
    g_models.push_back(LoadModelFromMesh(GenMeshCube(w, h, d)));
    lua_pushinteger(L, (lua_Integer)g_models.size() - 1);
    return 1;
}
static int l_rl_load_model_cylinder(lua_State* L) {
    float radius = (float)luaL_checknumber(L, 1);
    float height = (float)luaL_checknumber(L, 2);
    int slices = (int)luaL_optinteger(L, 3, 16);
    g_models.push_back(LoadModelFromMesh(GenMeshCylinder(radius, height, slices)));
    lua_pushinteger(L, (lua_Integer)g_models.size() - 1);
    return 1;
}

static int l_rl_load_texture_perlin(lua_State* L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    float scale = (float)luaL_optnumber(L, 3, 1.0f);
    Image img = GenImagePerlinNoise(w, h, 0, 0, scale);
    g_texs.push_back(LoadTextureFromImage(img));
    UnloadImage(img);
    lua_pushinteger(L, (lua_Integer)g_texs.size() - 1);
    return 1;
}

static int l_rl_load_shader(lua_State* L) {
    // rl.load_shader(vs_or_nil, fs) — nil vs uses the embedded default vertex shader
    const char* fs = luaL_checkstring(L, 2);
    const char* vs = lua_isnoneornil(L, 1) ? DEFAULT_VS : luaL_checkstring(L, 1);
    g_shaders.push_back(LoadShaderFromMemory(vs, fs));
    lua_pushinteger(L, (lua_Integer)g_shaders.size() - 1);
    return 1;
}

static int l_rl_set_material_texture(lua_State* L) {
    int mid = (int)luaL_checkinteger(L, 1);
    int map = (int)luaL_checkinteger(L, 2);
    int tid = (int)luaL_checkinteger(L, 3);
    if (mid < 0 || mid >= (int)g_models.size() || tid < 0 || tid >= (int)g_texs.size())
        return luaL_error(L, "set_material_texture: bad id (model %d tex %d)", mid, tid);
    SetMaterialTexture(&g_models[mid].materials[0], map, g_texs[tid]);
    return 0;
}

static int l_rl_set_material_shader(lua_State* L) {
    int mid = (int)luaL_checkinteger(L, 1);
    int sid = (int)luaL_checkinteger(L, 2);
    if (mid < 0 || mid >= (int)g_models.size() || sid < 0 || sid >= (int)g_shaders.size())
        return luaL_error(L, "set_material_shader: bad id (model %d shader %d)", mid, sid);
    g_models[mid].materials[0].shader = g_shaders[sid];
    return 0;
}

static int l_rl_set_material_color(lua_State* L) {
    int mid = (int)luaL_checkinteger(L, 1);
    int map = (int)luaL_checkinteger(L, 2);
    int r = (int)luaL_optinteger(L, 3, 255);
    int g = (int)luaL_optinteger(L, 4, 255);
    int b = (int)luaL_optinteger(L, 5, 255);
    int a = (int)luaL_optinteger(L, 6, 255);
    if (mid < 0 || mid >= (int)g_models.size())
        return luaL_error(L, "set_material_color: bad model id %d", mid);
    // raylib 6.0 removed SetMaterialColor; the map color is a plain field.
    g_models[mid].materials[0].maps[map].color = { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a };
    return 0;
}

static int l_rl_get_shader_location(lua_State* L) {
    int sid = (int)luaL_checkinteger(L, 1);
    const char* name = luaL_checkstring(L, 2);
    if (sid < 0 || sid >= (int)g_shaders.size())
        return luaL_error(L, "get_shader_location: bad shader id %d", sid);
    lua_pushinteger(L, GetShaderLocation(g_shaders[sid], name));
    return 1;
}

static int l_rl_set_shader_value_vec3(lua_State* L) {
    int sid = (int)luaL_checkinteger(L, 1);
    int loc = (int)luaL_checkinteger(L, 2);
    float v[3] = { (float)luaL_checknumber(L, 3), (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5) };
    if (sid < 0 || sid >= (int)g_shaders.size())
        return luaL_error(L, "set_shader_value_vec3: bad shader id %d", sid);
    SetShaderValue(g_shaders[sid], loc, v, SHADER_UNIFORM_VEC3);
    return 0;
}

static int l_rl_set_shader_value_float(lua_State* L) {
    int sid = (int)luaL_checkinteger(L, 1);
    int loc = (int)luaL_checkinteger(L, 2);
    float v = (float)luaL_checknumber(L, 3);
    if (sid < 0 || sid >= (int)g_shaders.size())
        return luaL_error(L, "set_shader_value_float: bad shader id %d", sid);
    SetShaderValue(g_shaders[sid], loc, &v, SHADER_UNIFORM_FLOAT);
    return 0;
}
static int l_rl_draw_model(lua_State* L) {
    int mid = (int)luaL_checkinteger(L, 1);
    Vector3 pos = { (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3), (float)luaL_checknumber(L, 4) };
    float scale = (float)luaL_optnumber(L, 5, 1.0f);
    int r = (int)luaL_optinteger(L, 6, 255);
    int g = (int)luaL_optinteger(L, 7, 255);
    int b = (int)luaL_optinteger(L, 8, 255);
    int a = (int)luaL_optinteger(L, 9, 255);
    if (mid < 0 || mid >= (int)g_models.size())
        return luaL_error(L, "draw_model: bad model id %d", mid);

    static Shader s_lighting_shader = {};
    static Shader s_default_shader = {};
    static bool s_shader_inited = false;
    if (!s_shader_inited) {
        s_default_shader = g_models[mid].materials[0].shader;
        s_lighting_shader = LoadShaderFromMemory(LIGHTING_VS, LIGHTING_FS);
        s_shader_inited = true;
    }

    if (g_lighting_enabled && s_lighting_shader.id > 0) {
        g_models[mid].materials[0].shader = s_lighting_shader;
    } else {
        g_models[mid].materials[0].shader = s_default_shader;
    }
    DrawModel(g_models[mid], pos, scale, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_draw_model_wires(lua_State* L) {
    int mid = (int)luaL_checkinteger(L, 1);
    Vector3 pos = { (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3), (float)luaL_checknumber(L, 4) };
    float scale = (float)luaL_optnumber(L, 5, 1.0f);
    int r = (int)luaL_optinteger(L, 6, 255);
    int g = (int)luaL_optinteger(L, 7, 255);
    int b = (int)luaL_optinteger(L, 8, 255);
    int a = (int)luaL_optinteger(L, 9, 255);
    if (mid < 0 || mid >= (int)g_models.size())
        return luaL_error(L, "draw_model_wires: bad model id %d", mid);
    DrawModelWires(g_models[mid], pos, scale, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_load_model_mesh(lua_State* L) {
    // lp.rl.load_model_mesh(verts, indices) -> model_id
    // verts:   flat {x,y,z, r,g,b,a, nx,ny,nz, u,v} per vertex (12 floats)
    // indices: flat triangle indices (0-based)
    // Builds a raylib Model from arbitrary geometry so EDITED meshes keep
    // material textures (canvas/perlin) — not just pristine primitives.
    size_t vn = lua_rawlen(L, 1);
    size_t in = lua_rawlen(L, 2);
    if (vn % 12 != 0) return luaL_error(L, "load_model_mesh: verts must be 12 floats/vertex (pos3+color4+normal3+uv2), got %d", (int)vn);
    if (in % 3 != 0) return luaL_error(L, "load_model_mesh: indices must be triangles, got %d", (int)in);
    int vcount = (int)(vn / 12);
    int icount = (int)in;

    Mesh m = {};
    m.vertexCount = vcount;
    m.triangleCount = icount / 3;
    m.vertices = (float*)RL_MALLOC(vcount * 3 * sizeof(float));
    m.colors = (unsigned char*)RL_MALLOC(vcount * 4 * sizeof(unsigned char));
    m.normals = (float*)RL_MALLOC(vcount * 3 * sizeof(float));
    m.texcoords = (float*)RL_MALLOC(vcount * 2 * sizeof(float));
    m.indices = (unsigned short*)RL_MALLOC(icount * sizeof(unsigned short));

    for (int i = 0; i < vcount; i++) {
        size_t base = 1 + (size_t)i * 12;
        lua_rawgeti(L, 1, (lua_Integer)base + 0);
        lua_rawgeti(L, 1, (lua_Integer)base + 1);
        lua_rawgeti(L, 1, (lua_Integer)base + 2);
        m.vertices[i * 3 + 0] = (float)lua_tonumber(L, -3);
        m.vertices[i * 3 + 1] = (float)lua_tonumber(L, -2);
        m.vertices[i * 3 + 2] = (float)lua_tonumber(L, -1);
        lua_pop(L, 3);
        for (int c = 0; c < 4; c++) {
            lua_rawgeti(L, 1, (lua_Integer)base + 3 + c);
            m.colors[i * 4 + c] = (unsigned char)lua_tointeger(L, -1);
            lua_pop(L, 1);
        }
        for (int n = 0; n < 3; n++) {
            lua_rawgeti(L, 1, (lua_Integer)base + 7 + n);
            m.normals[i * 3 + n] = (float)lua_tonumber(L, -1);
            lua_pop(L, 1);
        }
        for (int t = 0; t < 2; t++) {
            lua_rawgeti(L, 1, (lua_Integer)base + 10 + t);
            m.texcoords[i * 2 + t] = (float)lua_tonumber(L, -1);
            lua_pop(L, 1);
        }
    }
    for (int i = 0; i < icount; i++) {
        lua_rawgeti(L, 2, (lua_Integer)i + 1);
        m.indices[i] = (unsigned short)lua_tointeger(L, -1);
        lua_pop(L, 1);
    }

    // Same as raylib's GenMesh*: UploadMesh puts the data on the GPU and the
    // CPU arrays stay owned by the returned Model (LoadModelFromMesh takes
    // ownership; UnloadModel frees both). Do NOT RL_FREE here.
    UploadMesh(&m, false);
    g_models.push_back(LoadModelFromMesh(m));
    lua_pushinteger(L, (lua_Integer)g_models.size() - 1);
    return 1;
}

static int l_rl_debug_material(lua_State* L) {
    int mid = (int)luaL_checkinteger(L, 1);
    if (mid < 0 || mid >= (int)g_models.size())
        return luaL_error(L, "debug_material: bad model id %d", mid);
    Model& mdl = g_models[mid];
    if (mdl.materialCount == 0 || mdl.materials == nullptr) {
        lua_pushstring(L, "NO_MATERIAL");
        return 1;
    }
    int tex = mdl.materials[0].maps[MATERIAL_MAP_ALBEDO].texture.id;
    lua_pushstring(L, tex > 0 ? "TEXTURE_BOUND" : "TEXTURE_EMPTY");
    lua_pushinteger(L, tex);
    return 2;
}

// lp.rl.clipboard_file_path() -> path or nil
// Windows: prefers CF_HDROP (files copied in Explorer) via DragQueryFile —
// this AVOIDS GLFW's "Failed to convert clipboard to string" error when the
// clipboard holds files or is empty. Falls back to clipboard text ONLY when a
// text format is actually present. Linux/macOS: raylib GetClipboardText
// (uri-list arrives as text; file:// prefixes are stripped in Lua).
static int l_rl_clipboard_file_path(lua_State* L) {
#ifdef _WIN32
    // CF_HDROP-aware (src/winclip.c): files copied in Explorer paste cleanly,
    // and GLFW's "Failed to convert clipboard to string" error never fires
    // (that happens when the clipboard holds files or is empty).
    const char* p = win_clipboard_file_path();
    if (p && *p) { lua_pushstring(L, p); return 1; }
    const char* t = win_clipboard_text();
    if (t && *t) { lua_pushstring(L, t); return 1; }
    lua_pushnil(L);
    return 1;
#else
    const char* t = GetClipboardText();
    if (t && *t) { lua_pushstring(L, t); return 1; }
    lua_pushnil(L);
    return 1;
#endif
}

// lp.rl.get_clipboard_text() — copy immediately (raylib owns the buffer).
static int l_rl_get_clipboard_text(lua_State* L) {
    const char* t = GetClipboardText();
    if (t && *t) { lua_pushstring(L, t); return 1; }
    lua_pushnil(L);
    return 1;
}

// lp.rl.is_file_dropped() / take_dropped_file() -> path or nil (takes the
// FIRST dropped file; the caller owns nothing — we copy + unload the list).
static int l_rl_is_file_dropped(lua_State* L) {
    lua_pushboolean(L, IsFileDropped());
    return 1;
}
static int l_rl_take_dropped_file(lua_State* L) {
    if (!IsFileDropped()) { lua_pushnil(L); return 1; }
    FilePathList files = LoadDroppedFiles();
    if (files.count > 0 && files.paths && files.paths[0] && *files.paths[0]) {
        lua_pushstring(L, files.paths[0]);
        UnloadDroppedFiles(files);
        return 1;
    }
    UnloadDroppedFiles(files);
    lua_pushnil(L);
    return 1;
}

// lp.app.open_file_dialog() -> path or nil — native file picker.
// Windows: direct Win32 GetOpenFileNameW (winclip.c), always reliable.
// Linux: tinyfiledialogs (zenity/kdialog).
static int l_app_open_file_dialog(lua_State* L) {
    const char* path = nullptr;
#ifdef _WIN32
    path = win_open_file_dialog();
#else
    path = tinyfd_openFileDialog(
        "Open Texture (png/jpg/bmp/tga/gif/qoi)",
        "",
        8,
        (const char* const[]){"*.png", "*.jpg", "*.jpeg", "*.bmp", "*.tga", "*.gif", "*.qoi", "*.ico"},
        "Image files",
        0);
#endif
    if (path && *path) { lua_pushstring(L, path); return 1; }
    lua_pushnil(L);
    return 1;
}

static int l_rl_unload_model(lua_State* L) {
    int mid = (int)luaL_checkinteger(L, 1);
    if (mid < 0 || mid >= (int)g_models.size())
        return luaL_error(L, "unload_model: bad model id %d", mid);
    UnloadModel(g_models[mid]);
    g_models[mid] = {};
    return 0;
}

static int l_rl_unload_texture(lua_State* L) {
    int tid = (int)luaL_checkinteger(L, 1);
    if (tid < 0 || tid >= (int)g_texs.size())
        return luaL_error(L, "unload_texture: bad texture id %d", tid);
    UnloadTexture(g_texs[tid]);
    g_texs[tid] = {};
    return 0;
}

static int l_rl_unload_shader(lua_State* L) {
    int sid = (int)luaL_checkinteger(L, 1);
    if (sid < 0 || sid >= (int)g_shaders.size())
        return luaL_error(L, "unload_shader: bad shader id %d", sid);
    UnloadShader(g_shaders[sid]);
    g_shaders[sid] = {};
    return 0;
}

// ── 2D canvas: CPU Image + GPU Texture2D pairs (lp.tex.*) ───────────────────
// The canvas is the 2D surface of the template: Lua paints into the CPU Image
// (lp.tex.stamp / set_pixel / clear), then lp.tex.upload() pushes it to the
// GPU texture. That same texture can be applied to a 3D model material
// (lp.tex.apply_to_model) — the 2D→3D bridge that makes texture painting show
// up on the cube. Per-canvas undo/redo stacks hold Image copies (cap 50).
// GPU calls are deferred: tex.create only allocates the CPU Image; the
// Texture2D is uploaded on the first upload() so --test stays GL-free.
struct CanvasTex {
    Image img = {};      // CPU-side pixels (R8G8B8A8), the source of truth
    Texture2D tex = {};  // GPU upload; .id == 0 until the first upload()
};
static std::vector<CanvasTex> g_canvas;
static std::vector<std::vector<Image>> g_canvas_undo;  // per-canvas undo stacks
static std::vector<std::vector<Image>> g_canvas_redo;  // per-canvas redo stacks
static const size_t CANVAS_UNDO_CAP = 50;

static CanvasTex* canvas_check(lua_State* L, int idx) {
    int id = (int)luaL_checkinteger(L, idx);
    if (id < 0 || id >= (int)g_canvas.size()) {
        luaL_error(L, "tex: bad canvas id %d", id);
        return nullptr;  // unreachable: luaL_error long-jumps
    }
    return &g_canvas[id];
}

static void canvas_stack_push(std::vector<Image>& stack, const Image& src) {
    if (stack.size() >= CANVAS_UNDO_CAP) {
        UnloadImage(stack.front());
        stack.erase(stack.begin());
    }
    stack.push_back(ImageCopy(src));
}

static int l_tex_create(lua_State* L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    if (w <= 0 || h <= 0 || w > 8192 || h > 8192)
        return luaL_error(L, "tex.create: bad size %dx%d", w, h);
    CanvasTex ct;
    ct.img = GenImageColor(w, h, { 255, 255, 255, 255 });  // white canvas
    g_canvas.push_back(ct);
    g_canvas_undo.push_back({});
    g_canvas_redo.push_back({});
    lua_pushinteger(L, (lua_Integer)g_canvas.size() - 1);
    return 1;
}

static int l_tex_stamp(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    float x = (float)luaL_checknumber(L, 2);
    float y = (float)luaL_checknumber(L, 3);
    float radius = (float)luaL_checknumber(L, 4);
    float hardness = (float)luaL_optnumber(L, 5, 1.0f);
    int r = (int)luaL_optinteger(L, 6, 255);
    int g = (int)luaL_optinteger(L, 7, 255);
    int b = (int)luaL_optinteger(L, 8, 255);
    int a = (int)luaL_optinteger(L, 9, 255);
    if (radius <= 0.0f) return 0;
    if (ct->img.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8)
        return luaL_error(L, "tex.stamp: unsupported image format %d", ct->img.format);
    hardness = fmaxf(0.0f, fminf(1.0f, hardness));

    int cx = (int)floorf(x), cy = (int)floorf(y);
    int rad = (int)ceilf(radius);
    int x0 = cx - rad, x1 = cx + rad, y0 = cy - rad, y1 = cy + rad;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 >= ct->img.width) x1 = ct->img.width - 1;
    if (y1 >= ct->img.height) y1 = ct->img.height - 1;

    unsigned char* px = (unsigned char*)ct->img.data;
    float ca = a / 255.0f;
    for (int py = y0; py <= y1; py++) {
        for (int pxx = x0; pxx <= x1; pxx++) {
            float dx = pxx - x;
            float dy = py - y;
            float dist = sqrtf(dx * dx + dy * dy);
            if (dist > radius) continue;
            // Falloff: hardness 0 = hard edge, 1 = softest (linear) edge.
            float t = 1.0f - dist / radius;
            float af = ca * powf(t, hardness);
            unsigned char* p = px + ((size_t)py * ct->img.width + pxx) * 4;
            p[0] = (unsigned char)(r * af + p[0] * (1.0f - af));
            p[1] = (unsigned char)(g * af + p[1] * (1.0f - af));
            p[2] = (unsigned char)(b * af + p[2] * (1.0f - af));
            p[3] = (unsigned char)(a * af + p[3] * (1.0f - af));
        }
    }
    return 0;
}

static int l_tex_get_pixel(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    if (x < 0 || y < 0 || x >= ct->img.width || y >= ct->img.height)
        return luaL_error(L, "tex.get_pixel: (%d,%d) out of bounds for %dx%d",
                          x, y, ct->img.width, ct->img.height);
    unsigned char* p = (unsigned char*)ct->img.data + ((size_t)y * ct->img.width + x) * 4;
    lua_pushinteger(L, ((lua_Integer)p[0] << 24) | ((lua_Integer)p[1] << 16) |
                       ((lua_Integer)p[2] << 8) | p[3]);
    return 1;
}

static int l_tex_set_pixel(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    lua_Integer c = luaL_checkinteger(L, 4);
    if (x < 0 || y < 0 || x >= ct->img.width || y >= ct->img.height)
        return luaL_error(L, "tex.set_pixel: (%d,%d) out of bounds for %dx%d",
                          x, y, ct->img.width, ct->img.height);
    unsigned char* p = (unsigned char*)ct->img.data + ((size_t)y * ct->img.width + x) * 4;
    p[0] = (unsigned char)((c >> 24) & 0xFF);
    p[1] = (unsigned char)((c >> 16) & 0xFF);
    p[2] = (unsigned char)((c >> 8) & 0xFF);
    p[3] = (unsigned char)(c & 0xFF);
    return 0;
}

static int l_tex_clear(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    lua_Integer c = luaL_checkinteger(L, 2);
    ImageClearBackground(&ct->img, { (unsigned char)((c >> 24) & 0xFF),
                                     (unsigned char)((c >> 16) & 0xFF),
                                     (unsigned char)((c >> 8) & 0xFF),
                                     (unsigned char)(c & 0xFF) });
    return 0;
}

static int l_tex_upload(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    if (ct->img.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8)
        return luaL_error(L, "tex.upload: unsupported image format %d", ct->img.format);
    if (ct->tex.id == 0) ct->tex = LoadTextureFromImage(ct->img);
    else UpdateTexture(ct->tex, ct->img.data);
    return 0;
}

// lp.tex.load_image_from_file(tid, path) -> bool
// Replaces the canvas image with the file's image (resized to the canvas
// size, preserving the R8G8B8A8 pipeline) and invalidates the GPU texture so
// the next upload() reloads it. Returns false for unsupported/unreadable
// files WITHOUT touching the existing canvas (graceful rejection).
static int l_tex_load_image_from_file(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    CanvasTex* ct = canvas_check(L, 1);
    const char* path = luaL_checkstring(L, 2);

    Image img = LoadImage(path);
    if (!IsImageValid(img)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    // Convert to RGBA8 and resize to the canvas (raylib 6.0 mutates in place).
    if (img.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
        ImageFormat(&img, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
    }
    if (img.width != ct->img.width || img.height != ct->img.height) {
        ImageResize(&img, ct->img.width, ct->img.height);
    }
    UnloadImage(ct->img);
    ct->img = img;
    if (ct->tex.id != 0) {
        UnloadTexture(ct->tex);
        ct->tex = {};
    }
    // Undo stacks reference the old image — clear them to avoid stale state.
    g_canvas_undo[id].clear();
    g_canvas_redo[id].clear();
    lua_pushboolean(L, 1);
    return 1;
}

static void mkdir_one(const char* p);  // defined in the file-helpers section

static int l_tex_export_png(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    const char* path = luaL_checkstring(L, 2);
    // Ensure the parent dir exists (intermediate levels only — the last
    // component is the file itself, unlike lp.file.mkdirs which takes a dir)
    char buf[1024];
    snprintf(buf, sizeof(buf), "%s", path);
    for (char* p = buf + 1; *p; p++) {
        if (*p == '/' || *p == '\\') {
            char save = *p;
            *p = '\0';
            mkdir_one(buf);
            *p = save;
        }
    }
    lua_pushboolean(L, ExportImage(ct->img, path));
    return 1;
}

static int l_tex_push_undo(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id < 0 || id >= (int)g_canvas.size())
        return luaL_error(L, "tex.push_undo: bad canvas id %d", id);
    canvas_stack_push(g_canvas_undo[id], g_canvas[id].img);
    // A new action invalidates the redo stack
    for (auto& im : g_canvas_redo[id]) UnloadImage(im);
    g_canvas_redo[id].clear();
    return 0;
}

static int l_tex_pop_undo(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id < 0 || id >= (int)g_canvas.size())
        return luaL_error(L, "tex.pop_undo: bad canvas id %d", id);
    auto& stack = g_canvas_undo[id];
    if (stack.empty()) { lua_pushboolean(L, 0); return 1; }
    Image prev = stack.back();
    stack.pop_back();
    canvas_stack_push(g_canvas_redo[id], g_canvas[id].img);  // old state → redo
    UnloadImage(g_canvas[id].img);
    g_canvas[id].img = prev;
    lua_pushboolean(L, 1);
    return 1;
}

static int l_tex_push_redo(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id < 0 || id >= (int)g_canvas.size())
        return luaL_error(L, "tex.push_redo: bad canvas id %d", id);
    canvas_stack_push(g_canvas_redo[id], g_canvas[id].img);
    return 0;
}

static int l_tex_pop_redo(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id < 0 || id >= (int)g_canvas.size())
        return luaL_error(L, "tex.pop_redo: bad canvas id %d", id);
    auto& stack = g_canvas_redo[id];
    if (stack.empty()) { lua_pushboolean(L, 0); return 1; }
    Image next = stack.back();
    stack.pop_back();
    canvas_stack_push(g_canvas_undo[id], g_canvas[id].img);  // old state → undo
    UnloadImage(g_canvas[id].img);
    g_canvas[id].img = next;
    lua_pushboolean(L, 1);
    return 1;
}

static int l_tex_apply_to_model(lua_State* L) {
    int tid = (int)luaL_checkinteger(L, 1);
    int mid = (int)luaL_checkinteger(L, 2);
    if (tid < 0 || tid >= (int)g_canvas.size())
        return luaL_error(L, "tex.apply_to_model: bad canvas id %d", tid);
    if (mid < 0 || mid >= (int)g_models.size())
        return luaL_error(L, "tex.apply_to_model: bad model id %d", mid);
    SetMaterialTexture(&g_models[mid].materials[0], MATERIAL_MAP_ALBEDO, g_canvas[tid].tex);
    return 0;
}

static int l_tex_texture_id(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    // GL texture handle as an integer — rlImGui's ImTextureID convention,
    // used by ig.dl_add_image for the in-sidebar canvas preview.
    lua_pushinteger(L, (lua_Integer)(intptr_t)ct->tex.id);
    return 1;
}

static int l_tex_can_undo(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id < 0 || id >= (int)g_canvas.size())
        return luaL_error(L, "tex.can_undo: bad canvas id %d", id);
    lua_pushboolean(L, !g_canvas_undo[id].empty());
    return 1;
}

static int l_tex_can_redo(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id < 0 || id >= (int)g_canvas.size())
        return luaL_error(L, "tex.can_redo: bad canvas id %d", id);
    lua_pushboolean(L, !g_canvas_redo[id].empty());
    return 1;
}

static void tex_register(lua_State* L) {
    lua_getglobal(L, "lp");
    lua_newtable(L);
#define TR(name) lua_pushcfunction(L, l_tex_##name); lua_setfield(L, -2, #name)
    TR(create);
    TR(stamp);
    TR(get_pixel);
    TR(set_pixel);
    TR(clear);
    TR(upload);
    TR(export_png);
    TR(push_undo);
    TR(pop_undo);
    TR(push_redo);
    TR(pop_redo);
    TR(apply_to_model);
    TR(texture_id);
    TR(can_undo);
    TR(can_redo);
    TR(load_image_from_file);
#undef TR
    lua_setfield(L, -2, "tex");
    lua_pop(L, 1);
}

// ── 2D viewport camera bindings (lp.cam2d.*) ────────────────────────────────
static int l_cam2d_set(lua_State* L) {
    g_cam2d.target = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2) };
    g_cam2d.zoom = (float)luaL_checknumber(L, 3);
    if (g_cam2d.zoom <= 0.0f) g_cam2d.zoom = 1.0f;
    return 0;
}

static int l_cam2d_get(lua_State* L) {
    lua_pushnumber(L, g_cam2d.target.x);
    lua_pushnumber(L, g_cam2d.target.y);
    lua_pushnumber(L, g_cam2d.zoom);
    return 3;
}

static void cam2d_register(lua_State* L) {
    lua_getglobal(L, "lp");
    lua_newtable(L);
    lua_pushcfunction(L, l_cam2d_set); lua_setfield(L, -2, "set");
    lua_pushcfunction(L, l_cam2d_get); lua_setfield(L, -2, "get");
    lua_setfield(L, -2, "cam2d");
    lua_pop(L, 1);
}

// ── World-space 2D draw bindings (lp.rl.*, called inside BeginMode2D) ──────
static int l_rl_begin_mode2d(lua_State* L) {
    cam2d_refresh_offset();
    BeginMode2D(g_cam2d);
    return 0;
}

static int l_rl_end_mode2d(lua_State* L) {
    EndMode2D();
    return 0;
}

static int l_rl_draw_texture(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    float x = (float)luaL_checknumber(L, 2);
    float y = (float)luaL_checknumber(L, 3);
    float w = (float)luaL_checknumber(L, 4);
    float h = (float)luaL_checknumber(L, 5);
    if (ct->tex.id == 0) {
        // Never uploaded (e.g. --test) — draw a neutral placeholder
        DrawRectangleRec({ x, y, w, h }, { 200, 200, 205, 255 });
        return 0;
    }
    DrawTexturePro(ct->tex, { 0, 0, (float)ct->img.width, (float)ct->img.height },
                   { x, y, w, h }, { 0, 0 }, 0.0f, WHITE);
    return 0;
}

// Colors are float-friendly: 0..255 numbers (ints or floats) cast to bytes.
static int l_rl_draw_line_2d(lua_State* L) {
    Vector2 a = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2) };
    Vector2 b = { (float)luaL_checknumber(L, 3), (float)luaL_checknumber(L, 4) };
    float thick = (float)luaL_optnumber(L, 5, 1.0f);
    int r = (int)luaL_optnumber(L, 6, 255);
    int g = (int)luaL_optnumber(L, 7, 255);
    int b2 = (int)luaL_optnumber(L, 8, 255);
    int a2 = (int)luaL_optnumber(L, 9, 255);
    DrawLineEx(a, b, thick, { (unsigned char)r, (unsigned char)g, (unsigned char)b2, (unsigned char)a2 });
    return 0;
}

static int l_rl_draw_circle_lines_2d(lua_State* L) {
    Vector2 c = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2) };
    float radius = (float)luaL_checknumber(L, 3);
    float thick = (float)luaL_optnumber(L, 4, 1.0f);
    int r = (int)luaL_optnumber(L, 5, 255);
    int g = (int)luaL_optnumber(L, 6, 255);
    int b = (int)luaL_optnumber(L, 7, 255);
    int a = (int)luaL_optnumber(L, 8, 255);
    float inner = radius - thick * 0.5f;
    if (inner < 0.0f) inner = 0.0f;
    int segs = (int)(radius * 2.0f);
    if (segs < 16) segs = 16;
    DrawRing(c, inner, radius + thick * 0.5f, 0.0f, 360.0f, segs,
             { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_draw_rect_2d(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float w = (float)luaL_checknumber(L, 3);
    float h = (float)luaL_checknumber(L, 4);
    int r = (int)luaL_optnumber(L, 5, 255);
    int g = (int)luaL_optnumber(L, 6, 255);
    int b = (int)luaL_optnumber(L, 7, 255);
    int a = (int)luaL_optnumber(L, 8, 255);
    DrawRectangleRec({ x, y, w, h }, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_draw_text_2d(lua_State* L) {
    const char* text = luaL_checkstring(L, 1);
    int x = (int)luaL_checknumber(L, 2);
    int y = (int)luaL_checknumber(L, 3);
    int size = (int)luaL_checknumber(L, 4);
    int r = (int)luaL_optnumber(L, 5, 255);
    int g = (int)luaL_optnumber(L, 6, 255);
    int b = (int)luaL_optnumber(L, 7, 255);
    int a = (int)luaL_optnumber(L, 8, 255);
    DrawText(text, x, y, size, { (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a });
    return 0;
}

static int l_rl_screen_to_world(lua_State* L) {
    cam2d_refresh_offset();
    Vector2 w = GetScreenToWorld2D({ (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2) }, g_cam2d);
    lua_pushnumber(L, w.x);
    lua_pushnumber(L, w.y);
    return 2;
}

// ── Headless input drive — bindings ─────────────────────────────────────────
static int l_drive_active(lua_State* L) {
    g_drive_active = lua_toboolean(L, 1);
    return 0;
}
static int l_drive_mouse(lua_State* L) {
    g_drive_mx = (float)luaL_checknumber(L, 1);
    g_drive_my = (float)luaL_checknumber(L, 2);
    return 0;
}
static int l_drive_button(lua_State* L) {
    int btn = (int)luaL_checkinteger(L, 1);
    bool down = lua_toboolean(L, 2);
    if (btn < 0 || btn > 2) return luaL_error(L, "drive.button: btn %d out of range (0-2)", btn);
    if (down && !g_drive_btn[btn]) g_drive_btn_pressed[btn] = true;
    g_drive_btn[btn] = down;
    return 0;
}
static int l_drive_wheel(lua_State* L) {
    g_drive_wheel += (float)luaL_checknumber(L, 1);
    return 0;
}
static int l_drive_key(lua_State* L) {
    int code = (int)luaL_checkinteger(L, 1);
    bool down = lua_toboolean(L, 2);
    if (code < 0 || code >= 512) return luaL_error(L, "drive.key: code %d out of range", code);
    if (down && !g_drive_key_down[code]) g_drive_key_pressed[code] = true;
    g_drive_key_down[code] = down;
    return 0;
}
// Frame boundary: previous pos advances, wheel + pressed sets clear.
static int l_drive_frame(lua_State* L) {
    g_drive_px = g_drive_mx;
    g_drive_py = g_drive_my;
    g_drive_wheel = 0;
    for (int i = 0; i < 3; i++) g_drive_btn_pressed[i] = false;
    memset(g_drive_key_pressed, 0, sizeof(g_drive_key_pressed));
    return 0;
}

static void drive_register(lua_State* L) {
    lua_getglobal(L, "lp");
    lua_newtable(L);
#define DR(name) lua_pushcfunction(L, l_drive_##name); lua_setfield(L, -2, #name)
    DR(active);
    DR(mouse);
    DR(button);
    DR(wheel);
    DR(key);
    DR(frame);
#undef DR
    lua_setfield(L, -2, "drive");
    lua_pop(L, 1);
}

// Helper: does drive mode override a given input source?

static void rl_register(lua_State* L) {
    lua_getglobal(L, "lp");
    lua_newtable(L);
#define RR(name) lua_pushcfunction(L, l_rl_##name); lua_setfield(L, -2, #name)
    RR(draw_cube);
    RR(draw_cube_wires);
    RR(draw_grid);
    RR(draw_line_3d);
    RR(draw_sphere);
    RR(draw_sphere_wires);
    RR(draw_triangle_3d);
    RR(draw_cylinder);
    RR(draw_cylinder_wires);
    RR(world_to_screen);
    RR(begin_mode2d);
    RR(end_mode2d);
    RR(draw_texture);
    RR(draw_line_2d);
    RR(draw_circle_lines_2d);
    RR(draw_rect_2d);
    RR(draw_text_2d);
    RR(screen_to_world);
    RR(set_camera);
    RR(get_camera);
    RR(get_ray);
    RR(is_mouse_button_down);
    RR(is_mouse_button_pressed);
    RR(get_mouse_delta);
    RR(get_mouse_wheel);
    RR(get_mouse_pos);
    RR(is_key_pressed);
    RR(is_key_down);
    RR(get_frame_time);
    RR(get_screen_size);
    RR(set_window_size);
    RR(get_monitor_size);
    RR(set_window_position);
    RR(get_window_position);
    RR(set_mouse_cursor);
    RR(take_screenshot);
    RR(set_lighting_enabled);
    RR(is_lighting_enabled);
    RR(set_target_fps);
    RR(get_target_fps);
    RR(get_monitor_refresh_rate);
    RR(get_clipboard_text);
    RR(clipboard_file_path);
    RR(is_file_dropped);
    RR(take_dropped_file);
    RR(load_model_cube);
    RR(load_model_mesh);
    RR(load_model_cylinder);
    RR(load_texture_perlin);
    RR(load_shader);
    RR(set_material_texture);
    RR(set_material_shader);
    RR(set_material_color);
    RR(get_shader_location);
    RR(set_shader_value_vec3);
    RR(set_shader_value_float);
    RR(draw_model);
    RR(draw_model_wires);
    RR(unload_model);
    RR(debug_material);
    RR(unload_texture);
    RR(unload_shader);
#undef RR

    // Material map constants (raylib 6.0: ALBEDO == DIFFUSE)
    lua_pushinteger(L, MATERIAL_MAP_ALBEDO); lua_setfield(L, -2, "MAP_ALBEDO");
    lua_pushinteger(L, MATERIAL_MAP_NORMAL); lua_setfield(L, -2, "MAP_NORMAL");
    lua_pushinteger(L, MATERIAL_MAP_METALNESS); lua_setfield(L, -2, "MAP_METALNESS");
    lua_pushinteger(L, MATERIAL_MAP_ROUGHNESS); lua_setfield(L, -2, "MAP_ROUGHNESS");
    lua_pushinteger(L, MATERIAL_MAP_EMISSION); lua_setfield(L, -2, "MAP_EMISSION");

    // Shader uniform types
    lua_pushinteger(L, SHADER_UNIFORM_FLOAT); lua_setfield(L, -2, "UNIFORM_FLOAT");
    lua_pushinteger(L, SHADER_UNIFORM_VEC2);  lua_setfield(L, -2, "UNIFORM_VEC2");
    lua_pushinteger(L, SHADER_UNIFORM_VEC3);  lua_setfield(L, -2, "UNIFORM_VEC3");

    // Raylib key constants
    lua_newtable(L);
#define RK(name, val) lua_pushinteger(L, val); lua_setfield(L, -2, name)
    RK("A", KEY_A); RK("B", KEY_B); RK("C", KEY_C); RK("D", KEY_D);
    RK("E", KEY_E); RK("F", KEY_F); RK("G", KEY_G); RK("H", KEY_H);
    RK("I", KEY_I); RK("J", KEY_J); RK("K", KEY_K); RK("L", KEY_L);
    RK("M", KEY_M); RK("N", KEY_N); RK("O", KEY_O); RK("P", KEY_P);
    RK("Q", KEY_Q); RK("R", KEY_R); RK("S", KEY_S); RK("T", KEY_T);
    RK("U", KEY_U); RK("V", KEY_V); RK("W", KEY_W); RK("X", KEY_X);
    RK("Y", KEY_Y); RK("Z", KEY_Z);
    RK("0", KEY_ZERO); RK("1", KEY_ONE); RK("2", KEY_TWO); RK("3", KEY_THREE);
    RK("4", KEY_FOUR); RK("5", KEY_FIVE); RK("6", KEY_SIX); RK("7", KEY_SEVEN);
    RK("8", KEY_EIGHT); RK("9", KEY_NINE);
    RK("F1", KEY_F1); RK("F2", KEY_F2); RK("F3", KEY_F3); RK("F4", KEY_F4);
    RK("F5", KEY_F5); RK("F6", KEY_F6); RK("F7", KEY_F7); RK("F8", KEY_F8);
    RK("F9", KEY_F9); RK("F10", KEY_F10); RK("F11", KEY_F11); RK("F12", KEY_F12);
    RK("Space", KEY_SPACE); RK("Enter", KEY_ENTER); RK("Escape", KEY_ESCAPE);
    RK("Tab", KEY_TAB); RK("Backspace", KEY_BACKSPACE); RK("Delete", KEY_DELETE);
    RK("LeftShift", KEY_LEFT_SHIFT); RK("RightShift", KEY_RIGHT_SHIFT);
    RK("LeftControl", KEY_LEFT_CONTROL); RK("RightControl", KEY_RIGHT_CONTROL);
    RK("LeftAlt", KEY_LEFT_ALT); RK("RightAlt", KEY_RIGHT_ALT);
    RK("LeftCtrl", KEY_LEFT_CONTROL); RK("RightCtrl", KEY_RIGHT_CONTROL);
    RK("Ctrl", KEY_LEFT_CONTROL); RK("Shift", KEY_LEFT_SHIFT); RK("Alt", KEY_LEFT_ALT);
#undef RK
    lua_setfield(L, -2, "key");

    // Mouse button constants
    lua_pushinteger(L, MOUSE_BUTTON_LEFT);   lua_setfield(L, -2, "MOUSE_LEFT");
    lua_pushinteger(L, MOUSE_BUTTON_RIGHT);  lua_setfield(L, -2, "MOUSE_RIGHT");
    lua_pushinteger(L, MOUSE_BUTTON_MIDDLE); lua_setfield(L, -2, "MOUSE_MIDDLE");

    // Cursor constants (for lp.rl.set_mouse_cursor hover affordances)
    lua_pushinteger(L, MOUSE_CURSOR_DEFAULT);    lua_setfield(L, -2, "CURSOR_DEFAULT");
    lua_pushinteger(L, MOUSE_CURSOR_RESIZE_EW);  lua_setfield(L, -2, "CURSOR_RESIZE_EW");
    lua_pushinteger(L, MOUSE_CURSOR_RESIZE_NS);  lua_setfield(L, -2, "CURSOR_RESIZE_NS");
    lua_pushinteger(L, MOUSE_CURSOR_RESIZE_NWSE);lua_setfield(L, -2, "CURSOR_RESIZE_NWSE");
    lua_pushinteger(L, MOUSE_CURSOR_RESIZE_NESW);lua_setfield(L, -2, "CURSOR_RESIZE_NESW");
    lua_pushinteger(L, MOUSE_CURSOR_POINTING_HAND); lua_setfield(L, -2, "CURSOR_HAND");
    lua_pushinteger(L, MOUSE_CURSOR_CROSSHAIR);  lua_setfield(L, -2, "CURSOR_CROSSHAIR");

    lua_setfield(L, -2, "rl");
    lua_pop(L, 1);
}

// ── Lua VM ──────────────────────────────────────────────────────────────────
static lua_State* L_global = nullptr;
static char lua_dir[2048] = {};

// ── file helpers ────────────────────────────────────────────────────────────
#ifdef _WIN32
#include <direct.h>
static void mkdir_one(const char* p) { _mkdir(p); }
#else
#include <sys/stat.h>
static void mkdir_one(const char* p) { mkdir(p, 0755); }
#endif

// lp.file.mkdirs("a/b/c") — creates each path level, silently ignores
// existing dirs. Needed so exports can write into build/ in any layout.
static int l_file_mkdirs(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    char buf[1024];
    snprintf(buf, sizeof(buf), "%s", path);
    for (char* p = buf + 1; *p; p++) {
        if (*p == '/' || *p == '\\') {
            char save = *p;
            *p = '\0';
            mkdir_one(buf);
            *p = save;
        }
    }
    mkdir_one(buf);
    return 0;
}

// lp.file.exists(path) -> bool
static int l_file_exists(lua_State* L) {
    lua_pushboolean(L, FileExists(luaL_checkstring(L, 1)));
    return 1;
}

// lp.file.list_dir(path) -> dirs{}, files{} (basenames, no subdir scan).
// Backing the in-app file browser fallback (no zenity/kdialog on WSLg).
static int l_file_list_dir(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    FilePathList list = LoadDirectoryFiles(path);
    lua_newtable(L);  // dirs
    lua_newtable(L);  // files
    int nd = 0, nf = 0;
    for (unsigned int i = 0; i < list.count; i++) {
        const char* p = list.paths[i];
        if (DirectoryExists(p)) {
            nd++;
            lua_pushstring(L, GetFileName(p));
            lua_rawseti(L, -3, nd);
        } else {
            nf++;
            lua_pushstring(L, GetFileName(p));
            lua_rawseti(L, -2, nf);
        }
    }
    UnloadDirectoryFiles(list);
    return 2;
}

static void file_register(lua_State* L) {
    lua_getglobal(L, "lp");
    lua_newtable(L);
    lua_pushcfunction(L, l_file_mkdirs);
    lua_setfield(L, -2, "mkdirs");
    lua_pushcfunction(L, l_file_exists);
    lua_setfield(L, -2, "exists");
    lua_pushcfunction(L, l_file_list_dir);
    lua_setfield(L, -2, "list_dir");
    lua_setfield(L, -2, "file");
    lua_pop(L, 1);
}

lua_State* lua_state() { return L_global; }

void app_log(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
}

void lua_init(const char* root_dir) {
    std::string l_dir = app_paths::resolve_lua_dir(root_dir);
    snprintf(lua_dir, sizeof(lua_dir), "%s", l_dir.c_str());

    L_global = luaL_newstate();
    luaL_openlibs(L_global);

    lua_newtable(L_global);
    lua_newtable(L_global);
    lua_pushcfunction(L_global, [](lua_State* L) -> int {
        app_log("%s", luaL_checkstring(L, 1));
        return 0;
    });
    lua_setfield(L_global, -2, "log");
    lua_pushcfunction(L_global, l_app_open_file_dialog);
    lua_setfield(L_global, -2, "open_file_dialog");
    lua_pushcfunction(L_global, [](lua_State* L) -> int {
        lua_pushstring(L, "Raylib 6.0 (OpenGL 3.3)");
        return 1;
    });
    lua_setfield(L_global, -2, "backend_name");
    lua_setfield(L_global, -2, "app");
    lua_setglobal(L_global, "lp");

    app_paths::register_lua_bindings(L_global, "Raylib 6.0 (OpenGL 3.3)");

    ig_register(L_global);
    rl_register(L_global);
    tex_register(L_global);
    cam2d_register(L_global);
    drive_register(L_global);
    file_register(L_global);

    // Set package.path
    lua_getglobal(L_global, "package");
    char path_buf[4096];
    snprintf(path_buf, sizeof(path_buf), "%s/?.lua;%s/?/init.lua", lua_dir, lua_dir);
    lua_pushstring(L_global, path_buf);
    lua_setfield(L_global, -2, "path");
    lua_pop(L_global, 1);

    // Load main.lua
    char main_path[2048];
    snprintf(main_path, sizeof(main_path), "%s/main.lua", lua_dir);
    if (luaL_dofile(L_global, main_path) != LUA_OK) {
        app_log("[LUA LOAD ERROR] %s", lua_tostring(L_global, -1));
        lua_pop(L_global, 1);
    }
}

void lua_frame() {
    if (!L_global) return;
    ig_clear_draw_lists();
    lua_getglobal(L_global, "lp_frame");
    if (lua_isfunction(L_global, -1)) {
        if (lua_pcall(L_global, 0, 0, 0) != LUA_OK) {
            app_log("[LUA ERROR] %s", lua_tostring(L_global, -1));
            lua_pop(L_global, 1);
        }
    } else {
        lua_pop(L_global, 1);
    }
    ig_balance_check();
}

// Call a global Lua function by name; errors are logged, not fatal.
void lp_call_global(const char* name) {
    if (!L_global) return;
    lua_getglobal(L_global, name);
    if (lua_isfunction(L_global, -1)) {
        if (lua_pcall(L_global, 0, 0, 0) != LUA_OK) {
            app_log("[LUA ERROR %s] %s", name, lua_tostring(L_global, -1));
            lua_pop(L_global, 1);
        }
    } else {
        lua_pop(L_global, 1);
    }
}

void lua_shutdown() {
    if (L_global) { lua_close(L_global); L_global = nullptr; }
}

// ── Theme & Fonts ───────────────────────────────────────────────────────────
// Non-default UI: deep-slate surfaces + amber accent (texturewrangler family),
// and a Latin/Cyrillic primary font with a merged CJK fallback so every script
// renders. Fonts load from the dev-shell env paths or assets/fonts/ (packaged).

static void setup_imgui_fonts_and_theme() {
    rlImGuiBeginInitImGui();
    apply_modern_dark_theme();
    build_imgui_font_atlas();
    rlImGuiEndInitImGui();
}

// ── Main ────────────────────────────────────────────────────────────────────
// CLI modes (all headless-capable):
//   (no args)            interactive window
//   --shot out.png [--frames N] [--drive script.lua]   headless capture;
//                        runs N frames (window hidden), saves PNG, exits.
//                        --drive loads script.lua and calls its D.step()
//                        every frame so the capture can be input-driven.
//   --test               headless boot check: load Lua, run tests/testmain.lua
//                        if present, exit 0/1.
static bool has_arg(int argc, char** argv, const char* name) {
    for (int i = 1; i < argc; i++) if (strcmp(argv[i], name) == 0) return true;
    return false;
}
static const char* get_arg(int argc, char** argv, const char* name, const char* def) {
    for (int i = 1; i < argc - 1; i++) if (strcmp(argv[i], name) == 0) return argv[i + 1];
    return def;
}

// ── Frame render ─────────────────────────────────────────────────────────────
// The draw pass only — shared by the main loop and (on Windows) the resize
// subclass below. Does NOT present: the caller decides how.
//  - Windows main loop: present_no_poll() + one explicit PollInputEvents().
//    EndDrawing is NOT used there (its PollInputEvents must not be called
//    while the subclass can re-enter), and its GetFrameTime() would fight
//    our own dt — hence g_own_dt + rlImGuiBeginDelta below.
//  - Linux main loop: EndDrawing() → flush + swap + the single input poll.
//  - subclass (Windows, modal resize loop): present_no_poll(), NO
//    PollInputEvents (nested glfwPollEvents from wndproc context corrupts
//    raylib/GLFW input state).
static void render_frame_contents() {
    update_own_dt();
    BeginDrawing();
    ClearBackground({ 24, 24, 28, 255 });

    BeginMode3D(g_camera);
    lp_call_global("lp_draw3d");
    EndMode3D();

    // 2D pass after the 3D pass: raylib 6.0's BeginMode2D expects the base
    // ortho projection (it no longer installs its own), so 2D content must
    // be drawn OUTSIDE BeginMode3D. lp_draw2d is a no-op when absent/3D.
    lp_call_global("lp_draw2d");

    rlImGuiBeginDelta(g_own_dt);
    if (g_drive_active) {
        ImGuiIO& io = ImGui::GetIO();
        io.AddMousePosEvent(g_drive_mx, g_drive_my);
        io.AddMouseButtonEvent(0, g_drive_btn[0]);
        io.AddMouseButtonEvent(1, g_drive_btn[1]);
        io.AddMouseButtonEvent(2, g_drive_btn[2]);
        if (g_drive_wheel != 0) {
            io.AddMouseWheelEvent(0.0f, g_drive_wheel);
        }
        io.AddKeyEvent(ImGuiMod_Ctrl, g_drive_key_down[KEY_LEFT_CONTROL] || g_drive_key_down[KEY_RIGHT_CONTROL]);
        io.AddKeyEvent(ImGuiMod_Shift, g_drive_key_down[KEY_LEFT_SHIFT] || g_drive_key_down[KEY_RIGHT_SHIFT]);
        io.AddKeyEvent(ImGuiMod_Alt, g_drive_key_down[KEY_LEFT_ALT] || g_drive_key_down[KEY_RIGHT_ALT]);
    }
    lua_frame();
    rlImGuiEnd();
}

#ifdef _WIN32
// Present WITHOUT polling events — safe from wndproc (subclass) context.
static void present_no_poll() {
    rlDrawRenderBatchActive();
    SwapBuffers(wglGetCurrentDC());
}
// ── Windows continuous-resize ────────────────────────────────────────────────
// During a drag-resize, DefWindowProc runs a modal loop on the GUI thread; no
// frames are presented and DWM stretches the stale backbuffer. Subclass the
// GLFW window and render from inside the modal loop on every WM_SIZE.
// Crash-safety rules (previous subclass attempts crashed by violating them):
//  1. NEVER call EndDrawing()/glfwPollEvents() re-entrantly from wndproc
//     context — nested polls corrupt GLFW's queue + raylib input state.
//     render_frame_contents() only draws; present_no_poll() flushes+swaps.
//  2. The modal loop runs on the main thread, entered from the outer frame's
//     poll (after the outer swap) — GL state is at a frame boundary. Keep a
//     re-entrancy latch anyway.
//  3. Call the original (GLFW) wndproc FIRST so raylib's size callback has
//     updated CORE.Window before we re-render.
// Proven in poc_resize/ (poc_min, poc_imgui, poc_lua — incl. Lua coroutines).
#define CF_GWLP_WNDPROC      (-4)
#define CF_WM_SIZE           0x0005u
#define CF_WM_ENTERSIZEMOVE  0x0231u
#define CF_WM_EXITSIZEMOVE   0x0232u
#define CF_SIZE_MINIMIZED    1ull
typedef long long (*CfWndProc)(void*, unsigned, unsigned long long, long long);
static CfWndProc g_orig_proc = nullptr;
static bool      g_in_sizemove = false;
static bool      g_in_subclass_render = false;
static bool      g_headless_mode = false;   // mirrored from main; subclass render skipped

static long long __stdcall cf_resize_subclass_proc(void* hwnd, unsigned msg,
                                                   unsigned long long wp, long long lp) {
    if (msg == CF_WM_ENTERSIZEMOVE) g_in_sizemove = true;
    if (msg == CF_WM_EXITSIZEMOVE)  g_in_sizemove = false;

    long long res = CallWindowProcW((long long)g_orig_proc, hwnd, msg, wp, lp);

    if (msg == CF_WM_SIZE && wp != CF_SIZE_MINIMIZED && g_in_sizemove &&
        !g_in_subclass_render && !g_headless_mode) {
        g_in_subclass_render = true;
        render_frame_contents();
        present_no_poll();
        g_in_subclass_render = false;
    }
    return res;
}

static void install_resize_subclass() {
    void* hwnd = GetWindowHandle();
    g_orig_proc = (CfWndProc)GetWindowLongPtrW(hwnd, CF_GWLP_WNDPROC);
    SetWindowLongPtrW(hwnd, CF_GWLP_WNDPROC, (long long)cf_resize_subclass_proc);
}
static void uninstall_resize_subclass() {
    if (!g_orig_proc) return;
    void* hwnd = GetWindowHandle();
    SetWindowLongPtrW(hwnd, CF_GWLP_WNDPROC, (long long)g_orig_proc);
    g_orig_proc = nullptr;
}
#endif

int main(int argc, char** argv) {
    const char* shot_path = get_arg(argc, argv, "--shot", nullptr);
    int shot_frames = atoi(get_arg(argc, argv, "--frames", "20"));
    const char* drive_script = get_arg(argc, argv, "--drive", nullptr);
    bool headless = shot_path != nullptr;

    // Find root dir: prefer cwd if it contains lua (dev or packaged layout),
    // else the exe's own directory (packaged: exe sits next to lua/).
    char root[2048];
    if (FileExists("editor/lua/main.lua") || FileExists("lua/main.lua")) {
        snprintf(root, sizeof(root), ".");
    } else {
        snprintf(root, sizeof(root), "%s", GetApplicationDirectory());
        ChangeDirectory(root);
    }

    if (has_arg(argc, argv, "--test")) {
        // Headless boot check: VM + main.lua load, no window/GL needed.
        lua_init(root);
        // Run the headless test suite if it exists (dev or packaged layout).
        char t1[2048], t2[2048];
        snprintf(t1, sizeof(t1), "%s/editor/tests/testmain.lua", root);
        snprintf(t2, sizeof(t2), "%s/tests/testmain.lua", root);
        const char* candidates[] = { t1, t2, "./editor/tests/testmain.lua", "./tests/testmain.lua" };
        const char* found = nullptr;
        for (const char* c : candidates) if (FileExists(c)) { found = c; break; }
        if (found) {
            if (luaL_dofile(L_global, found) != LUA_OK) {
                app_log("[TEST ERROR] %s", lua_tostring(L_global, -1));
                lua_shutdown();
                return 1;
            }
        } else {
            app_log("[--test] no testmain.lua found; boot check only");
        }
        lua_shutdown();
        return 0;
    }
    int req_w = 1280;
    int req_h = 800;
#ifdef _WIN32
    if (!headless) {
        int work_w = 0, work_h = 0;
        win_get_workarea(&work_w, &work_h);
        if (work_w > 0 && work_h > 0) {
            if (req_w > work_w - 40) req_w = work_w > 80 ? work_w - 40 : work_w;
            if (req_h > work_h - 60) req_h = work_h > 100 ? work_h - 60 : work_h;
            if (req_w < 640 && work_w >= 640) req_w = 640;
            if (req_h < 480 && work_h >= 480) req_h = 480;
        }
    }
#endif

    uint32_t cfg = FLAG_MSAA_4X_HINT | FLAG_VSYNC_HINT | FLAG_WINDOW_RESIZABLE;
    if (headless) cfg |= FLAG_WINDOW_HIDDEN;  // render without stealing focus
    SetConfigFlags(cfg);
    InitWindow(req_w, req_h, "CubeForge — Raylib + ImGui + Lua");
    SetTargetFPS(0); // Unlocked / synchronized to monitor native refresh rate (e.g. 240Hz)

    // Guard against negative window positions or monitor bounds overflow (e.g. 800x600 displays):
    if (!headless) {
        int mon = GetCurrentMonitor();
        int mon_w = GetMonitorWidth(mon);
        int mon_h = GetMonitorHeight(mon);
        if (mon_w > 0 && mon_h > 0) {
            int cur_w = GetScreenWidth();
            int cur_h = GetScreenHeight();
            if (cur_w > mon_w || cur_h > mon_h) {
                int fit_w = (cur_w > mon_w) ? (mon_w > 40 ? mon_w - 40 : mon_w) : cur_w;
                int fit_h = (cur_h > mon_h) ? (mon_h > 60 ? mon_h - 60 : mon_h) : cur_h;
                SetWindowSize(fit_w, fit_h);
            }
            Vector2 mon_pos = GetMonitorPosition(mon);
            Vector2 win_pos = GetWindowPosition();
            int final_w = GetScreenWidth();
            int final_h = GetScreenHeight();
            int safe_x = (int)win_pos.x;
            int safe_y = (int)win_pos.y;
            if (safe_x < (int)mon_pos.x) {
                safe_x = (int)mon_pos.x + std::max(0, (mon_w - final_w) / 2);
            }
            if (safe_y < (int)mon_pos.y) {
                safe_y = (int)mon_pos.y + std::max(0, (mon_h - final_h) / 2);
            }
            if (safe_y < (int)mon_pos.y) safe_y = (int)mon_pos.y;
            if (safe_x != (int)win_pos.x || safe_y != (int)win_pos.y) {
                SetWindowPosition(safe_x, safe_y);
            }
        }
    }

    setup_imgui_fonts_and_theme();  // modern dark theme + CJK/Cyrillic fonts

    lua_init(root);


    bool drive_loaded = false;
    if (drive_script) {
        char dpath[2048];
        if (strchr(drive_script, '/')) snprintf(dpath, sizeof(dpath), "%s", drive_script);
        else if (FileExists("editor/tests/")) snprintf(dpath, sizeof(dpath), "%s/editor/lua/%s", root, drive_script);
        else snprintf(dpath, sizeof(dpath), "%s/lua/%s", root, drive_script);
        if (luaL_dofile(L_global, dpath) == LUA_OK) {
            drive_loaded = true;
            lp_call_global("drive_begin");   // drive.lua sets lp.drive.active(true)
            app_log("[drive] loaded %s", dpath);
        } else {
            app_log("[drive] LOAD ERROR %s", lua_tostring(L_global, -1));
            lua_pop(L_global, 1);
        }
    }

    int frame = 0;
    bool running = true;
#ifdef _WIN32
    g_headless_mode = headless;
    if (!headless) install_resize_subclass();  // continuous render during drag-resize
#endif
    while (running && !WindowShouldClose()) {
        // NOTE: exactly ONE input poll per frame. On Windows the poll is the
        // explicit PollInputEvents() after render_frame_contents() (which
        // swaps without polling); on Linux EndDrawing() inside it does the
        // single poll. Never poll twice — the second poll clears the
        // pressed-queues and drops clicks (intermittent unresponsiveness).

        // Drive step BEFORE input is read: executes this frame's plan + boundary
        if (drive_loaded) lp_call_global("drive_step");

        render_frame_contents();
#ifdef _WIN32
        present_no_poll();
        PollInputEvents();   // the one poll/frame (subclass renders never poll)
#else
        EndDrawing();        // flush + swap + the single poll
#endif
        frame++;

        // Drive frame boundary AFTER render: prev-pos advances, wheel/pressed
        // clears — so the NEXT frame's deltas are measured from this frame.
        if (drive_loaded) lp_call_global("drive_frame");

        if (headless && frame >= shot_frames) {
            // TakeScreenshot also writes an auto-numbered screenshot000.png —
            // unlink that duplicate so only the requested file remains.
            TakeScreenshot(shot_path);
            char dup[2048];
            snprintf(dup, sizeof(dup), "screenshot%03d.png", 0);
            if (strcmp(dup, shot_path) != 0 && FileExists(dup)) remove(dup);
            app_log("Screenshot saved to %s", shot_path);
            running = false;
        }
    }

#ifdef _WIN32
    if (!headless) uninstall_resize_subclass();  // restore GLFW proc before close
#endif
    lua_shutdown();
    rlImGuiShutdown();
    CloseWindow();
    return 0;
}
