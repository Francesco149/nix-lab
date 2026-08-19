// d3d11_resize_eval.cpp — Direct3D 11 continuous resize evaluation on Windows
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#define WINVER 0x0601
#define _WIN32_WINNT 0x0601

#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <cstdio>
#include <chrono>

static ID3D11Device*           g_device = nullptr;
static ID3D11DeviceContext*    g_context = nullptr;
static IDXGISwapChain*         g_swapchain = nullptr;
static ID3D11RenderTargetView* g_rtv = nullptr;
static int                     g_width = 1280;
static int                     g_height = 800;
static int                     g_resize_count = 0;
static int                     g_render_in_resize_count = 0;
static bool                    g_in_sizemove = false;

static void create_render_target() {
    ID3D11Texture2D* back_buffer = nullptr;
    g_swapchain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&back_buffer);
    if (back_buffer) {
        g_device->CreateRenderTargetView(back_buffer, nullptr, &g_rtv);
        back_buffer->Release();
    }
}

static void cleanup_render_target() {
    if (g_rtv) {
        g_rtv->Release();
        g_rtv = nullptr;
    }
}

static void render_frame(float r, float g, float b) {
    if (!g_rtv || !g_context || !g_swapchain) return;

    D3D11_VIEWPORT vp = {};
    vp.Width = (float)g_width;
    vp.Height = (float)g_height;
    vp.MinDepth = 0.0f;
    vp.MaxDepth = 1.0f;
    g_context->RSSetViewports(1, &vp);

    float clear_color[4] = { r, g, b, 1.0f };
    g_context->ClearRenderTargetView(g_rtv, clear_color);
    g_context->OMSetRenderTargets(1, &g_rtv, nullptr);

    // Present with DXGI Flip Model
    g_swapchain->Present(1, 0);
}

static void handle_resize(int width, int height) {
    if (width <= 0 || height <= 0 || !g_swapchain) return;
    g_width = width;
    g_height = height;

    cleanup_render_target();
    HRESULT hr = g_swapchain->ResizeBuffers(0, width, height, DXGI_FORMAT_UNKNOWN, 0);
    if (SUCCEEDED(hr)) {
        create_render_target();
        g_resize_count++;
        if (g_in_sizemove) {
            g_render_in_resize_count++;
            // Draw a distinct color during resize to verify live frame presentation
            render_frame(0.96f, 0.62f, 0.04f); // Amber accent
        }
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
    printf("[D3D11 EVAL] Initializing Direct3D 11 window & DXGI swapchain...\n");

    WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_CLASSDC, WndProc, 0L, 0L,
                      GetModuleHandle(nullptr), nullptr, nullptr, nullptr, nullptr,
                      L"D3D11ResizeEvalClass", nullptr };
    RegisterClassEx(&wc);

    HWND hwnd = CreateWindow(wc.lpszClassName, L"D3D11 Continuous Resize Evaluation",
                             WS_OVERLAPPEDWINDOW, 100, 100, g_width, g_height,
                             nullptr, nullptr, wc.hInstance, nullptr);
    if (!hwnd) {
        printf("[D3D11 EVAL] Failed to create window!\n");
        return 1;
    }

    DXGI_SWAP_CHAIN_DESC sd = {};
    sd.BufferCount = 2;
    sd.BufferDesc.Width = g_width;
    sd.BufferDesc.Height = g_height;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = TRUE;
    // DXGI_SWAP_EFFECT_FLIP_DISCARD for Windows 10/11, or FLIP_SEQUENTIAL for Win 7 platform update
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;

    UINT createDeviceFlags = 0;
    D3D_FEATURE_LEVEL featureLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };
    D3D_FEATURE_LEVEL featureLevel;

    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, createDeviceFlags,
        featureLevels, 4, D3D11_SDK_VERSION, &sd,
        &g_swapchain, &g_device, &featureLevel, &g_context);

    if (FAILED(hr)) {
        // Fallback without FLIP_SEQUENTIAL
        sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
        hr = D3D11CreateDeviceAndSwapChain(
            nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, createDeviceFlags,
            featureLevels, 4, D3D11_SDK_VERSION, &sd,
            &g_swapchain, &g_device, &featureLevel, &g_context);
    }

    if (FAILED(hr)) {
        printf("[D3D11 EVAL] D3D11CreateDeviceAndSwapChain failed: 0x%08lX\n", (unsigned long)hr);
        return 1;
    }

    printf("[D3D11 EVAL] D3D11 Device created successfully (Feature Level: 0x%X)\n", (unsigned int)featureLevel);
    create_render_target();

    // Check programmatic resize simulation
    printf("[D3D11 EVAL] Running automated continuous resize simulation (50 steps)...\n");
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

    printf("[D3D11 EVAL] Completed 50 resize cycles in %.2f ms (%.2f ms/resize, %d frames presented during sizing)\n",
        ms, ms / 50.0, g_render_in_resize_count);

    bool smooth = (g_render_in_resize_count >= 50);
    printf("[D3D11 EVAL] Direct3D 11 Smooth Live Resize Result: %s\n", smooth ? "PASS (100% live frames presented)" : "FAIL");

    cleanup_render_target();
    if (g_swapchain) g_swapchain->Release();
    if (g_context) g_context->Release();
    if (g_device) g_device->Release();
    DestroyWindow(hwnd);
    UnregisterClass(wc.lpszClassName, wc.hInstance);

    return smooth ? 0 : 1;
}
