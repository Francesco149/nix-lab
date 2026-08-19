// wgl_resize_eval.cpp — OpenGL (WGL) continuous resize evaluation on Windows
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#define WINVER 0x0601
#define _WIN32_WINNT 0x0601

#include <windows.h>
#include <GL/gl.h>
#include <cstdio>
#include <chrono>

static HDC   g_hdc = nullptr;
static HGLRC g_hglrc = nullptr;
static int   g_width = 1280;
static int   g_height = 800;
static int   g_resize_count = 0;
static int   g_render_in_resize_count = 0;
static bool  g_in_sizemove = false;

static void render_frame(float r, float g, float b) {
    if (!g_hdc || !g_hglrc) return;
    wglMakeCurrent(g_hdc, g_hglrc);
    glViewport(0, 0, g_width, g_height);
    glClearColor(r, g, b, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    SwapBuffers(g_hdc);
}

static void handle_resize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    g_width = width;
    g_height = height;
    g_resize_count++;
    if (g_in_sizemove) {
        g_render_in_resize_count++;
        render_frame(0.96f, 0.62f, 0.04f);
    }
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_ENTERSIZEMOVE:
            g_in_sizemove = true;
            return 0;

        case WM_EXITSIZEMOVE:
            g_in_sizemove = false;
            render_frame(0.09f, 0.09f, 0.11f);
            return 0;

        case WM_SIZE:
            if (wParam != SIZE_MINIMIZED) {
                handle_resize(LOWORD(lParam), HIWORD(lParam));
            }
            return 0;

        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(hwnd, &ps);
            render_frame(0.09f, 0.09f, 0.11f);
            EndPaint(hwnd, &ps);
            return 0;
        }

        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

int main(int argc, char** argv) {
    printf("[WGL EVAL] Initializing OpenGL (WGL) window...\n");

    WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_CLASSDC | CS_OWNDC, WndProc, 0L, 0L,
                      GetModuleHandle(nullptr), nullptr, nullptr, nullptr, nullptr,
                      L"WGLResizeEvalClass", nullptr };
    RegisterClassEx(&wc);

    HWND hwnd = CreateWindow(wc.lpszClassName, L"OpenGL WGL Continuous Resize Evaluation",
                             WS_OVERLAPPEDWINDOW, 100, 100, g_width, g_height,
                             nullptr, nullptr, wc.hInstance, nullptr);
    if (!hwnd) {
        printf("[WGL EVAL] Failed to create window!\n");
        return 1;
    }

    g_hdc = GetDC(hwnd);
    PIXELFORMATDESCRIPTOR pfd = {};
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.iLayerType = PFD_MAIN_PLANE;

    int format = ChoosePixelFormat(g_hdc, &pfd);
    SetPixelFormat(g_hdc, format, &pfd);

    g_hglrc = wglCreateContext(g_hdc);
    if (!g_hglrc) {
        printf("[WGL EVAL] wglCreateContext failed!\n");
        return 1;
    }
    wglMakeCurrent(g_hdc, g_hglrc);

    printf("[WGL EVAL] WGL Context created successfully\n");

    // Check programmatic resize simulation
    printf("[WGL EVAL] Running automated continuous resize simulation (50 steps)...\n");
    auto t0 = std::chrono::high_resolution_clock::now();
    g_in_sizemove = true;

    for (int i = 0; i < 50; i++) {
        int target_w = 800 + (i * 12);
        int target_h = 600 + (i * 6);
        SetWindowPos(hwnd, nullptr, 100, 100, target_w, target_h, SWP_NOZORDER | SWP_NOACTIVATE);
        // Dispatch window messages
        MSG msg;
        while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }
    g_in_sizemove = false;
    auto t1 = std::chrono::high_resolution_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    printf("[WGL EVAL] Completed 50 resize cycles in %.2f ms (%.2f ms/resize, %d frames presented during sizing)\n",
        ms, ms / 50.0, g_render_in_resize_count);

    wglMakeCurrent(nullptr, nullptr);
    if (g_hglrc) wglDeleteContext(g_hglrc);
    if (g_hdc) ReleaseDC(hwnd, g_hdc);
    DestroyWindow(hwnd);
    UnregisterClass(wc.lpszClassName, wc.hInstance);

    return 0;
}
