// poc_imgui.cpp — PoC stage 2: raylib OGL3.3 + rlImGui + smooth resize.
// Same subclass no-poll render path as poc_min, now with a full ImGui frame
// inside it. Proves ImGui re-frames correctly during the sizing modal loop.
//
// Caveat accepted: rlImGuiBeginDelta calls ImGui_ImplRaylib_ProcessEvents()
// which reads raylib input state — safe on-thread, may consume key events
// mid-poll. Irrelevant during drag-resize (no typing); main loop re-syncs
// after WM_EXITSIZEMOVE.

#include "raylib.h"
#include "rlgl.h"
#include "rlImGui.h"
#include "imgui.h"
#include "imgui_internal.h"

#include <cstdio>
#include <cstring>
#include <cmath>

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

static float g_hue = 0.0f;
static int   g_clicks = 0;
static bool  g_check = false;
static float g_slider = 0.5f;
static int   g_diag_mmb = 0, g_diag_rmb = 0, g_diag_wheel = 0, g_diag_wantcap = 0;

static void RenderFrameNoPoll() {
    BeginDrawing();
    ClearBackground({ 24, 24, 28, 255 });

    int w = GetScreenWidth();
    int h = GetScreenHeight();

    // rotating hue ring in the 3D (raylib) layer — proves continuous animation
    g_hue = fmodf(g_hue + 0.005f, 1.0f);
    for (int i = 0; i < 12; i++) {
        float a0 = (i / 12.0f) * 2.0f * 3.14159265f + g_hue * 6.28318f;
        Vector2 c = { w * 0.5f, h * 0.5f };
        float r1 = (w < h ? w : h) * 0.28f, r2 = (w < h ? w : h) * 0.38f;
        DrawTriangle(
            { c.x + cosf(a0) * r1, c.y + sinf(a0) * r1 },
            { c.x + cosf(a0 + 0.4f) * r2, c.y + sinf(a0 + 0.4f) * r2 },
            { c.x + cosf(a0 - 0.4f) * r2, c.y + sinf(a0 - 0.4f) * r2 },
            ColorFromHSV(g_hue * 360, 0.7f, 0.9f));
    }
    // input diagnostics — sampled BEFORE the ImGui frame, like the template reads
    g_diag_mmb = IsMouseButtonDown(MOUSE_BUTTON_MIDDLE);
    g_diag_rmb = IsMouseButtonDown(MOUSE_BUTTON_RIGHT);
    g_diag_wheel = (int)GetMouseWheelMove();


    // ImGui frame
    rlImGuiBeginDelta(1.0f / 60.0f);
    ImGui::SetNextWindowPos({ 20, 20 }, ImGuiCond_Once);
    ImGui::SetNextWindowSize({ 360, 220 }, ImGuiCond_Once);
    ImGui::Begin("resize monitor");
    ImGui::Text("client: %dx%d", w, h);
    ImGui::Text("MMB:%d RMB:%d wheel:%d wantcap:%d", g_diag_mmb, g_diag_rmb, g_diag_wheel, g_diag_wantcap);
#ifdef _WIN32
    ImGui::Text("subclass renders: %d %s", g_subclass_renders, g_in_sizemove ? "(IN SIZEMOVE)" : "");
#else
    ImGui::Text("subclass renders: n/a");
#endif
    if (ImGui::Button("click me")) g_clicks++;
    ImGui::SameLine();
    ImGui::Text("clicks: %d", g_clicks);
    ImGui::SliderFloat("slider", &g_slider, 0.0f, 1.0f);
    ImGui::Checkbox("checkbox", &g_check);
    ImGui::ProgressBar(g_slider, { -1, 0 }, NULL);
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

int main() {
    SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT);
    InitWindow(1280, 800, "poc_imgui — raylib OGL3.3 + rlImGui smooth resize");
    SetTargetFPS(0);

    rlImGuiBeginInitImGui();
    ImGui::StyleColorsDark();
    rlImGuiEndInitImGui();

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
    rlImGuiShutdown();
    CloseWindow();
    return 0;
}
