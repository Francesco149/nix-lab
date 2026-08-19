// poc_lua.cpp — PoC stage 3: + Lua 5.4. Runs the full Lua frame step inside
// BOTH the main loop and the subclass (modal-resize) render path — same
// thread, so Lua state access is safe by construction; this stage exists to
// prove no snags surface (coroutines, GC, error handling) when lua_frame()
// runs re-entrantly-ish from wndproc context at high frequency.

#include "raylib.h"
#include "rlgl.h"
#include "rlImGui.h"
#include "imgui.h"

#include <cstdio>
#include <cstring>
#include <cmath>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

#ifdef _WIN32
extern "C" {
__declspec(dllimport) void*   __stdcall wglGetCurrentDC(void);
__declspec(dllimport) int     __stdcall SwapBuffers(void* hdc);
__declspec(dllimport) void*   __stdcall GetWindowLongPtrW(void* hwnd, int index);
__declspec(dllimport) long long __stdcall SetWindowLongPtrW(void* hwnd, int index, long long value);
__declspec(dllimport) long long __stdcall CallWindowProcW(long long proc, void* hwnd,
                                                          unsigned msg, unsigned long long wp, long long lp);
}
#define POC_GWLP_WNDPROC     (-4)
#define POC_WM_SIZE          0x0005u
#define POC_WM_ENTERSIZEMOVE 0x0231u
#define POC_WM_EXITSIZEMOVE  0x0232u
#define POC_SIZE_MINIMIZED   1ull
typedef long long (*PocWndProc)(void*, unsigned, unsigned long long, long long);
static PocWndProc g_orig_proc = nullptr;
static bool       g_rendering = false;
static bool       g_in_sizemove = false;
static int        g_subclass_renders = 0;
#endif

static lua_State* g_L = nullptr;
static int        g_ref_poc = LUA_NOREF;
static bool       g_lua_ok = true;
static char       g_lua_err[256] = "";

static int g_lua_frames = 0, g_resizes = 0, g_spin_val = 0;
static bool g_lua_in_sizemove = false;

// One Lua step. Returns true on success. Called from BOTH the main loop and
// the subclass path — always on the main thread.
static bool LuaFrame() {
    if (!g_lua_ok || g_ref_poc == LUA_NOREF) return g_lua_ok;
    lua_rawgeti(g_L, LUA_REGISTRYINDEX, g_ref_poc);
    lua_getfield(g_L, -1, "frame");
    lua_pushinteger(g_L, GetScreenWidth());
    lua_pushinteger(g_L, GetScreenHeight());
    lua_pushboolean(g_L, g_in_sizemove);
    if (lua_pcall(g_L, 3, 1, 0) != LUA_OK) {
        snprintf(g_lua_err, sizeof(g_lua_err), "%s", lua_tostring(g_L, -1));
        lua_pop(g_L, 2);
        g_lua_ok = false;
        return false;
    }
    g_lua_frames = (int)lua_tointeger(g_L, -1);
    lua_pop(g_L, 1);          // frame() result
    // pull stats
    lua_getfield(g_L, -1, "resizes_seen"); g_resizes = (int)lua_tointeger(g_L, -1); lua_pop(g_L, 1);
    lua_getfield(g_L, -1, "spin_val");     g_spin_val = (int)lua_tointeger(g_L, -1); lua_pop(g_L, 1);
    lua_getfield(g_L, -1, "in_sizemove");  g_lua_in_sizemove = lua_toboolean(g_L, -1); lua_pop(g_L, 1);
    lua_pop(g_L, 1);          // module table
    return true;
}

