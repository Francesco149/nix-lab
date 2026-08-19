// poc_min.cpp — OpenGL 3.3 (raylib) smooth-resize proof of concept for Windows.
//
// Problem: during a Win32 drag-resize, DefWindowProc runs a modal loop on the
// GUI thread; no frames are presented and DWM stretches the stale backbuffer.
// Fix: subclass the GLFW window and present a re-rendered frame from inside
// the modal loop on every WM_SIZE.
//
// Crash-safety rules (why previous attempts crashed):
//  1. NEVER call EndDrawing() re-entrantly — it calls glfwPollEvents(), and a
//     nested poll from window-proc context corrupts GLFW's event queue and
//     raylib's input state. Instead: rlDrawRenderBatchActive() + SwapBuffers.
//  2. The modal loop runs on the main thread, entered from the outer frame's
//     poll (which happens AFTER the outer swap), so GL state is at a frame
//     boundary — but keep a re-entrancy latch anyway (SendMessage recursion).
//  3. Call the original (GLFW) wndproc FIRST so raylib's GLFW size callback
//     updates CORE.Window sizes before we re-render.
//
// NOTE: windows.h is deliberately NOT included — raylib.h and wingdi/winuser
// collide on Rectangle / CloseWindow / ShowCursor / DrawText. We declare the
// handful of Win32 imports we need directly.

#include "raylib.h"
#include "rlgl.h"

#include <cstdio>
#include <cstring>

#ifdef _WIN32

extern "C" {
__declspec(dllimport) void*   __stdcall wglGetCurrentDC(void);
__declspec(dllimport) int     __stdcall SwapBuffers(void* hdc);
__declspec(dllimport) void*   __stdcall GetWindowLongPtrW(void* hwnd, int index);
__declspec(dllimport) long long __stdcall SetWindowLongPtrW(void* hwnd, int index, long long value);
__declspec(dllimport) long long __stdcall CallWindowProcW(long long proc, void* hwnd,
                                                          unsigned msg, unsigned long long wp, long long lp);
}

#define POC_GWLP_WNDPROC    (-4)
#define POC_WM_SIZE         0x0005u
#define POC_WM_ENTERSIZEMOVE 0x0231u
#define POC_WM_EXITSIZEMOVE  0x0232u
#define POC_SIZE_MINIMIZED  1ull

typedef long long (*PocWndProc)(void*, unsigned, unsigned long long, long long);

static PocWndProc g_orig_proc = nullptr;
static bool       g_rendering = false;      // re-entrancy latch (same thread)
static bool       g_in_sizemove = false;
static int        g_subclass_renders = 0;   // instrumentation

static void RenderFrameNoPoll() {
    // Full re-render, but skip EndDrawing's SwapBuffers+PollInputEvents.
    BeginDrawing();
    {
        ClearBackground({ 24, 24, 28, 255 });

        int w = GetScreenWidth();
        int h = GetScreenHeight();

        // Content that makes stretching obvious: border at exact window edge
        // + centered text reporting the live size + diagonals that MUST hit
        // the corners. If any of these are off during/after resize, the fix
        // regressed.
        DrawRectangleLinesEx({ 8, 8, (float)w - 16, (float)h - 16 }, 4.0f, { 240, 180, 40, 255 });
        DrawLine(8, 8, w - 8, h - 8, { 80, 200, 255, 255 });
        DrawLine(w - 8, 8, 8, h - 8, { 80, 200, 255, 255 });

        const char* txt = TextFormat("%dx%d  subclass-renders: %d", w, h, g_subclass_renders);
        int tw = MeasureText(txt, 30);
        DrawText(txt, (w - tw) / 2, h / 2 - 15, 30, { 235, 235, 245, 255 });
    }
    rlDrawRenderBatchActive();          // flush raylib's batch
    SwapBuffers(wglGetCurrentDC());     // present WITHOUT polling events
    // NOTE: viewport/projection for the new size is applied by raylib inside
    // BeginDrawing on the next call — verified empirically by this PoC.
}

static long long __stdcall ResizeSubclassProc(void* hwnd, unsigned msg,
                                              unsigned long long wp, long long lp) {
    if (msg == POC_WM_ENTERSIZEMOVE) g_in_sizemove = true;
    if (msg == POC_WM_EXITSIZEMOVE)  g_in_sizemove = false;

    // Let GLFW's proc run first (updates raylib's screen size on WM_SIZE).
    long long res = CallWindowProcW((long long)g_orig_proc, hwnd, msg, wp, lp);

    if (msg == POC_WM_SIZE && wp != POC_SIZE_MINIMIZED && g_in_sizemove) {
        if (!g_rendering) {           // latch: no recursive rendering
            g_rendering = true;
            g_subclass_renders++;
            RenderFrameNoPoll();
            g_rendering = false;
        }
    }
    return res;
}
#endif // _WIN32

int main() {
    SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT);
    InitWindow(1280, 800, "poc_min — raylib OGL3.3 smooth resize");
    SetTargetFPS(0); // vsync

#ifdef _WIN32
    void* hwnd = GetWindowHandle();
    g_orig_proc = (PocWndProc)GetWindowLongPtrW(hwnd, POC_GWLP_WNDPROC);
    SetWindowLongPtrW(hwnd, POC_GWLP_WNDPROC, (long long)ResizeSubclassProc);
    printf("subclass installed: hwnd=%p orig=%p\n", hwnd, (void*)g_orig_proc);
#endif

    while (!WindowShouldClose()) {
#ifdef _WIN32
        RenderFrameNoPoll(); // main loop uses the same no-poll path
        PollInputEvents();   // then poll once, top-level only
#else
        BeginDrawing();
        ClearBackground(RAYWHITE);
        DrawText("PoC is Windows-only", 40, 40, 30, BLACK);
        EndDrawing();
#endif
    }

#ifdef _WIN32
    SetWindowLongPtrW(hwnd, POC_GWLP_WNDPROC, (long long)g_orig_proc);
#endif
    CloseWindow();
    return 0;
}