static void RenderFrameNoPoll() {
    LuaFrame();   // Lua drives state; safe on main thread from either path

    BeginDrawing();
    ClearBackground({ 24, 24, 28, 255 });
    int w = GetScreenWidth(), h = GetScreenHeight();

    for (int i = 0; i < 12; i++) {
        float a0 = (i / 12.0f) * 6.28318f + (g_lua_frames % 360) * 0.01745f;
        Vector2 c = { w * 0.5f, h * 0.5f };
        float r1 = (w < h ? w : h) * 0.28f, r2 = (w < h ? w : h) * 0.38f;
        DrawTriangle(
            { c.x + cosf(a0) * r1, c.y + sinf(a0) * r1 },
            { c.x + cosf(a0 + 0.4f) * r2, c.y + sinf(a0 + 0.4f) * r2 },
            { c.x + cosf(a0 - 0.4f) * r2, c.y + sinf(a0 - 0.4f) * r2 },
            { 90, 200, 120, 255 });
    }
    DrawRectangleLinesEx({ 8, 8, (float)w - 16, (float)h - 16 }, 4.0f, { 240, 180, 40, 255 });

    rlImGuiBeginDelta(1.0f / 60.0f);
    ImGui::SetNextWindowPos({ 20, 20 }, ImGuiCond_Once);
    ImGui::SetNextWindowSize({ 400, 240 }, ImGuiCond_Once);
    ImGui::Begin("lua resize monitor");
    ImGui::Text("client: %dx%d", w, h);
#ifdef _WIN32
    ImGui::Text("subclass renders: %d %s", g_subclass_renders, g_in_sizemove ? "(IN SIZEMOVE)" : "");
#else
    ImGui::Text("subclass renders: n/a");
#endif
    ImGui::Separator();
    ImGui::Text("lua: frames=%d resizes=%d spin=%d", g_lua_frames, g_resizes, g_spin_val);
    ImGui::Text("lua sizemove flag: %s", g_lua_in_sizemove ? "true" : "false");
    ImGui::Text("gc: %d KB", g_L ? (int)(lua_gc(g_L, LUA_GCCOUNT)) : 0);
    if (!g_lua_ok) { ImGui::TextColored({ 1, 0.3f, 0.3f, 1 }, "LUA ERROR: %s", g_lua_err); }
    ImGui::End();
    rlImGuiEnd();

    rlDrawRenderBatchActive();
#ifdef _WIN32
    SwapBuffers(wglGetCurrentDC());
#endif
}

#ifdef _WIN32
static long long __stdcall ResizeSubclassProc(void* hwnd, unsigned msg,
                                              unsigned long long wp, long long lp) {
    if (msg == POC_WM_ENTERSIZEMOVE) g_in_sizemove = true;
    if (msg == POC_WM_EXITSIZEMOVE)  g_in_sizemove = false;
    long long res = CallWindowProcW((long long)g_orig_proc, hwnd, msg, wp, lp);
    if (msg == POC_WM_SIZE && wp != POC_SIZE_MINIMIZED && g_in_sizemove) {
        if (!g_rendering) {
            g_rendering = true;
            g_subclass_renders++;
            RenderFrameNoPoll();
            g_rendering = false;
        }
    }
    return res;
}
#endif

int main(int argc, char** argv) {
    SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT);
    InitWindow(1280, 800, "poc_lua — raylib OGL3.3 + rlImGui + Lua smooth resize");
    SetTargetFPS(0);

    rlImGuiBeginInitImGui();
    ImGui::StyleColorsDark();
    rlImGuiEndInitImGui();

    // Lua init — same pattern as the template: dofile from exe dir
    g_L = luaL_newstate();
    luaL_openlibs(g_L);
    const char* script = (argc > 1) ? argv[1] : "poc.lua";
    if (luaL_dofile(g_L, script) != LUA_OK) {
        snprintf(g_lua_err, sizeof(g_lua_err), "%s", lua_tostring(g_L, -1));
        lua_pop(g_L, 1);
        g_lua_ok = false;
        printf("lua load error: %s\n", g_lua_err);
    } else if (lua_istable(g_L, -1)) {
        g_ref_poc = luaL_ref(g_L, LUA_REGISTRYINDEX);
    }

#ifdef _WIN32
    void* hwnd = GetWindowHandle();
    g_orig_proc = (PocWndProc)GetWindowLongPtrW(hwnd, POC_GWLP_WNDPROC);
    SetWindowLongPtrW(hwnd, POC_GWLP_WNDPROC, (long long)ResizeSubclassProc);
    printf("subclass installed: hwnd=%p\n", hwnd);
#endif

    while (!WindowShouldClose()) {
#ifdef _WIN32
        RenderFrameNoPoll();
        PollInputEvents();
#else
        RenderFrameNoPoll();
        EndDrawing();
#endif
    }

#ifdef _WIN32
    SetWindowLongPtrW(hwnd, POC_GWLP_WNDPROC, (long long)g_orig_proc);
#endif
    if (g_ref_poc != LUA_NOREF) luaL_unref(g_L, LUA_REGISTRYINDEX, g_ref_poc);
    lua_close(g_L);
    rlImGuiShutdown();
    CloseWindow();
    printf("lua stats: frames=%d resizes=%d subclass_renders=%d ok=%d\n",
           g_lua_frames, g_resizes, g_subclass_renders, (int)g_lua_ok);
    return 0;
}
