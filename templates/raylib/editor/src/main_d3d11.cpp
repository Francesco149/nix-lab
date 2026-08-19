// main_d3d11.cpp — Native Direct3D 11 engine for CubeForge (Windows)
// Pure Direct3D 11 + DXGI Flip Model + ImGui DX11/Win32 + Lua 5.4.
// Delivers smooth continuous 60fps window resize during live dragging with zero stretching.

#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#define WINVER 0x0601
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <mmsystem.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <d3dcompiler.h>
#include <direct.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <string>
#include <chrono>
#include <algorithm>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#define STB_PERLIN_IMPLEMENTATION
#include "stb_perlin.h"
#include "app_paths.h"
#include "editor_theme.h"
#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

#include "editor.h"

extern "C" const char* win_clipboard_file_path(void);
extern "C" const char* win_clipboard_text(void);
extern "C" const char* win_open_file_dialog(void);
extern "C" void win_get_workarea(int* out_w, int* out_h);

extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

// ── Math & Vector Types ─────────────────────────────────────────────────────
struct Vec2 { float x, y; };
struct Vec3 { float x, y, z; };
struct Vec4 { float x, y, z, w; };
struct Mat4 { float m[16]; };

static inline Vec3 v3(float x, float y, float z) { return { x, y, z }; }
static inline Vec4 v4(float x, float y, float z, float w) { return { x, y, z, w }; }

static inline Vec3 v3_add(Vec3 a, Vec3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
static inline Vec3 v3_sub(Vec3 a, Vec3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
static inline Vec3 v3_scale(Vec3 v, float s) { return { v.x * s, v.y * s, v.z * s }; }
static inline float v3_dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline Vec3 v3_cross(Vec3 a, Vec3 b) {
    return { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x };
}
static inline float v3_len(Vec3 v) { return std::sqrt(v3_dot(v, v)); }
static inline Vec3 v3_norm(Vec3 v) {
    float l = v3_len(v);
    return l > 1e-6f ? v3_scale(v, 1.0f / l) : v3(0, 0, 0);
}

static Mat4 mat4_identity() {
    Mat4 r = {};
    r.m[0] = r.m[5] = r.m[10] = r.m[15] = 1.0f;
    return r;
}

static Mat4 mat4_mul(const Mat4& a, const Mat4& b) {
    Mat4 r = {};
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            r.m[i * 4 + j] = a.m[i * 4 + 0] * b.m[0 * 4 + j] +
                             a.m[i * 4 + 1] * b.m[1 * 4 + j] +
                             a.m[i * 4 + 2] * b.m[2 * 4 + j] +
                             a.m[i * 4 + 3] * b.m[3 * 4 + j];
        }
    }
    return r;
}

static Mat4 mat4_perspective(float fovy_deg, float aspect, float near_z, float far_z) {
    Mat4 r = {};
    float rad = fovy_deg * (3.14159265358979323846f / 180.0f);
    float tan_half = std::tan(rad * 0.5f);
    r.m[0] = 1.0f / (aspect * tan_half);
    r.m[5] = 1.0f / tan_half;
    r.m[10] = far_z / (near_z - far_z);
    r.m[11] = -1.0f;
    r.m[14] = (near_z * far_z) / (near_z - far_z);
    return r;
}

static Mat4 mat4_ortho(float left, float right, float bottom, float top, float near_z, float far_z) {
    Mat4 r = {};
    r.m[0] = 2.0f / (right - left);
    r.m[5] = 2.0f / (top - bottom);
    r.m[10] = 1.0f / (far_z - near_z);
    r.m[12] = -(right + left) / (right - left);
    r.m[13] = -(top + bottom) / (top - bottom);
    r.m[14] = -near_z / (far_z - near_z);
    r.m[15] = 1.0f;
    return r;
}

static Mat4 mat4_look_at(Vec3 eye, Vec3 target, Vec3 up) {
    Vec3 zaxis = v3_norm(v3_sub(eye, target));
    Vec3 xaxis = v3_norm(v3_cross(up, zaxis));
    Vec3 yaxis = v3_cross(zaxis, xaxis);

    Mat4 r = mat4_identity();
    r.m[0] = xaxis.x; r.m[1] = yaxis.x; r.m[2] = zaxis.x;
    r.m[4] = xaxis.y; r.m[5] = yaxis.y; r.m[6] = zaxis.y;
    r.m[8] = xaxis.z; r.m[9] = yaxis.z; r.m[10] = zaxis.z;
    r.m[12] = -v3_dot(xaxis, eye);
    r.m[13] = -v3_dot(yaxis, eye);
    r.m[14] = -v3_dot(zaxis, eye);
    return r;
}

// Invert 4x4 matrix
static bool mat4_invert(const Mat4& mat, Mat4& out) {
    const float* m = mat.m;
    float inv[16];

    inv[0] = m[5]  * m[10] * m[15] - m[5]  * m[11] * m[14] - m[9]  * m[6]  * m[15] +
             m[9]  * m[7]  * m[14] + m[13] * m[6]  * m[11] - m[13] * m[7]  * m[10];

    inv[4] = -m[4]  * m[10] * m[15] + m[4]  * m[11] * m[14] + m[8]  * m[6]  * m[15] -
              m[8]  * m[7]  * m[14] - m[12] * m[6]  * m[11] + m[12] * m[7]  * m[10];

    inv[8] = m[4]  * m[9]  * m[15] - m[4]  * m[11] * m[13] - m[8]  * m[5]  * m[15] +
             m[8]  * m[7]  * m[13] + m[12] * m[5]  * m[11] - m[12] * m[7]  * m[9];

    inv[12] = -m[4]  * m[9]  * m[14] + m[4]  * m[10] * m[13] + m[8]  * m[5]  * m[14] -
               m[8]  * m[6]  * m[13] - m[12] * m[5]  * m[10] + m[12] * m[6]  * m[9];

    inv[1] = -m[1]  * m[10] * m[15] + m[1]  * m[11] * m[14] + m[9]  * m[2]  * m[15] -
              m[9]  * m[3]  * m[14] - m[13] * m[2]  * m[11] + m[13] * m[3]  * m[10];

    inv[5] = m[0]  * m[10] * m[15] - m[0]  * m[11] * m[14] - m[8]  * m[2]  * m[15] +
             m[8]  * m[3]  * m[14] + m[12] * m[2]  * m[11] - m[12] * m[3]  * m[10];

    inv[9] = -m[0]  * m[9]  * m[15] + m[0]  * m[11] * m[13] + m[8]  * m[1]  * m[15] -
              m[8]  * m[3]  * m[13] - m[12] * m[1]  * m[11] + m[12] * m[3]  * m[9];

    inv[13] = m[0]  * m[9]  * m[14] - m[0]  * m[10] * m[13] - m[8]  * m[1]  * m[14] +
              m[8]  * m[2]  * m[13] + m[12] * m[1]  * m[10] - m[12] * m[2]  * m[9];

    inv[2] = m[1]  * m[6]  * m[15] - m[1]  * m[7]  * m[14] - m[5]  * m[2]  * m[15] +
             m[5]  * m[3]  * m[14] + m[13] * m[2]  * m[7]  - m[13] * m[3]  * m[6];

    inv[6] = -m[0]  * m[6]  * m[15] + m[0]  * m[7]  * m[14] + m[4]  * m[2]  * m[15] -
              m[4]  * m[3]  * m[14] - m[12] * m[2]  * m[7]  + m[12] * m[3]  * m[6];

    inv[10] = m[0]  * m[5]  * m[15] - m[0]  * m[7]  * m[13] - m[4]  * m[1]  * m[15] +
              m[4]  * m[3]  * m[13] + m[12] * m[1]  * m[7]  - m[12] * m[3]  * m[5];

    inv[14] = -m[0]  * m[5]  * m[14] + m[0]  * m[6]  * m[13] + m[4]  * m[1]  * m[14] -
               m[4]  * m[2]  * m[13] - m[12] * m[1]  * m[6]  + m[12] * m[2]  * m[5];

    inv[3] = -m[1]  * m[6]  * m[11] + m[1]  * m[7]  * m[10] + m[5]  * m[2]  * m[11] -
              m[5]  * m[3]  * m[10] - m[9]  * m[2]  * m[7]  + m[9]  * m[3]  * m[6];

    inv[7] = m[0]  * m[6]  * m[11] - m[0]  * m[7]  * m[10] - m[4]  * m[2]  * m[11] +
             m[4]  * m[3]  * m[10] + m[8]  * m[2]  * m[7]  - m[8]  * m[3]  * m[6];

    inv[11] = -m[0]  * m[5]  * m[11] + m[0]  * m[7]  * m[9]  + m[4]  * m[1]  * m[11] -
               m[4]  * m[3]  * m[9]  - m[8]  * m[1]  * m[7]  + m[8]  * m[3]  * m[5];

    inv[15] = m[0]  * m[5]  * m[10] - m[0]  * m[6]  * m[9]  - m[4]  * m[1]  * m[10] +
              m[4]  * m[2]  * m[9]  + m[8]  * m[1]  * m[6]  - m[8]  * m[2]  * m[5];

    float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
    if (std::abs(det) < 1e-8f) return false;

    float inv_det = 1.0f / det;
    for (int i = 0; i < 16; i++) out.m[i] = inv[i] * inv_det;
    return true;
}

static Vec4 mat4_mul_vec4(const Mat4& mat, Vec4 v) {
    return {
        mat.m[0] * v.x + mat.m[4] * v.y + mat.m[8]  * v.z + mat.m[12] * v.w,
        mat.m[1] * v.x + mat.m[5] * v.y + mat.m[9]  * v.z + mat.m[13] * v.w,
        mat.m[2] * v.x + mat.m[6] * v.y + mat.m[10] * v.z + mat.m[14] * v.w,
        mat.m[3] * v.x + mat.m[7] * v.y + mat.m[11] * v.z + mat.m[15] * v.w,
    };
}

// ── Camera State ────────────────────────────────────────────────────────────
struct Camera3DState {
    Vec3 position = { 5.0f, 5.0f, 5.0f };
    Vec3 target   = { 0.0f, 0.0f, 0.0f };
    Vec3 up       = { 0.0f, 1.0f, 0.0f };
    float fovy    = 60.0f;
};
static Camera3DState g_camera;

struct Camera2DState {
    Vec2 offset   = { 0.0f, 0.0f };
    Vec2 target   = { 0.0f, 0.0f };
    float rotation = 0.0f;
    float zoom     = 1.0f;
};
static Camera2DState g_cam2d;
static bool g_in_mode2d = false;

// ── Direct3D 11 Globals ─────────────────────────────────────────────────────
static HWND                     g_hwnd = nullptr;
static ID3D11Device*            g_d3d_device = nullptr;
static ID3D11DeviceContext*     g_d3d_context = nullptr;
static IDXGISwapChain*          g_swapchain = nullptr;
static ID3D11RenderTargetView*  g_main_rtv = nullptr;
static ID3D11Texture2D*         g_depth_stencil_tex = nullptr;
static ID3D11DepthStencilView*  g_depth_stencil_view = nullptr;
static ID3D11DepthStencilState* g_depth_state_3d = nullptr;
static ID3D11DepthStencilState* g_depth_state_2d = nullptr;
static ID3D11DepthStencilState* g_depth_state_overlay = nullptr;
static ID3D11RasterizerState*   g_raster_solid = nullptr;
static ID3D11RasterizerState*   g_raster_wire = nullptr;
static ID3D11BlendState*        g_blend_state = nullptr;
static ID3D11SamplerState*      g_sampler_state = nullptr;
static bool                     g_lighting_enabled = false;
static ID3D11VertexShader*      g_vs_3d = nullptr;
static ID3D11PixelShader*       g_ps_3d = nullptr;
static ID3D11InputLayout*       g_layout_3d = nullptr;
static ID3D11Buffer*            g_cbuffer_scene = nullptr;

static ID3D11VertexShader*      g_vs_unlit = nullptr;
static ID3D11PixelShader*       g_ps_unlit = nullptr;
static ID3D11InputLayout*       g_layout_unlit = nullptr;

static ID3D11Buffer*            g_dynamic_vb = nullptr;
static size_t                   g_dynamic_vb_capacity = 0;

static int                      g_win_w = 1280;
static int                      g_win_h = 800;
static bool                     g_in_render = false;
static bool                     g_in_sizemove = false;
static double                   g_last_frame_time = 0.016;
static int                      g_target_fps = 0; // 0 = VSync (240Hz default)

// ── D3D11 Vertex Struct ─────────────────────────────────────────────────────
struct D3DVertex {
    float x, y, z;
    float r, g, b, a;
    float nx, ny, nz;
    float u, v;
};

struct SceneCBuffer {
    Mat4  mvp;
    Mat4  model;
    Vec4  ambient;
    Vec4  sun_dir;
    Vec4  sun_color;
    Vec4  color_tint;
    int   use_texture;
    int   pad[3];
};

// ── D3D11 Texture & Model Registries ────────────────────────────────────────
struct D3DTexture {
    ID3D11Texture2D*          tex = nullptr;
    ID3D11ShaderResourceView* srv = nullptr;
    int                       width = 0;
    int                       height = 0;
};

struct D3DModel {
    ID3D11Buffer* vb = nullptr;
    ID3D11Buffer* ib = nullptr;
    int           vertex_count = 0;
    int           index_count = 0;
    int           texture_id = -1; // -1 = untextured / white
    Vec4          tint = { 1, 1, 1, 1 };
};

static std::vector<D3DTexture> g_textures;
static std::vector<D3DModel>   g_models;

static int register_texture(ID3D11Texture2D* tex, ID3D11ShaderResourceView* srv, int w, int h) {
    g_textures.push_back({ tex, srv, w, h });
    return (int)g_textures.size(); // 1-indexed
}

// ── Input State & Virtual Drive ─────────────────────────────────────────────
static bool g_keys_down[512] = {};
static bool g_keys_pressed[512] = {};
static bool g_mouse_down[3] = {};
static bool g_mouse_pressed[3] = {};
static float g_mouse_x = 0, g_mouse_y = 0;
static float g_mouse_dx = 0, g_mouse_dy = 0;
static float g_mouse_wheel = 0;

static bool  g_drive_active = false;
static float g_drive_mx = 0, g_drive_my = 0;
static float g_drive_px = 0, g_drive_py = 0;
static bool  g_drive_btn[3] = {};
static bool  g_drive_btn_pressed[3] = {};
static float g_drive_wheel = 0;
static bool  g_drive_key_down[512] = {};
static bool  g_drive_key_pressed[512] = {};
static std::string g_dropped_file = "";

// ── Forward Declarations ────────────────────────────────────────────────────
static void d3d11_handle_resize(int width, int height);
static void app_render_frame();
static void app_init_d3d_pipeline();


// ── Lua VM State ────────────────────────────────────────────────────────────
static lua_State* L_global = nullptr;
static char lua_dir[2048] = {};

void app_log(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
}

lua_State* lua_state() { return L_global; }

extern "C" void* GetWindowHandle(void) { return (void*)g_hwnd; }
extern "C" void app_on_live_resize(void) { app_render_frame(); }

static void lp_call_global(const char* name) {
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

// ── Dynamic Mesh Batching ───────────────────────────────────────────────────
static std::vector<D3DVertex> g_dynamic_verts;

static void ensure_dynamic_vb(size_t vertex_count) {
    if (vertex_count <= g_dynamic_vb_capacity && g_dynamic_vb) return;
    if (g_dynamic_vb) g_dynamic_vb->Release();

    g_dynamic_vb_capacity = std::max(vertex_count, (size_t)8192);
    D3D11_BUFFER_DESC desc = {};
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.ByteWidth = (UINT)(g_dynamic_vb_capacity * sizeof(D3DVertex));
    desc.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    g_d3d_device->CreateBuffer(&desc, nullptr, &g_dynamic_vb);
}

static void draw_dynamic_triangles(const D3DVertex* verts, size_t count, int tex_id = -1, Vec4 tint = { 1, 1, 1, 1 }) {
    if (count == 0 || !g_d3d_context) return;
    ensure_dynamic_vb(count);

    D3D11_MAPPED_SUBRESOURCE mapped;
    if (SUCCEEDED(g_d3d_context->Map(g_dynamic_vb, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
        memcpy(mapped.pData, verts, count * sizeof(D3DVertex));
        g_d3d_context->Unmap(g_dynamic_vb, 0);
    }

    // Set constant buffer
    Mat4 view = mat4_look_at(g_camera.position, g_camera.target, g_camera.up);
    Mat4 proj = mat4_perspective(g_camera.fovy, g_win_w / (float)std::max(1, g_win_h), 0.1f, 1000.0f);
    Mat4 mvp = mat4_mul(view, proj);

    SceneCBuffer cb = {};
    cb.mvp = mvp;
    cb.model = mat4_identity();
    if (g_lighting_enabled) {
        cb.ambient = v4(0.35f, 0.35f, 0.38f, 1.0f);
        cb.sun_dir = v4(-0.4f, -1.0f, -0.6f, 0.0f);
        cb.sun_color = v4(0.9f, 0.88f, 0.82f, 1.0f);
    } else {
        cb.ambient = v4(1.0f, 1.0f, 1.0f, 1.0f);
        cb.sun_dir = v4(0.0f, 0.0f, 0.0f, 0.0f);
        cb.sun_color = v4(0.0f, 0.0f, 0.0f, 1.0f);
    }
    cb.use_texture = (tex_id > 0 && tex_id <= (int)g_textures.size() && g_textures[tex_id - 1].srv != nullptr) ? 1 : 0;

    g_d3d_context->UpdateSubresource(g_cbuffer_scene, 0, nullptr, &cb, 0, 0);

    if (cb.use_texture) {
        ID3D11ShaderResourceView* srv = g_textures[tex_id - 1].srv;
        g_d3d_context->PSSetShaderResources(0, 1, &srv);
    }

    UINT stride = sizeof(D3DVertex);
    UINT offset = 0;
    g_d3d_context->IASetVertexBuffers(0, 1, &g_dynamic_vb, &stride, &offset);
    g_d3d_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_d3d_context->IASetInputLayout(g_layout_3d);
    g_d3d_context->VSSetShader(g_vs_3d, nullptr, 0);
    g_d3d_context->VSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetShader(g_ps_3d, nullptr, 0);
    g_d3d_context->PSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetSamplers(0, 1, &g_sampler_state);

    g_d3d_context->RSSetState(g_raster_solid);
    g_d3d_context->OMSetDepthStencilState(g_depth_state_3d, 0);
    g_d3d_context->OMSetBlendState(g_blend_state, nullptr, 0xffffffff);

    g_d3d_context->Draw((UINT)count, 0);
}

static void draw_dynamic_lines(const D3DVertex* verts, size_t count) {
    if (count == 0 || !g_d3d_context) return;
    ensure_dynamic_vb(count);

    D3D11_MAPPED_SUBRESOURCE mapped;
    if (SUCCEEDED(g_d3d_context->Map(g_dynamic_vb, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
        memcpy(mapped.pData, verts, count * sizeof(D3DVertex));
        g_d3d_context->Unmap(g_dynamic_vb, 0);
    }

    Mat4 view = mat4_look_at(g_camera.position, g_camera.target, g_camera.up);
    Mat4 proj = mat4_perspective(g_camera.fovy, g_win_w / (float)std::max(1, g_win_h), 0.1f, 1000.0f);
    Mat4 mvp = mat4_mul(view, proj);

    SceneCBuffer cb = {};
    cb.mvp = mvp;
    cb.model = mat4_identity();
    cb.color_tint = v4(1, 1, 1, 1);
    g_d3d_context->UpdateSubresource(g_cbuffer_scene, 0, nullptr, &cb, 0, 0);

    UINT stride = sizeof(D3DVertex);
    UINT offset = 0;
    g_d3d_context->IASetVertexBuffers(0, 1, &g_dynamic_vb, &stride, &offset);
    g_d3d_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_LINELIST);
    g_d3d_context->IASetInputLayout(g_layout_unlit);
    g_d3d_context->VSSetShader(g_vs_unlit, nullptr, 0);
    g_d3d_context->VSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetShader(g_ps_unlit, nullptr, 0);

    g_d3d_context->RSSetState(g_raster_solid);
    g_d3d_context->OMSetDepthStencilState(g_depth_state_3d, 0);
    g_d3d_context->OMSetBlendState(g_blend_state, nullptr, 0xffffffff);

    g_d3d_context->Draw((UINT)count, 0);
}

static void draw_dynamic_triangles_unlit(const D3DVertex* verts, size_t count, Vec4 tint = { 1, 1, 1, 1 }) {
    if (count == 0 || !g_d3d_context) return;
    ensure_dynamic_vb(count);

    D3D11_MAPPED_SUBRESOURCE mapped;
    if (SUCCEEDED(g_d3d_context->Map(g_dynamic_vb, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
        memcpy(mapped.pData, verts, count * sizeof(D3DVertex));
        g_d3d_context->Unmap(g_dynamic_vb, 0);
    }

    Mat4 view = mat4_look_at(g_camera.position, g_camera.target, g_camera.up);
    Mat4 proj = mat4_perspective(g_camera.fovy, g_win_w / (float)std::max(1, g_win_h), 0.1f, 1000.0f);
    Mat4 mvp = mat4_mul(view, proj);

    SceneCBuffer cb = {};
    cb.mvp = mvp;
    cb.model = mat4_identity();
    cb.color_tint = tint;
    g_d3d_context->UpdateSubresource(g_cbuffer_scene, 0, nullptr, &cb, 0, 0);

    UINT stride = sizeof(D3DVertex);
    UINT offset = 0;
    g_d3d_context->IASetVertexBuffers(0, 1, &g_dynamic_vb, &stride, &offset);
    g_d3d_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_d3d_context->IASetInputLayout(g_layout_unlit);
    g_d3d_context->VSSetShader(g_vs_unlit, nullptr, 0);
    g_d3d_context->VSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetShader(g_ps_unlit, nullptr, 0);

    g_d3d_context->RSSetState(g_raster_solid);
    g_d3d_context->OMSetDepthStencilState(g_depth_state_overlay, 0);
    g_d3d_context->OMSetBlendState(g_blend_state, nullptr, 0xffffffff);

    g_d3d_context->Draw((UINT)count, 0);
}

static void draw_dynamic_triangles_2d(const D3DVertex* verts, size_t count, int tex_id = -1, Vec4 tint = { 1, 1, 1, 1 }) {
    if (count == 0 || !g_d3d_context) return;
    ensure_dynamic_vb(count);

    D3D11_MAPPED_SUBRESOURCE mapped;
    if (SUCCEEDED(g_d3d_context->Map(g_dynamic_vb, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
        memcpy(mapped.pData, verts, count * sizeof(D3DVertex));
        g_d3d_context->Unmap(g_dynamic_vb, 0);
    }

    SceneCBuffer cb = {};
    cb.mvp = mat4_identity();
    cb.model = mat4_identity();
    cb.ambient = v4(1, 1, 1, 1);
    cb.color_tint = tint;
    cb.use_texture = (tex_id > 0 && tex_id <= (int)g_textures.size() && g_textures[tex_id - 1].srv != nullptr) ? 1 : 0;
    g_d3d_context->UpdateSubresource(g_cbuffer_scene, 0, nullptr, &cb, 0, 0);

    if (cb.use_texture) {
        ID3D11ShaderResourceView* srv = g_textures[tex_id - 1].srv;
        g_d3d_context->PSSetShaderResources(0, 1, &srv);
        g_d3d_context->PSSetSamplers(0, 1, &g_sampler_state);
        g_d3d_context->VSSetShader(g_vs_3d, nullptr, 0);
        g_d3d_context->PSSetShader(g_ps_3d, nullptr, 0);
        g_d3d_context->IASetInputLayout(g_layout_3d);
    } else {
        g_d3d_context->VSSetShader(g_vs_unlit, nullptr, 0);
        g_d3d_context->PSSetShader(g_ps_unlit, nullptr, 0);
        g_d3d_context->IASetInputLayout(g_layout_unlit);
    }

    UINT stride = sizeof(D3DVertex);
    UINT offset = 0;
    g_d3d_context->IASetVertexBuffers(0, 1, &g_dynamic_vb, &stride, &offset);
    g_d3d_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_d3d_context->VSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetConstantBuffers(0, 1, &g_cbuffer_scene);

    g_d3d_context->RSSetState(g_raster_solid);
    g_d3d_context->OMSetDepthStencilState(g_depth_state_2d, 0);
    g_d3d_context->OMSetBlendState(g_blend_state, nullptr, 0xffffffff);

    g_d3d_context->Draw((UINT)count, 0);
}

static void draw_dynamic_lines_2d(const D3DVertex* verts, size_t count) {
    if (count == 0 || !g_d3d_context) return;
    ensure_dynamic_vb(count);

    D3D11_MAPPED_SUBRESOURCE mapped;
    if (SUCCEEDED(g_d3d_context->Map(g_dynamic_vb, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
        memcpy(mapped.pData, verts, count * sizeof(D3DVertex));
        g_d3d_context->Unmap(g_dynamic_vb, 0);
    }

    SceneCBuffer cb = {};
    cb.mvp = mat4_identity();
    cb.model = mat4_identity();
    cb.color_tint = v4(1, 1, 1, 1);
    g_d3d_context->UpdateSubresource(g_cbuffer_scene, 0, nullptr, &cb, 0, 0);

    UINT stride = sizeof(D3DVertex);
    UINT offset = 0;
    g_d3d_context->IASetVertexBuffers(0, 1, &g_dynamic_vb, &stride, &offset);
    g_d3d_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_LINELIST);
    g_d3d_context->IASetInputLayout(g_layout_unlit);
    g_d3d_context->VSSetShader(g_vs_unlit, nullptr, 0);
    g_d3d_context->VSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetShader(g_ps_unlit, nullptr, 0);

    g_d3d_context->RSSetState(g_raster_solid);
    g_d3d_context->OMSetDepthStencilState(g_depth_state_2d, 0);
    g_d3d_context->OMSetBlendState(g_blend_state, nullptr, 0xffffffff);

    g_d3d_context->Draw((UINT)count, 0);
}

// ── Raylib Lua Bindings (lp.rl.*) ───────────────────────────────────────────
static int l_rl_draw_cube(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float z = (float)luaL_checknumber(L, 3);
    float w = (float)luaL_checknumber(L, 4) * 0.5f;
    float h = (float)luaL_checknumber(L, 5) * 0.5f;
    float d = (float)luaL_checknumber(L, 6) * 0.5f;
    float r = (float)luaL_optinteger(L, 7, 100) / 255.0f;
    float g = (float)luaL_optinteger(L, 8, 150) / 255.0f;
    float b = (float)luaL_optinteger(L, 9, 200) / 255.0f;
    float a = (float)luaL_optinteger(L, 10, 255) / 255.0f;

    D3DVertex v[36];
    // Front (+Z)
    v[0]  = { x - w, y - h, z + d, r, g, b, a, 0, 0, 1, 0, 1 };
    v[1]  = { x + w, y - h, z + d, r, g, b, a, 0, 0, 1, 1, 1 };
    v[2]  = { x + w, y + h, z + d, r, g, b, a, 0, 0, 1, 1, 0 };
    v[3]  = { x - w, y - h, z + d, r, g, b, a, 0, 0, 1, 0, 1 };
    v[4]  = { x + w, y + h, z + d, r, g, b, a, 0, 0, 1, 1, 0 };
    v[5]  = { x - w, y + h, z + d, r, g, b, a, 0, 0, 1, 0, 0 };

    // Back (-Z)
    v[6]  = { x + w, y - h, z - d, r, g, b, a, 0, 0, -1, 0, 1 };
    v[7]  = { x - w, y - h, z - d, r, g, b, a, 0, 0, -1, 1, 1 };
    v[8]  = { x - w, y + h, z - d, r, g, b, a, 0, 0, -1, 1, 0 };
    v[9]  = { x + w, y - h, z - d, r, g, b, a, 0, 0, -1, 0, 1 };
    v[10] = { x - w, y + h, z - d, r, g, b, a, 0, 0, -1, 1, 0 };
    v[11] = { x + w, y + h, z - d, r, g, b, a, 0, 0, -1, 0, 0 };

    // Top (+Y)
    v[12] = { x - w, y + h, z + d, r, g, b, a, 0, 1, 0, 0, 1 };
    v[13] = { x + w, y + h, z + d, r, g, b, a, 0, 1, 0, 1, 1 };
    v[14] = { x + w, y + h, z - d, r, g, b, a, 0, 1, 0, 1, 0 };
    v[15] = { x - w, y + h, z + d, r, g, b, a, 0, 1, 0, 0, 1 };
    v[16] = { x + w, y + h, z - d, r, g, b, a, 0, 1, 0, 1, 0 };
    v[17] = { x - w, y + h, z - d, r, g, b, a, 0, 1, 0, 0, 0 };

    // Bottom (-Y)
    v[18] = { x - w, y - h, z - d, r, g, b, a, 0, -1, 0, 0, 1 };
    v[19] = { x + w, y - h, z - d, r, g, b, a, 0, -1, 0, 1, 1 };
    v[20] = { x + w, y - h, z + d, r, g, b, a, 0, -1, 0, 1, 0 };
    v[21] = { x - w, y - h, z - d, r, g, b, a, 0, -1, 0, 0, 1 };
    v[22] = { x + w, y - h, z + d, r, g, b, a, 0, -1, 0, 1, 0 };
    v[23] = { x - w, y - h, z + d, r, g, b, a, 0, -1, 0, 0, 0 };

    // Right (+X)
    v[24] = { x + w, y - h, z + d, r, g, b, a, 1, 0, 0, 0, 1 };
    v[25] = { x + w, y - h, z - d, r, g, b, a, 1, 0, 0, 1, 1 };
    v[26] = { x + w, y + h, z - d, r, g, b, a, 1, 0, 0, 1, 0 };
    v[27] = { x + w, y - h, z + d, r, g, b, a, 1, 0, 0, 0, 1 };
    v[28] = { x + w, y + h, z - d, r, g, b, a, 1, 0, 0, 1, 0 };
    v[29] = { x + w, y + h, z + d, r, g, b, a, 1, 0, 0, 0, 0 };

    // Left (-X)
    v[30] = { x - w, y - h, z - d, r, g, b, a, -1, 0, 0, 0, 1 };
    v[31] = { x - w, y - h, z + d, r, g, b, a, -1, 0, 0, 1, 1 };
    v[32] = { x - w, y + h, z + d, r, g, b, a, -1, 0, 0, 1, 0 };
    v[33] = { x - w, y - h, z - d, r, g, b, a, -1, 0, 0, 0, 1 };
    v[34] = { x - w, y + h, z + d, r, g, b, a, -1, 0, 0, 1, 0 };
    v[35] = { x - w, y + h, z - d, r, g, b, a, -1, 0, 0, 0, 0 };

    draw_dynamic_triangles(v, 36);
    return 0;
}

static int l_rl_draw_cube_wires(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float z = (float)luaL_checknumber(L, 3);
    float w = (float)luaL_checknumber(L, 4) * 0.5f;
    float h = (float)luaL_checknumber(L, 5) * 0.5f;
    float d = (float)luaL_checknumber(L, 6) * 0.5f;
    float r = (float)luaL_optinteger(L, 7, 40) / 255.0f;
    float g = (float)luaL_optinteger(L, 8, 50) / 255.0f;
    float b = (float)luaL_optinteger(L, 9, 70) / 255.0f;
    float a = (float)luaL_optinteger(L, 10, 255) / 255.0f;

    D3DVertex lines[24] = {
        // Bottom square
        { x-w, y-h, z-d, r,g,b,a, 0,0,0, 0,0 }, { x+w, y-h, z-d, r,g,b,a, 0,0,0, 0,0 },
        { x+w, y-h, z-d, r,g,b,a, 0,0,0, 0,0 }, { x+w, y-h, z+d, r,g,b,a, 0,0,0, 0,0 },
        { x+w, y-h, z+d, r,g,b,a, 0,0,0, 0,0 }, { x-w, y-h, z+d, r,g,b,a, 0,0,0, 0,0 },
        { x-w, y-h, z+d, r,g,b,a, 0,0,0, 0,0 }, { x-w, y-h, z-d, r,g,b,a, 0,0,0, 0,0 },
        // Top square
        { x-w, y+h, z-d, r,g,b,a, 0,0,0, 0,0 }, { x+w, y+h, z-d, r,g,b,a, 0,0,0, 0,0 },
        { x+w, y+h, z-d, r,g,b,a, 0,0,0, 0,0 }, { x+w, y+h, z+d, r,g,b,a, 0,0,0, 0,0 },
        { x+w, y+h, z+d, r,g,b,a, 0,0,0, 0,0 }, { x-w, y+h, z+d, r,g,b,a, 0,0,0, 0,0 },
        { x-w, y+h, z+d, r,g,b,a, 0,0,0, 0,0 }, { x-w, y+h, z-d, r,g,b,a, 0,0,0, 0,0 },
        // Vertical pillars
        { x-w, y-h, z-d, r,g,b,a, 0,0,0, 0,0 }, { x-w, y+h, z-d, r,g,b,a, 0,0,0, 0,0 },
        { x+w, y-h, z-d, r,g,b,a, 0,0,0, 0,0 }, { x+w, y+h, z-d, r,g,b,a, 0,0,0, 0,0 },
        { x+w, y-h, z+d, r,g,b,a, 0,0,0, 0,0 }, { x+w, y+h, z+d, r,g,b,a, 0,0,0, 0,0 },
        { x-w, y-h, z+d, r,g,b,a, 0,0,0, 0,0 }, { x-w, y+h, z+d, r,g,b,a, 0,0,0, 0,0 },
    };
    draw_dynamic_lines(lines, 24);
    return 0;
}

static int l_rl_draw_grid(lua_State* L) {
    int slices = (int)luaL_checkinteger(L, 1);
    float spacing = (float)luaL_checknumber(L, 2);
    float half = slices * spacing * 0.5f;

    std::vector<D3DVertex> lines;
    lines.reserve((slices + 1) * 4);
    float r = 0.25f, g = 0.26f, b = 0.30f, a = 0.8f;
    float gy = -0.02f; // Anti-z-fighting

    for (int i = 0; i <= slices; i++) {
        float pos = -half + i * spacing;
        lines.push_back({ pos, gy, -half, r, g, b, a, 0, 0, 0, 0, 0 });
        lines.push_back({ pos, gy,  half, r, g, b, a, 0, 0, 0, 0, 0 });
        lines.push_back({ -half, gy, pos, r, g, b, a, 0, 0, 0, 0, 0 });
        lines.push_back({  half, gy, pos, r, g, b, a, 0, 0, 0, 0, 0 });
    }
    draw_dynamic_lines(lines.data(), lines.size());
    return 0;
}

static int l_rl_draw_line_3d(lua_State* L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float z1 = (float)luaL_checknumber(L, 3);
    float x2 = (float)luaL_checknumber(L, 4);
    float y2 = (float)luaL_checknumber(L, 5);
    float z2 = (float)luaL_checknumber(L, 6);
    float r = (float)luaL_optinteger(L, 7, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 8, 255) / 255.0f;
    float b = (float)luaL_optinteger(L, 9, 255) / 255.0f;
    float a = (float)luaL_optinteger(L, 10, 255) / 255.0f;

    D3DVertex line[2] = {
        { x1, y1, z1, r, g, b, a, 0, 0, 0, 0, 0 },
        { x2, y2, z2, r, g, b, a, 0, 0, 0, 0, 0 },
    };
    draw_dynamic_lines(line, 2);
    return 0;
}

static int l_rl_draw_sphere_wires(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float z = (float)luaL_checknumber(L, 3);
    float rad = (float)luaL_checknumber(L, 4);
    int rings = (int)luaL_optinteger(L, 5, 12);
    int slices = (int)luaL_optinteger(L, 6, 12);
    float r = (float)luaL_optinteger(L, 7, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 8, 200) / 255.0f;
    float b = (float)luaL_optinteger(L, 9, 0) / 255.0f;
    float a = (float)luaL_optinteger(L, 10, 255) / 255.0f;

    if (rings < 2) rings = 2;
    if (slices < 3) slices = 3;

    std::vector<D3DVertex> lines;
    const float PI = 3.14159265358979323846f;

    // 1. Latitude rings
    for (int i = 1; i < rings; i++) {
        float phi = (float)i * PI / (float)rings;
        float ring_y = y + rad * std::cos(phi);
        float ring_r = rad * std::sin(phi);

        for (int j = 0; j < slices; j++) {
            float t1 = (float)j * 2.0f * PI / (float)slices;
            float t2 = (float)(j + 1) * 2.0f * PI / (float)slices;

            lines.push_back({ x + ring_r * std::cos(t1), ring_y, z + ring_r * std::sin(t1), r, g, b, a, 0, 0, 0, 0, 0 });
            lines.push_back({ x + ring_r * std::cos(t2), ring_y, z + ring_r * std::sin(t2), r, g, b, a, 0, 0, 0, 0, 0 });
        }
    }

    // 2. Longitude meridians
    for (int j = 0; j < slices; j++) {
        float theta = (float)j * 2.0f * PI / (float)slices;
        float cos_t = std::cos(theta);
        float sin_t = std::sin(theta);

        for (int i = 0; i < rings; i++) {
            float p1 = (float)i * PI / (float)rings;
            float p2 = (float)(i + 1) * PI / (float)rings;

            Vec3 v1 = { x + rad * std::sin(p1) * cos_t, y + rad * std::cos(p1), z + rad * std::sin(p1) * sin_t };
            Vec3 v2 = { x + rad * std::sin(p2) * cos_t, y + rad * std::cos(p2), z + rad * std::sin(p2) * sin_t };

            lines.push_back({ v1.x, v1.y, v1.z, r, g, b, a, 0, 0, 0, 0, 0 });
            lines.push_back({ v2.x, v2.y, v2.z, r, g, b, a, 0, 0, 0, 0, 0 });
        }
    }

    draw_dynamic_lines(lines.data(), lines.size());
    return 0;
}

static int l_rl_draw_sphere(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float z = (float)luaL_checknumber(L, 3);
    float rad = (float)luaL_checknumber(L, 4);
    float r = (float)luaL_optinteger(L, 5, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 6, 255) / 255.0f;
    float b = (float)luaL_optinteger(L, 7, 255) / 255.0f;
    float a = (float)luaL_optinteger(L, 8, 255) / 255.0f;

    const int rings = 6, slices = 8;
    std::vector<D3DVertex> verts;
    for (int i = 0; i < rings; i++) {
        float phi1 = (i / (float)rings) * 3.14159265f;
        float phi2 = ((i + 1) / (float)rings) * 3.14159265f;
        for (int j = 0; j < slices; j++) {
            float theta1 = (j / (float)slices) * 6.2831853f;
            float theta2 = ((j + 1) / (float)slices) * 6.2831853f;

            Vec3 p1 = { x + rad * std::sin(phi1) * std::cos(theta1), y + rad * std::cos(phi1), z + rad * std::sin(phi1) * std::sin(theta1) };
            Vec3 p2 = { x + rad * std::sin(phi1) * std::cos(theta2), y + rad * std::cos(phi1), z + rad * std::sin(phi1) * std::sin(theta2) };
            Vec3 p3 = { x + rad * std::sin(phi2) * std::cos(theta2), y + rad * std::cos(phi2), z + rad * std::sin(phi2) * std::sin(theta2) };
            Vec3 p4 = { x + rad * std::sin(phi2) * std::cos(theta1), y + rad * std::cos(phi2), z + rad * std::sin(phi2) * std::sin(theta1) };

            verts.push_back({ p1.x, p1.y, p1.z, r, g, b, a, 0, 1, 0, 0, 0 });
            verts.push_back({ p2.x, p2.y, p2.z, r, g, b, a, 0, 1, 0, 0, 0 });
            verts.push_back({ p3.x, p3.y, p3.z, r, g, b, a, 0, 1, 0, 0, 0 });

            verts.push_back({ p1.x, p1.y, p1.z, r, g, b, a, 0, 1, 0, 0, 0 });
            verts.push_back({ p3.x, p3.y, p3.z, r, g, b, a, 0, 1, 0, 0, 0 });
            verts.push_back({ p4.x, p4.y, p4.z, r, g, b, a, 0, 1, 0, 0, 0 });
        }
    }
    draw_dynamic_triangles_unlit(verts.data(), verts.size(), v4(r, g, b, a));
    return 0;
}

static int l_rl_set_camera(lua_State* L) {
    g_camera.position = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    g_camera.target   = { (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) };
    g_camera.fovy     = (float)luaL_optnumber(L, 7, 60.0);
    return 0;
}

static int l_rl_get_camera(lua_State* L) {
    lua_newtable(L);
    lua_pushnumber(L, g_camera.position.x); lua_setfield(L, -2, "eye_x");
    lua_pushnumber(L, g_camera.position.y); lua_setfield(L, -2, "eye_y");
    lua_pushnumber(L, g_camera.position.z); lua_setfield(L, -2, "eye_z");
    lua_pushnumber(L, g_camera.target.x);   lua_setfield(L, -2, "target_x");
    lua_pushnumber(L, g_camera.target.y);   lua_setfield(L, -2, "target_y");
    lua_pushnumber(L, g_camera.target.z);   lua_setfield(L, -2, "target_z");
    lua_pushnumber(L, g_camera.fovy);       lua_setfield(L, -2, "fov");
    return 1;
}

static int l_rl_get_ray(lua_State* L) {
    float mx = (float)luaL_checknumber(L, 1);
    float my = (float)luaL_checknumber(L, 2);

    float ndc_x = (2.0f * mx) / g_win_w - 1.0f;
    float ndc_y = 1.0f - (2.0f * my) / g_win_h;

    Mat4 view = mat4_look_at(g_camera.position, g_camera.target, g_camera.up);
    Mat4 proj = mat4_perspective(g_camera.fovy, g_win_w / (float)std::max(1, g_win_h), 0.1f, 1000.0f);
    Mat4 vp = mat4_mul(view, proj);
    Mat4 inv_vp;
    mat4_invert(vp, inv_vp);

    Vec4 near_pt = mat4_mul_vec4(inv_vp, v4(ndc_x, ndc_y, 0.0f, 1.0f));
    Vec4 far_pt  = mat4_mul_vec4(inv_vp, v4(ndc_x, ndc_y, 1.0f, 1.0f));

    Vec3 p0 = v3_scale(v3(near_pt.x, near_pt.y, near_pt.z), 1.0f / near_pt.w);
    Vec3 p1 = v3_scale(v3(far_pt.x, far_pt.y, far_pt.z), 1.0f / far_pt.w);
    Vec3 dir = v3_norm(v3_sub(p1, p0));

    lua_pushnumber(L, p0.x);
    lua_pushnumber(L, p0.y);
    lua_pushnumber(L, p0.z);
    lua_pushnumber(L, dir.x);
    lua_pushnumber(L, dir.y);
    lua_pushnumber(L, dir.z);
    return 6;
}

static int l_rl_world_to_screen(lua_State* L) {
    int top = lua_gettop(L);
    if (top >= 3) {
        float x = (float)luaL_checknumber(L, 1);
        float y = (float)luaL_checknumber(L, 2);
        float z = (float)luaL_checknumber(L, 3);

        Mat4 view = mat4_look_at(g_camera.position, g_camera.target, g_camera.up);
        Mat4 proj = mat4_perspective(g_camera.fovy, g_win_w / (float)std::max(1, g_win_h), 0.1f, 1000.0f);
        Mat4 vp = mat4_mul(view, proj);
        Vec4 clip = mat4_mul_vec4(vp, v4(x, y, z, 1.0f));

        if (clip.w <= 0.0f) {
            lua_pushnumber(L, -1000.0);
            lua_pushnumber(L, -1000.0);
            return 2;
        }

        float ndc_x = clip.x / clip.w;
        float ndc_y = clip.y / clip.w;
        float sx = (ndc_x + 1.0f) * 0.5f * g_win_w;
        float sy = (1.0f - ndc_y) * 0.5f * g_win_h;
        lua_pushnumber(L, sx);
        lua_pushnumber(L, sy);
        return 2;
    } else {
        // 2D world to screen
        float wx = (float)luaL_checknumber(L, 1);
        float wy = (float)luaL_checknumber(L, 2);
        float sx = (wx - g_cam2d.target.x) * g_cam2d.zoom + g_win_w * 0.5f;
        float sy = (wy - g_cam2d.target.y) * g_cam2d.zoom + g_win_h * 0.5f;
        lua_pushnumber(L, sx);
        lua_pushnumber(L, sy);
        return 2;
    }
}

static int l_rl_screen_to_world(lua_State* L) {
    float mx = (float)luaL_checknumber(L, 1);
    float my = (float)luaL_checknumber(L, 2);
    float wx = (mx - g_win_w * 0.5f) / g_cam2d.zoom + g_cam2d.target.x;
    float wy = (my - g_win_h * 0.5f) / g_cam2d.zoom + g_cam2d.target.y;
    lua_pushnumber(L, wx);
    lua_pushnumber(L, wy);
    return 2;
}

// ── Models & Meshes ─────────────────────────────────────────────────────────
static int l_rl_load_model_mesh(lua_State* L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    luaL_checktype(L, 2, LUA_TTABLE);

    size_t vert_count = lua_rawlen(L, 1);
    size_t index_count = lua_rawlen(L, 2);
    size_t num_verts = vert_count / 12;

    std::vector<D3DVertex> verts(num_verts);
    for (size_t i = 0; i < num_verts; i++) {
        size_t base = i * 12;
        lua_rawgeti(L, 1, base + 1);  verts[i].x  = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 2);  verts[i].y  = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 3);  verts[i].z  = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 4);  verts[i].r  = (float)lua_tonumber(L, -1) / 255.0f; lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 5);  verts[i].g  = (float)lua_tonumber(L, -1) / 255.0f; lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 6);  verts[i].b  = (float)lua_tonumber(L, -1) / 255.0f; lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 7);  verts[i].a  = (float)lua_tonumber(L, -1) / 255.0f; lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 8);  verts[i].nx = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 9);  verts[i].ny = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 10); verts[i].nz = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 11); verts[i].u  = (float)lua_tonumber(L, -1); lua_pop(L, 1);
        lua_rawgeti(L, 1, base + 12); verts[i].v  = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    }

    std::vector<uint32_t> indices(index_count);
    for (size_t i = 0; i < index_count; i++) {
        lua_rawgeti(L, 2, i + 1);
        indices[i] = (uint32_t)lua_tointeger(L, -1);
        lua_pop(L, 1);
    }

    ID3D11Buffer* vb = nullptr;
    ID3D11Buffer* ib = nullptr;

    D3D11_BUFFER_DESC vbd = {};
    vbd.Usage = D3D11_USAGE_IMMUTABLE;
    vbd.ByteWidth = (UINT)(verts.size() * sizeof(D3DVertex));
    vbd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    D3D11_SUBRESOURCE_DATA vdata = { verts.data(), 0, 0 };
    g_d3d_device->CreateBuffer(&vbd, &vdata, &vb);

    D3D11_BUFFER_DESC ibd = {};
    ibd.Usage = D3D11_USAGE_IMMUTABLE;
    ibd.ByteWidth = (UINT)(indices.size() * sizeof(uint32_t));
    ibd.BindFlags = D3D11_BIND_INDEX_BUFFER;
    D3D11_SUBRESOURCE_DATA idata = { indices.data(), 0, 0 };
    g_d3d_device->CreateBuffer(&ibd, &idata, &ib);

    D3DModel model = {};
    model.vb = vb;
    model.ib = ib;
    model.vertex_count = (int)verts.size();
    model.index_count = (int)indices.size();
    model.texture_id = -1;

    g_models.push_back(model);
    lua_pushinteger(L, (int)g_models.size());
    return 1;
}

static int l_rl_load_model_cube(lua_State* L) {
    float w = (float)luaL_checknumber(L, 1);
    float h = (float)luaL_checknumber(L, 2);
    float d = (float)luaL_checknumber(L, 3);
    // Build 6 faces * 2 tris
    lua_newtable(L);
    lua_newtable(L);
    // Push into load_model_mesh
    // We synthesize vertices
    float hw = w*0.5f, hh = h*0.5f, hd = d*0.5f;
    D3DVertex v[24] = {
        // Front
        {-hw,-hh, hd, 1,1,1,1, 0,0,1, 0,1}, { hw,-hh, hd, 1,1,1,1, 0,0,1, 1,1},
        { hw, hh, hd, 1,1,1,1, 0,0,1, 1,0}, {-hw, hh, hd, 1,1,1,1, 0,0,1, 0,0},
        // Back
        { hw,-hh,-hd, 1,1,1,1, 0,0,-1, 0,1}, {-hw,-hh,-hd, 1,1,1,1, 0,0,-1, 1,1},
        {-hw, hh,-hd, 1,1,1,1, 0,0,-1, 1,0}, { hw, hh,-hd, 1,1,1,1, 0,0,-1, 0,0},
        // Top
        {-hw, hh, hd, 1,1,1,1, 0,1,0, 0,1}, { hw, hh, hd, 1,1,1,1, 0,1,0, 1,1},
        { hw, hh,-hd, 1,1,1,1, 0,1,0, 1,0}, {-hw, hh,-hd, 1,1,1,1, 0,1,0, 0,0},
        // Bottom
        {-hw,-hh,-hd, 1,1,1,1, 0,-1,0, 0,1}, { hw,-hh,-hd, 1,1,1,1, 0,-1,0, 1,1},
        { hw,-hh, hd, 1,1,1,1, 0,-1,0, 1,0}, {-hw,-hh, hd, 1,1,1,1, 0,-1,0, 0,0},
        // Right
        { hw,-hh, hd, 1,1,1,1, 1,0,0, 0,1}, { hw,-hh,-hd, 1,1,1,1, 1,0,0, 1,1},
        { hw, hh,-hd, 1,1,1,1, 1,0,0, 1,0}, { hw, hh, hd, 1,1,1,1, 1,0,0, 0,0},
        // Left
        {-hw,-hh,-hd, 1,1,1,1, -1,0,0, 0,1}, {-hw,-hh, hd, 1,1,1,1, -1,0,0, 1,1},
        {-hw, hh, hd, 1,1,1,1, -1,0,0, 1,0}, {-hw, hh,-hd, 1,1,1,1, -1,0,0, 0,0},
    };
    uint32_t idx[36];
    for (int i = 0; i < 6; i++) {
        idx[i*6+0] = i*4+0; idx[i*6+1] = i*4+1; idx[i*6+2] = i*4+2;
        idx[i*6+3] = i*4+0; idx[i*6+4] = i*4+2; idx[i*6+5] = i*4+3;
    }

    ID3D11Buffer* vb = nullptr;
    ID3D11Buffer* ib = nullptr;
    D3D11_BUFFER_DESC vbd = { sizeof(v), D3D11_USAGE_IMMUTABLE, D3D11_BIND_VERTEX_BUFFER, 0, 0, 0 };
    D3D11_SUBRESOURCE_DATA vdata = { v, 0, 0 };
    g_d3d_device->CreateBuffer(&vbd, &vdata, &vb);

    D3D11_BUFFER_DESC ibd = { sizeof(idx), D3D11_USAGE_IMMUTABLE, D3D11_BIND_INDEX_BUFFER, 0, 0, 0 };
    D3D11_SUBRESOURCE_DATA idata = { idx, 0, 0 };
    g_d3d_device->CreateBuffer(&ibd, &idata, &ib);

    D3DModel m = { vb, ib, 24, 36, -1, { 1, 1, 1, 1 } };
    g_models.push_back(m);
    lua_pushinteger(L, (int)g_models.size());
    return 1;
}

static int l_rl_draw_model(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id <= 0 || id > (int)g_models.size()) return 0;
    D3DModel& m = g_models[id - 1];
    if (!m.vb || !m.ib || !g_d3d_context) return 0;

    float x = (float)luaL_optnumber(L, 2, 0.0);
    float y = (float)luaL_optnumber(L, 3, 0.0);
    float z = (float)luaL_optnumber(L, 4, 0.0);
    float scale = (float)luaL_optnumber(L, 5, 1.0);
    float r = (float)luaL_optinteger(L, 6, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 7, 255) / 255.0f;
    float b = (float)luaL_optinteger(L, 8, 255) / 255.0f;
    float a = (float)luaL_optinteger(L, 9, 255) / 255.0f;

    Mat4 model_mat = mat4_identity();
    model_mat.m[0] = scale; model_mat.m[5] = scale; model_mat.m[10] = scale;
    model_mat.m[12] = x; model_mat.m[13] = y; model_mat.m[14] = z;

    Mat4 view = mat4_look_at(g_camera.position, g_camera.target, g_camera.up);
    Mat4 proj = mat4_perspective(g_camera.fovy, g_win_w / (float)std::max(1, g_win_h), 0.1f, 1000.0f);
    Mat4 mvp = mat4_mul(model_mat, mat4_mul(view, proj));

    SceneCBuffer cb = {};
    cb.mvp = mvp;
    if (g_lighting_enabled) {
        cb.ambient = v4(0.45f, 0.45f, 0.48f, 1.0f);
        cb.sun_dir = v4(0.5f, 0.8f, 0.6f, 0.0f);
        cb.sun_color = v4(0.75f, 0.73f, 0.68f, 1.0f);
    } else {
        cb.ambient = v4(1.0f, 1.0f, 1.0f, 1.0f);
        cb.sun_dir = v4(0.0f, 0.0f, 0.0f, 0.0f);
        cb.sun_color = v4(0.0f, 0.0f, 0.0f, 1.0f);
    }
    cb.color_tint = v4(r, g, b, a);
    cb.use_texture = (m.texture_id > 0 && m.texture_id <= (int)g_textures.size() && g_textures[m.texture_id - 1].srv != nullptr) ? 1 : 0;

    g_d3d_context->UpdateSubresource(g_cbuffer_scene, 0, nullptr, &cb, 0, 0);

    if (cb.use_texture) {
        ID3D11ShaderResourceView* srv = g_textures[m.texture_id - 1].srv;
        g_d3d_context->PSSetShaderResources(0, 1, &srv);
    }

    UINT stride = sizeof(D3DVertex);
    UINT offset = 0;
    g_d3d_context->IASetVertexBuffers(0, 1, &m.vb, &stride, &offset);
    g_d3d_context->IASetIndexBuffer(m.ib, DXGI_FORMAT_R32_UINT, 0);
    g_d3d_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_d3d_context->IASetInputLayout(g_layout_3d);
    g_d3d_context->VSSetShader(g_vs_3d, nullptr, 0);
    g_d3d_context->VSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetShader(g_ps_3d, nullptr, 0);
    g_d3d_context->PSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetSamplers(0, 1, &g_sampler_state);

    g_d3d_context->RSSetState(g_raster_solid);
    g_d3d_context->OMSetDepthStencilState(g_depth_state_3d, 0);
    g_d3d_context->OMSetBlendState(g_blend_state, nullptr, 0xffffffff);

    g_d3d_context->DrawIndexed((UINT)m.index_count, 0, 0);
    return 0;
}

static int l_rl_draw_model_wires(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id <= 0 || id > (int)g_models.size()) return 0;
    D3DModel& m = g_models[id - 1];
    if (!m.vb || !m.ib || !g_d3d_context) return 0;

    float x = (float)luaL_optnumber(L, 2, 0.0);
    float y = (float)luaL_optnumber(L, 3, 0.0);
    float z = (float)luaL_optnumber(L, 4, 0.0);
    float scale = (float)luaL_optnumber(L, 5, 1.0);
    float r = (float)luaL_optinteger(L, 6, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 7, 255) / 255.0f;
    float b = (float)luaL_optinteger(L, 8, 255) / 255.0f;
    float a = (float)luaL_optinteger(L, 9, 255) / 255.0f;

    Mat4 model_mat = mat4_identity();
    model_mat.m[0] = scale; model_mat.m[5] = scale; model_mat.m[10] = scale;
    model_mat.m[12] = x; model_mat.m[13] = y; model_mat.m[14] = z;

    Mat4 view = mat4_look_at(g_camera.position, g_camera.target, g_camera.up);
    Mat4 proj = mat4_perspective(g_camera.fovy, g_win_w / (float)std::max(1, g_win_h), 0.1f, 1000.0f);
    Mat4 mvp = mat4_mul(model_mat, mat4_mul(view, proj));

    SceneCBuffer cb = {};
    cb.mvp = mvp;
    cb.model = model_mat;
    cb.color_tint = v4(r, g, b, a);
    cb.use_texture = 0;
    g_d3d_context->UpdateSubresource(g_cbuffer_scene, 0, nullptr, &cb, 0, 0);

    UINT stride = sizeof(D3DVertex);
    UINT offset = 0;
    g_d3d_context->IASetVertexBuffers(0, 1, &m.vb, &stride, &offset);
    g_d3d_context->IASetIndexBuffer(m.ib, DXGI_FORMAT_R32_UINT, 0);
    g_d3d_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_d3d_context->IASetInputLayout(g_layout_unlit);
    g_d3d_context->VSSetShader(g_vs_unlit, nullptr, 0);
    g_d3d_context->VSSetConstantBuffers(0, 1, &g_cbuffer_scene);
    g_d3d_context->PSSetShader(g_ps_unlit, nullptr, 0);

    g_d3d_context->RSSetState(g_raster_wire);
    g_d3d_context->OMSetDepthStencilState(g_depth_state_3d, 0);
    g_d3d_context->OMSetBlendState(g_blend_state, nullptr, 0xffffffff);

    g_d3d_context->DrawIndexed((UINT)m.index_count, 0, 0);
    return 0;
}

static int l_rl_unload_model(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id > 0 && id <= (int)g_models.size()) {
        D3DModel& m = g_models[id - 1];
        if (m.vb) { m.vb->Release(); m.vb = nullptr; }
        if (m.ib) { m.ib->Release(); m.ib = nullptr; }
    }
    return 0;
}

static int l_rl_set_material_texture(lua_State* L) {
    int model_id = (int)luaL_checkinteger(L, 1);
    int map = (int)luaL_checkinteger(L, 2);
    int tex_id = (int)luaL_checkinteger(L, 3);
    if (model_id > 0 && model_id <= (int)g_models.size()) {
        g_models[model_id - 1].texture_id = tex_id;
    }
    return 0;
}

static int l_rl_load_texture_perlin(lua_State* L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    float scale = (float)luaL_optnumber(L, 3, 5.0);

    std::vector<uint32_t> pixels(w * h);
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            float nx = (x / (float)w) * scale;
            float ny = (y / (float)h) * scale;
            float n = stb_perlin_fbm_noise3(nx, ny, 0.5f, 2.0f, 0.5f, 6);
            float val = std::max(0.0f, std::min(1.0f, (n + 1.0f) * 0.5f));
            uint8_t c = (uint8_t)(val * 255.0f);
            pixels[y * w + x] = (0xFF << 24) | (c << 16) | (c << 8) | c;
        }
    }

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = w;
    desc.Height = h;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

    D3D11_SUBRESOURCE_DATA init_data = { pixels.data(), (UINT)(w * sizeof(uint32_t)), 0 };
    ID3D11Texture2D* tex = nullptr;
    ID3D11ShaderResourceView* srv = nullptr;

    g_d3d_device->CreateTexture2D(&desc, &init_data, &tex);
    g_d3d_device->CreateShaderResourceView(tex, nullptr, &srv);

    int id = register_texture(tex, srv, w, h);
    lua_pushinteger(L, id);
    return 1;
}

static int l_rl_unload_texture(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    if (id > 0 && id <= (int)g_textures.size()) {
        D3DTexture& t = g_textures[id - 1];
        if (t.srv) { t.srv->Release(); t.srv = nullptr; }
        if (t.tex) { t.tex->Release(); t.tex = nullptr; }
    }
    return 0;
}
// ── CanvasTex Structure & Globals ──────────────────────────────────────────
struct CanvasTex {
    int width = 0;
    int height = 0;
    std::vector<unsigned char> data;
    int d3d_tex_id = -1;
    std::vector<std::vector<unsigned char>> undo_stack;
    std::vector<std::vector<unsigned char>> redo_stack;
};
static std::vector<CanvasTex> g_canvas;

static CanvasTex* canvas_check(lua_State* L, int arg) {
    int id = (int)luaL_checkinteger(L, arg);
    if (id < 0 || id >= (int)g_canvas.size()) {
        luaL_error(L, "canvas id %d out of range (count=%d)", id, (int)g_canvas.size());
        return nullptr;
    }
    return &g_canvas[id];
}

static int l_tex_upload(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    if (!ct || !g_d3d_device) return 0;

    if (ct->d3d_tex_id <= 0) {
        D3D11_TEXTURE2D_DESC desc = {};
        desc.Width = ct->width;
        desc.Height = ct->height;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        desc.SampleDesc.Count = 1;
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

        D3D11_SUBRESOURCE_DATA data = { ct->data.data(), (UINT)(ct->width * 4), 0 };
        ID3D11Texture2D* tex = nullptr;
        ID3D11ShaderResourceView* srv = nullptr;
        g_d3d_device->CreateTexture2D(&desc, &data, &tex);
        g_d3d_device->CreateShaderResourceView(tex, nullptr, &srv);
        ct->d3d_tex_id = register_texture(tex, srv, ct->width, ct->height);
    } else {
        D3DTexture& t = g_textures[ct->d3d_tex_id - 1];
        g_d3d_context->UpdateSubresource(t.tex, 0, nullptr, ct->data.data(), ct->width * 4, 0);
    }
    return 0;
}

// ── 2D Canvas Viewport Bindings ─────────────────────────────────────────────
static int l_rl_begin_mode2d(lua_State* L) {
    g_in_mode2d = true;
    return 0;
}

static int l_rl_end_mode2d(lua_State* L) {
    g_in_mode2d = false;
    return 0;
}
static int l_rl_draw_texture(lua_State* L) {
    int id = (int)luaL_checkinteger(L, 1);
    float x = (float)luaL_checknumber(L, 2);
    float y = (float)luaL_checknumber(L, 3);
    float w = (float)luaL_checknumber(L, 4);
    float h = (float)luaL_checknumber(L, 5);

    int d3d_id = -1;
    if (id >= 0 && id < (int)g_canvas.size()) {
        CanvasTex& c = g_canvas[id];
        if (c.d3d_tex_id <= 0) {
            lua_pushinteger(L, id);
            l_tex_upload(L);
            lua_pop(L, 1);
        }
        d3d_id = c.d3d_tex_id;
    } else if (id > 0 && id <= (int)g_textures.size()) {
        d3d_id = id;
    }

    if (d3d_id <= 0 || d3d_id > (int)g_textures.size()) return 0;

    float sx0 = (x - g_cam2d.target.x) * g_cam2d.zoom + g_win_w * 0.5f;
    float sy0 = (y - g_cam2d.target.y) * g_cam2d.zoom + g_win_h * 0.5f;
    float sx1 = sx0 + w * g_cam2d.zoom;
    float sy1 = sy0 + h * g_cam2d.zoom;

    float ndc_x0 = (2.0f * sx0) / g_win_w - 1.0f;
    float ndc_x1 = (2.0f * sx1) / g_win_w - 1.0f;
    float ndc_y0 = 1.0f - (2.0f * sy0) / g_win_h;
    float ndc_y1 = 1.0f - (2.0f * sy1) / g_win_h;

    D3DVertex quad[6] = {
        { ndc_x0, ndc_y0, 0.0f, 1,1,1,1, 0,0,-1, 0, 0 },
        { ndc_x1, ndc_y0, 0.0f, 1,1,1,1, 0,0,-1, 1, 0 },
        { ndc_x1, ndc_y1, 0.0f, 1,1,1,1, 0,0,-1, 1, 1 },
        { ndc_x0, ndc_y0, 0.0f, 1,1,1,1, 0,0,-1, 0, 0 },
        { ndc_x1, ndc_y1, 0.0f, 1,1,1,1, 0,0,-1, 1, 1 },
        { ndc_x0, ndc_y1, 0.0f, 1,1,1,1, 0,0,-1, 0, 1 },
    };
    draw_dynamic_triangles_2d(quad, 6, d3d_id);
    return 0;
}
static int l_rl_draw_rect_2d(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float w = (float)luaL_checknumber(L, 3);
    float h = (float)luaL_checknumber(L, 4);
    float r = (float)luaL_optinteger(L, 5, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 6, 255) / 255.0f;
    float b = (float)luaL_optinteger(L, 7, 255) / 255.0f;
    float a = (float)luaL_optinteger(L, 8, 255) / 255.0f;

    float sx0 = (x - g_cam2d.target.x) * g_cam2d.zoom + g_win_w * 0.5f;
    float sy0 = (y - g_cam2d.target.y) * g_cam2d.zoom + g_win_h * 0.5f;
    float sx1 = sx0 + w * g_cam2d.zoom;
    float sy1 = sy0 + h * g_cam2d.zoom;

    float ndc_x0 = (2.0f * sx0) / g_win_w - 1.0f;
    float ndc_x1 = (2.0f * sx1) / g_win_w - 1.0f;
    float ndc_y0 = 1.0f - (2.0f * sy0) / g_win_h;
    float ndc_y1 = 1.0f - (2.0f * sy1) / g_win_h;

    D3DVertex quad[6] = {
        { ndc_x0, ndc_y0, 0.0f, r, g, b, a, 0,0,-1, 0, 0 },
        { ndc_x1, ndc_y0, 0.0f, r, g, b, a, 0,0,-1, 1, 0 },
        { ndc_x1, ndc_y1, 0.0f, r, g, b, a, 0,0,-1, 1, 1 },
        { ndc_x0, ndc_y0, 0.0f, r, g, b, a, 0,0,-1, 0, 0 },
        { ndc_x1, ndc_y1, 0.0f, r, g, b, a, 0,0,-1, 1, 1 },
        { ndc_x0, ndc_y1, 0.0f, r, g, b, a, 0,0,-1, 0, 1 },
    };
    draw_dynamic_triangles_2d(quad, 6, -1);
    return 0;
}

static int l_rl_draw_circle_lines_2d(lua_State* L) {
    float cx = (float)luaL_checknumber(L, 1);
    float cy = (float)luaL_checknumber(L, 2);
    float rad = (float)luaL_checknumber(L, 3);
    float r = (float)luaL_optinteger(L, 5, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 6, 255) / 255.0f;
    float b = (float)luaL_optinteger(L, 7, 255) / 255.0f;
    float a = (float)luaL_optinteger(L, 8, 255) / 255.0f;

    std::vector<D3DVertex> lines;
    const int segs = 32;
    for (int i = 0; i < segs; i++) {
        float a1 = (i / (float)segs) * 6.2831853f;
        float a2 = ((i + 1) / (float)segs) * 6.2831853f;
        float wx1 = cx + rad * std::cos(a1);
        float wy1 = cy + rad * std::sin(a1);
        float wx2 = cx + rad * std::cos(a2);
        float wy2 = cy + rad * std::sin(a2);

        float sx1 = (wx1 - g_cam2d.target.x) * g_cam2d.zoom + g_win_w * 0.5f;
        float sy1 = (wy1 - g_cam2d.target.y) * g_cam2d.zoom + g_win_h * 0.5f;
        float sx2 = (wx2 - g_cam2d.target.x) * g_cam2d.zoom + g_win_w * 0.5f;
        float sy2 = (wy2 - g_cam2d.target.y) * g_cam2d.zoom + g_win_h * 0.5f;

        float ndc_x1 = (2.0f * sx1) / g_win_w - 1.0f;
        float ndc_y1 = 1.0f - (2.0f * sy1) / g_win_h;
        float ndc_x2 = (2.0f * sx2) / g_win_w - 1.0f;
        float ndc_y2 = 1.0f - (2.0f * sy2) / g_win_h;

        lines.push_back({ ndc_x1, ndc_y1, 0.0f, r, g, b, a, 0, 0, 0, 0, 0 });
        lines.push_back({ ndc_x2, ndc_y2, 0.0f, r, g, b, a, 0, 0, 0, 0, 0 });
    }
    draw_dynamic_lines_2d(lines.data(), lines.size());
    return 0;
}

static int l_rl_draw_text_2d(lua_State* L) {
    return 0;
}

static int l_rl_draw_line_2d(lua_State* L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float x2 = (float)luaL_checknumber(L, 3);
    float y2 = (float)luaL_checknumber(L, 4);
    float r = (float)luaL_optinteger(L, 6, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 7, 255) / 255.0f;
    float b = (float)luaL_optinteger(L, 8, 255) / 255.0f;
    float a = (float)luaL_optinteger(L, 9, 255) / 255.0f;

    float sx1 = (x1 - g_cam2d.target.x) * g_cam2d.zoom + g_win_w * 0.5f;
    float sy1 = (y1 - g_cam2d.target.y) * g_cam2d.zoom + g_win_h * 0.5f;
    float sx2 = (x2 - g_cam2d.target.x) * g_cam2d.zoom + g_win_w * 0.5f;
    float sy2 = (y2 - g_cam2d.target.y) * g_cam2d.zoom + g_win_h * 0.5f;

    float ndc_x1 = (2.0f * sx1) / g_win_w - 1.0f;
    float ndc_y1 = 1.0f - (2.0f * sy1) / g_win_h;
    float ndc_x2 = (2.0f * sx2) / g_win_w - 1.0f;
    float ndc_y2 = 1.0f - (2.0f * sy2) / g_win_h;

    D3DVertex line[2] = {
        { ndc_x1, ndc_y1, 0.0f, r, g, b, a, 0, 0, 0, 0, 0 },
        { ndc_x2, ndc_y2, 0.0f, r, g, b, a, 0, 0, 0, 0, 0 },
    };
    draw_dynamic_lines_2d(line, 2);
    return 0;
}

static int l_rl_get_screen_size(lua_State* L) {
    lua_pushinteger(L, g_win_w);
    lua_pushinteger(L, g_win_h);
    return 2;
}

static int l_rl_get_frame_time(lua_State* L) {
    lua_pushnumber(L, g_last_frame_time);
    return 1;
}

static int l_rl_set_window_size(lua_State* L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    if (w > 0 && h > 0 && g_hwnd) {
        SetWindowPos(g_hwnd, nullptr, 0, 0, w, h, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
    return 0;
}
static HCURSOR g_current_cursor = nullptr;

static int l_rl_set_mouse_cursor(lua_State* L) {
    int type = (int)luaL_optinteger(L, 1, 0);
    LPCTSTR cur = IDC_ARROW;
    switch (type) {
        case 1: cur = IDC_SIZEWE; break;
        case 2: cur = IDC_SIZENS; break;
        case 3: cur = IDC_SIZENWSE; break;
        case 4: cur = IDC_SIZENESW; break;
        case 5: cur = IDC_HAND; break;
        case 6: cur = IDC_CROSS; break;
        default: cur = IDC_ARROW; break;
    }
    g_current_cursor = LoadCursor(nullptr, cur);
    return 0;
}

static int l_rl_set_target_fps(lua_State* L) {
    g_target_fps = (int)luaL_checkinteger(L, 1);
    return 0;
}

static int l_rl_get_target_fps(lua_State* L) {
    lua_pushinteger(L, g_target_fps);
    return 1;
}

static int l_rl_get_monitor_refresh_rate(lua_State* L) {
    lua_pushinteger(L, 240);
    return 1;
}


static int l_rl_get_monitor_size(lua_State* L) {
    int w = 1920, h = 1080;
    win_get_workarea(&w, &h);
    lua_pushinteger(L, w);
    lua_pushinteger(L, h);
    return 2;
}

static int l_rl_set_window_position(lua_State* L) {
    int x = (int)luaL_checkinteger(L, 1);
    int y = (int)luaL_checkinteger(L, 2);
    if (g_hwnd) SetWindowPos(g_hwnd, nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    return 0;
}

static int l_rl_get_window_position(lua_State* L) {
    RECT rc = {};
    if (g_hwnd) GetWindowRect(g_hwnd, &rc);
    lua_pushinteger(L, rc.left);
    lua_pushinteger(L, rc.top);
    return 2;
}


static int l_rl_is_mouse_button_down(lua_State* L) {
    int btn = (int)luaL_checkinteger(L, 1);
    if (btn >= 0 && btn < 3) {
        lua_pushboolean(L, g_drive_active ? g_drive_btn[btn] : g_mouse_down[btn]);
    } else {
        lua_pushboolean(L, false);
    }
    return 1;
}

static int l_rl_is_mouse_button_pressed(lua_State* L) {
    int btn = (int)luaL_checkinteger(L, 1);
    if (g_drive_active) {
        lua_pushboolean(L, btn >= 0 && btn < 3 && g_drive_btn_pressed[btn]);
        return 1;
    }
    if (btn >= 0 && btn < 3) {
        lua_pushboolean(L, g_mouse_pressed[btn]);
    } else {
        lua_pushboolean(L, false);
    }
    return 1;
}

static int l_rl_get_mouse_delta(lua_State* L) {
    if (g_drive_active) {
        lua_pushnumber(L, g_drive_mx - g_drive_px);
        lua_pushnumber(L, g_drive_my - g_drive_py);
        return 2;
    }
    lua_pushnumber(L, g_mouse_dx);
    lua_pushnumber(L, g_mouse_dy);
    return 2;
}
static int l_rl_get_mouse_wheel(lua_State* L) {
    lua_pushnumber(L, g_drive_active ? g_drive_wheel : g_mouse_wheel);
    return 1;
}

static int l_rl_get_mouse_pos(lua_State* L) {
    if (g_drive_active) {
        lua_pushnumber(L, g_drive_mx);
        lua_pushnumber(L, g_drive_my);
    } else {
        lua_pushnumber(L, g_mouse_x);
        lua_pushnumber(L, g_mouse_y);
    }
    return 2;
}

static int l_rl_is_key_pressed(lua_State* L) {
    int k = (int)luaL_checkinteger(L, 1);
    if (g_drive_active) {
        lua_pushboolean(L, k >= 0 && k < 512 && g_drive_key_pressed[k]);
        return 1;
    }
    if (k >= 0 && k < 512) {
        lua_pushboolean(L, g_keys_pressed[k]);
    } else {
        lua_pushboolean(L, false);
    }
    return 1;
}

static int l_rl_is_key_down(lua_State* L) {
    int k = (int)luaL_checkinteger(L, 1);
    if (k >= 0 && k < 512) {
        lua_pushboolean(L, g_drive_active ? g_drive_key_down[k] : g_keys_down[k]);
    } else {
        lua_pushboolean(L, false);
    }
    return 1;
}

static int l_rl_get_clipboard_text(lua_State* L) {
    const char* txt = win_clipboard_text();
    if (txt) lua_pushstring(L, txt);
    else lua_pushnil(L);
    return 1;
}

static int l_rl_clipboard_file_path(lua_State* L) {
    const char* p = win_clipboard_file_path();
    if (p) lua_pushstring(L, p);
    else lua_pushnil(L);
    return 1;
}

static int l_rl_is_file_dropped(lua_State* L) {
    lua_pushboolean(L, !g_dropped_file.empty());
    return 1;
}

static int l_rl_take_dropped_file(lua_State* L) {
    if (!g_dropped_file.empty()) {
        lua_pushstring(L, g_dropped_file.c_str());
        g_dropped_file.clear();
        return 1;
    }
    return 0;
}

static int l_rl_take_screenshot(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    if (!g_swapchain || !g_d3d_device || !g_d3d_context) return 0;

    ID3D11Texture2D* back_buffer = nullptr;
    g_swapchain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&back_buffer);
    if (!back_buffer) return 0;

    D3D11_TEXTURE2D_DESC desc = {};
    back_buffer->GetDesc(&desc);

    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;

    ID3D11Texture2D* staging = nullptr;
    g_d3d_device->CreateTexture2D(&desc, nullptr, &staging);
    g_d3d_context->CopyResource(staging, back_buffer);
    back_buffer->Release();

    D3D11_MAPPED_SUBRESOURCE mapped;
    if (SUCCEEDED(g_d3d_context->Map(staging, 0, D3D11_MAP_READ, 0, &mapped))) {
        stbi_write_png(path, desc.Width, desc.Height, 4, mapped.pData, mapped.RowPitch);
        g_d3d_context->Unmap(staging, 0);
    }
    staging->Release();
    return 0;
}

static int l_rl_load_model_cylinder(lua_State* L) {
    float rt = (float)luaL_checknumber(L, 1);
    float rb = (float)luaL_checknumber(L, 2);
    float h  = (float)luaL_checknumber(L, 3);
    int slices = (int)luaL_optinteger(L, 4, 16);
    if (slices < 3) slices = 3;

    std::vector<D3DVertex> verts;
    std::vector<uint32_t> indices;
    float hh = h * 0.5f;
    uint32_t top_center_idx = 0;
    verts.push_back({ 0, hh, 0, 1,1,1,1, 0,1,0, 0.5f, 0.5f });
    uint32_t bot_center_idx = 1;
    verts.push_back({ 0, -hh, 0, 1,1,1,1, 0,-1,0, 0.5f, 0.5f });

    uint32_t ring_start = 2;
    for (int i = 0; i <= slices; i++) {
        float angle = (i / (float)slices) * 6.2831853f;
        float ca = std::cos(angle);
        float sa = std::sin(angle);
        float u = (float)i / slices;
        verts.push_back({ rt * ca, hh, rt * sa, 1,1,1,1, 0,1,0, u, 0 });
        verts.push_back({ rb * ca, -hh, rb * sa, 1,1,1,1, 0,-1,0, u, 1 });
    }

    for (int i = 0; i < slices; i++) {
        uint32_t t0 = ring_start + i * 2;
        uint32_t b0 = ring_start + i * 2 + 1;
        uint32_t t1 = ring_start + (i + 1) * 2;
        uint32_t b1 = ring_start + (i + 1) * 2 + 1;
        indices.push_back(top_center_idx); indices.push_back(t1); indices.push_back(t0);
        indices.push_back(bot_center_idx); indices.push_back(b0); indices.push_back(b1);
        indices.push_back(t0); indices.push_back(t1); indices.push_back(b1);
        indices.push_back(t0); indices.push_back(b1); indices.push_back(b0);
    }

    ID3D11Buffer* vb = nullptr;
    ID3D11Buffer* ib = nullptr;
    D3D11_BUFFER_DESC vbd = { (UINT)(verts.size() * sizeof(D3DVertex)), D3D11_USAGE_IMMUTABLE, D3D11_BIND_VERTEX_BUFFER, 0, 0, 0 };
    D3D11_SUBRESOURCE_DATA vdata = { verts.data(), 0, 0 };
    g_d3d_device->CreateBuffer(&vbd, &vdata, &vb);

    D3D11_BUFFER_DESC ibd = { (UINT)(indices.size() * sizeof(uint32_t)), D3D11_USAGE_IMMUTABLE, D3D11_BIND_INDEX_BUFFER, 0, 0, 0 };
    D3D11_SUBRESOURCE_DATA idata = { indices.data(), 0, 0 };
    g_d3d_device->CreateBuffer(&ibd, &idata, &ib);

    D3DModel m = { vb, ib, (int)verts.size(), (int)indices.size(), -1, { 1, 1, 1, 1 } };
    g_models.push_back(m);
    lua_pushinteger(L, (int)g_models.size());
    return 1;
}
static int l_rl_draw_cylinder(lua_State* L) { return 0; }
static int l_rl_draw_cylinder_wires(lua_State* L) { return 0; }
static int l_rl_draw_triangle_3d(lua_State* L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float z1 = (float)luaL_checknumber(L, 3);
    float x2 = (float)luaL_checknumber(L, 4);
    float y2 = (float)luaL_checknumber(L, 5);
    float z2 = (float)luaL_checknumber(L, 6);
    float x3 = (float)luaL_checknumber(L, 7);
    float y3 = (float)luaL_checknumber(L, 8);
    float z3 = (float)luaL_checknumber(L, 9);
    float r = (float)luaL_optinteger(L, 10, 255) / 255.0f;
    float g = (float)luaL_optinteger(L, 11, 255) / 255.0f;
    float b = (float)luaL_optinteger(L, 12, 255) / 255.0f;
    float a = (float)luaL_optinteger(L, 13, 255) / 255.0f;

    D3DVertex v[3] = {
        { x1, y1, z1, r, g, b, a, 0, 1, 0, 0, 0 },
        { x2, y2, z2, r, g, b, a, 0, 1, 0, 1, 0 },
        { x3, y3, z3, r, g, b, a, 0, 1, 0, 0, 1 },
    };
    draw_dynamic_triangles_unlit(v, 3, v4(r, g, b, a));
    return 0;
}

static int l_rl_load_shader(lua_State* L) { lua_pushinteger(L, 1); return 1; }
static int l_rl_unload_shader(lua_State* L) { return 0; }
static int l_rl_set_material_shader(lua_State* L) { return 0; }
static int l_rl_set_material_color(lua_State* L) { return 0; }
static int l_rl_get_shader_location(lua_State* L) { lua_pushinteger(L, 0); return 1; }
static int l_rl_set_shader_value_vec3(lua_State* L) { return 0; }
static int l_rl_set_shader_value_float(lua_State* L) { return 0; }
static int l_rl_debug_material(lua_State* L) {
    lua_pushstring(L, "TEXTURE_EMPTY");
    lua_pushinteger(L, 0);
    return 2;
}
static int l_rl_set_lighting_enabled(lua_State* L) {
    g_lighting_enabled = lua_toboolean(L, 1);
    return 0;
}
static int l_rl_is_lighting_enabled(lua_State* L) {
    lua_pushboolean(L, g_lighting_enabled);
    return 1;
}



// ── Register Raylib Lua Module ──────────────────────────────────────────────
static void rl_register(lua_State* L) {
    lua_getglobal(L, "lp");
    lua_newtable(L);
#define RR(name) lua_pushcfunction(L, l_rl_##name); lua_setfield(L, -2, #name)
    RR(draw_cube);
    RR(draw_cube_wires);
    RR(draw_grid);
    RR(draw_line_3d);
    RR(draw_sphere_wires);
    RR(set_camera);
    RR(get_camera);
    RR(get_ray);
    RR(world_to_screen);
    RR(screen_to_world);
    RR(begin_mode2d);
    RR(end_mode2d);
    RR(draw_texture);
    RR(load_model_cube);
    RR(load_model_mesh);
    RR(draw_model);
    RR(draw_model_wires);
    RR(unload_model);
    RR(set_material_texture);
    RR(load_texture_perlin);
    RR(unload_texture);
    RR(load_model_cylinder);
    RR(draw_cylinder);
    RR(draw_cylinder_wires);
    RR(draw_triangle_3d);
    RR(load_shader);
    RR(set_target_fps);
    RR(get_target_fps);
    RR(get_monitor_refresh_rate);
    RR(unload_shader);
    RR(set_material_shader);
    RR(set_material_color);
    RR(get_shader_location);
    RR(set_shader_value_vec3);
    RR(set_shader_value_float);
    RR(debug_material);
    RR(draw_line_2d);
    RR(draw_sphere);
    RR(draw_circle_lines_2d);
    RR(draw_rect_2d);
    RR(draw_text_2d);
    RR(get_screen_size);
    RR(get_frame_time);
    RR(set_window_size);
    RR(get_monitor_size);
    RR(set_window_position);
    RR(get_window_position);
    RR(set_mouse_cursor);
    RR(is_mouse_button_down);
    RR(is_mouse_button_pressed);
    RR(set_lighting_enabled);
    RR(is_lighting_enabled);
    RR(get_mouse_delta);
    RR(get_mouse_wheel);
    RR(get_mouse_pos);
    RR(is_key_pressed);
    RR(is_key_down);
    RR(get_clipboard_text);
    RR(clipboard_file_path);
    RR(is_file_dropped);
    RR(take_dropped_file);
    RR(take_screenshot);
#undef RR

    lua_pushinteger(L, 0); lua_setfield(L, -2, "MAP_ALBEDO");
    lua_pushinteger(L, 1); lua_setfield(L, -2, "MAP_NORMAL");
    lua_pushinteger(L, 2); lua_setfield(L, -2, "MAP_METALNESS");
    lua_pushinteger(L, 3); lua_setfield(L, -2, "MAP_ROUGHNESS");
    lua_pushinteger(L, 4); lua_setfield(L, -2, "MAP_EMISSION");
    lua_pushinteger(L, 0); lua_setfield(L, -2, "UNIFORM_FLOAT");
    lua_pushinteger(L, 1); lua_setfield(L, -2, "UNIFORM_VEC2");
    lua_pushinteger(L, 2); lua_setfield(L, -2, "UNIFORM_VEC3");

    // Keys
    lua_newtable(L);
#define RK(name, code) lua_pushinteger(L, code); lua_setfield(L, -2, name)
    RK("A", 'A'); RK("B", 'B'); RK("C", 'C'); RK("D", 'D'); RK("E", 'E');
    RK("F", 'F'); RK("G", 'G'); RK("H", 'H'); RK("I", 'I'); RK("J", 'J');
    RK("K", 'K'); RK("L", 'L'); RK("M", 'M'); RK("N", 'N'); RK("O", 'O');
    RK("P", 'P'); RK("Q", 'Q'); RK("R", 'R'); RK("S", 'S'); RK("T", 'T');
    RK("U", 'U'); RK("V", 'V'); RK("W", 'W'); RK("X", 'X'); RK("Y", 'Y');
    RK("Z", 'Z');
    RK("0", '0'); RK("1", '1'); RK("2", '2'); RK("3", '3'); RK("4", '4');
    RK("5", '5'); RK("6", '6'); RK("7", '7'); RK("8", '8'); RK("9", '9');
    RK("Zero", '0'); RK("One", '1'); RK("Two", '2'); RK("Three", '3'); RK("Four", '4');
    RK("Five", '5'); RK("Six", '6'); RK("Seven", '7'); RK("Eight", '8'); RK("Nine", '9');
    RK("F1", VK_F1); RK("F2", VK_F2); RK("F3", VK_F3); RK("F4", VK_F4);
    RK("F5", VK_F5); RK("F6", VK_F6); RK("F7", VK_F7); RK("F8", VK_F8);
    RK("F9", VK_F9); RK("F10", VK_F10); RK("F11", VK_F11); RK("F12", VK_F12);
    RK("Escape", VK_ESCAPE); RK("Space", VK_SPACE); RK("Enter", VK_RETURN);
    RK("LeftControl", VK_LCONTROL); RK("RightControl", VK_RCONTROL);
    RK("LeftShift", VK_LSHIFT); RK("RightShift", VK_RSHIFT);
    RK("LeftAlt", VK_LMENU); RK("RightAlt", VK_RMENU);
    RK("LeftCtrl", VK_LCONTROL); RK("RightCtrl", VK_RCONTROL);
    RK("Ctrl", VK_CONTROL); RK("Shift", VK_SHIFT); RK("Alt", VK_MENU);
#undef RK
    lua_setfield(L, -2, "key");

    lua_pushinteger(L, 0); lua_setfield(L, -2, "MOUSE_LEFT");
    lua_pushinteger(L, 1); lua_setfield(L, -2, "MOUSE_RIGHT");
    lua_pushinteger(L, 2); lua_setfield(L, -2, "MOUSE_MIDDLE");

    lua_pushinteger(L, 0); lua_setfield(L, -2, "CURSOR_DEFAULT");
    lua_pushinteger(L, 1); lua_setfield(L, -2, "CURSOR_RESIZE_EW");
    lua_pushinteger(L, 2); lua_setfield(L, -2, "CURSOR_RESIZE_NS");
    lua_pushinteger(L, 3); lua_setfield(L, -2, "CURSOR_RESIZE_NWSE");
    lua_pushinteger(L, 4); lua_setfield(L, -2, "CURSOR_RESIZE_NESW");
    lua_pushinteger(L, 5); lua_setfield(L, -2, "CURSOR_HAND");
    lua_pushinteger(L, 6); lua_setfield(L, -2, "CURSOR_CROSSHAIR");

    lua_setfield(L, -2, "rl");
    lua_pop(L, 1);
}



static int l_tex_create(lua_State* L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    CanvasTex ct;
    ct.width = w;
    ct.height = h;
    ct.data.assign((size_t)w * h * 4, 255);
    ct.d3d_tex_id = -1;
    g_canvas.push_back(ct);
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
    hardness = std::max(0.0f, std::min(1.0f, hardness));

    int cx = (int)std::floor(x), cy = (int)std::floor(y);
    int rad = (int)std::ceil(radius);
    int x0 = std::max(0, cx - rad);
    int y0 = std::max(0, cy - rad);
    int x1 = std::min(ct->width - 1, cx + rad);
    int y1 = std::min(ct->height - 1, cy + rad);

    unsigned char* px = ct->data.data();
    float ca = a / 255.0f;
    for (int py = y0; py <= y1; py++) {
        for (int pxx = x0; pxx <= x1; pxx++) {
            float dx = pxx - x;
            float dy = py - y;
            float dist = std::sqrt(dx * dx + dy * dy);
            if (dist >= radius) continue;
            float t = 1.0f - dist / radius;
            float af = ca * std::pow(t, hardness);
            unsigned char* p = px + ((size_t)py * ct->width + pxx) * 4;
            p[0] = (unsigned char)(r * af + p[0] * (1.0f - af));
            p[1] = (unsigned char)(g * af + p[1] * (1.0f - af));
            p[2] = (unsigned char)(b * af + p[2] * (1.0f - af));
            p[3] = 255; // Canvas remains fully opaque
        }
    }
    return 0;
}

static int l_tex_get_pixel(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    if (x < 0 || y < 0 || x >= ct->width || y >= ct->height)
        return luaL_error(L, "tex.get_pixel: (%d,%d) out of bounds for %dx%d", x, y, ct->width, ct->height);
    unsigned char* p = ct->data.data() + ((size_t)y * ct->width + x) * 4;
    lua_pushinteger(L, ((lua_Integer)p[0] << 24) | ((lua_Integer)p[1] << 16) | ((lua_Integer)p[2] << 8) | p[3]);
    return 1;
}

static int l_tex_set_pixel(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    uint32_t val = (uint32_t)luaL_checkinteger(L, 4);
    if (x < 0 || y < 0 || x >= ct->width || y >= ct->height)
        return luaL_error(L, "tex.set_pixel: out of bounds");
    unsigned char* p = ct->data.data() + ((size_t)y * ct->width + x) * 4;
    p[0] = (val >> 24) & 0xFF;
    p[1] = (val >> 16) & 0xFF;
    p[2] = (val >> 8) & 0xFF;
    p[3] = val & 0xFF;
    return 0;
}

static int l_tex_clear(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    uint32_t val = (uint32_t)luaL_checkinteger(L, 2);
    unsigned char r = (val >> 24) & 0xFF;
    unsigned char g = (val >> 16) & 0xFF;
    unsigned char b = (val >> 8) & 0xFF;
    unsigned char a = val & 0xFF;
    unsigned char* px = ct->data.data();
    size_t total = (size_t)ct->width * ct->height;
    for (size_t i = 0; i < total; i++) {
        px[i * 4 + 0] = r;
        px[i * 4 + 1] = g;
        px[i * 4 + 2] = b;
        px[i * 4 + 3] = a;
    }
    return 0;
}

static int l_tex_export_png(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    const char* path = luaL_checkstring(L, 2);
    char parent[1024];
    snprintf(parent, sizeof(parent), "%s", path);
    for (char* p = parent + 1; *p; p++) {
        if (*p == '/' || *p == '\\') {
            char save = *p;
            *p = '\0';
            _mkdir(parent);
            *p = save;
        }
    }
    int ok = stbi_write_png(path, ct->width, ct->height, 4, ct->data.data(), ct->width * 4);
    lua_pushboolean(L, ok != 0);
    return 1;
}

static int l_tex_push_undo(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    ct->undo_stack.push_back(ct->data);
    if (ct->undo_stack.size() > 50) ct->undo_stack.erase(ct->undo_stack.begin());
    ct->redo_stack.clear();
    return 0;
}

static int l_tex_pop_undo(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    if (!ct->undo_stack.empty()) {
        ct->redo_stack.push_back(ct->data);
        ct->data = ct->undo_stack.back();
        ct->undo_stack.pop_back();
        lua_pushboolean(L, true);
        return 1;
    }
    lua_pushboolean(L, false);
    return 1;
}

static int l_tex_push_redo(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    ct->redo_stack.push_back(ct->data);
    return 0;
}

static int l_tex_pop_redo(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    if (!ct->redo_stack.empty()) {
        ct->undo_stack.push_back(ct->data);
        ct->data = ct->redo_stack.back();
        ct->redo_stack.pop_back();
        lua_pushboolean(L, true);
        return 1;
    }
    lua_pushboolean(L, false);
    return 1;
}

static int l_tex_can_undo(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    lua_pushboolean(L, !ct->undo_stack.empty());
    return 1;
}

static int l_tex_can_redo(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    lua_pushboolean(L, !ct->redo_stack.empty());
    return 1;
}

static int l_tex_apply_to_model(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    int model_id = (int)luaL_checkinteger(L, 2);
    if (model_id <= 0 || model_id > (int)g_models.size()) return luaL_error(L, "Invalid model id");

    if (ct->d3d_tex_id <= 0) {
        lua_pushinteger(L, (lua_Integer)(ct - g_canvas.data()));
        l_tex_upload(L);
        lua_pop(L, 1);
    }
    g_models[model_id - 1].texture_id = ct->d3d_tex_id;
    return 0;
}

static int l_tex_texture_id(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    if (ct->d3d_tex_id <= 0) {
        lua_pushinteger(L, (lua_Integer)(ct - g_canvas.data()));
        l_tex_upload(L);
        lua_pop(L, 1);
    }
    if (ct->d3d_tex_id > 0 && ct->d3d_tex_id <= (int)g_textures.size()) {
        lua_pushinteger(L, (lua_Integer)(intptr_t)g_textures[ct->d3d_tex_id - 1].srv);
        return 1;
    }
    lua_pushinteger(L, 0);
    return 1;
}

static int l_tex_load_image_from_file(lua_State* L) {
    CanvasTex* ct = canvas_check(L, 1);
    const char* path = luaL_checkstring(L, 2);
    int w = 0, h = 0, comp = 0;
    stbi_uc* data = stbi_load(path, &w, &h, &comp, 4);
    if (!data) {
        lua_pushboolean(L, false);
        return 1;
    }
    ct->data.resize((size_t)ct->width * ct->height * 4);
    for (int y = 0; y < ct->height; y++) {
        for (int x = 0; x < ct->width; x++) {
            int sx = (x * w) / ct->width;
            int sy = (y * h) / ct->height;
            size_t src_idx = ((size_t)sy * w + sx) * 4;
            size_t dst_idx = ((size_t)y * ct->width + x) * 4;
            ct->data[dst_idx + 0] = data[src_idx + 0];
            ct->data[dst_idx + 1] = data[src_idx + 1];
            ct->data[dst_idx + 2] = data[src_idx + 2];
            ct->data[dst_idx + 3] = data[src_idx + 3];
        }
    }
    stbi_image_free(data);
    lua_pushboolean(L, true);
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
    TR(can_undo);
    TR(can_redo);
    TR(apply_to_model);
    TR(texture_id);
    TR(load_image_from_file);
#undef TR
    lua_setfield(L, -2, "tex");
    lua_pop(L, 1);
}

// ── 2D Camera Module (lp.cam2d.*) ───────────────────────────────────────────
static int l_cam2d_set(lua_State* L) {
    g_cam2d.target.x = (float)luaL_checknumber(L, 1);
    g_cam2d.target.y = (float)luaL_checknumber(L, 2);
    g_cam2d.zoom     = (float)luaL_optnumber(L, 3, 1.0);
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

// ── Virtual Drive Module (lp.drive.*) ───────────────────────────────────────
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
    int b = (int)luaL_checkinteger(L, 1);
    bool down = lua_toboolean(L, 2);
    if (b >= 0 && b < 3) {
        if (down && !g_drive_btn[b]) g_drive_btn_pressed[b] = true;
        g_drive_btn[b] = down;
    }
    return 0;
}
static int l_drive_wheel(lua_State* L) {
    g_drive_wheel += (float)luaL_checknumber(L, 1);
    return 0;
}
static int l_drive_key(lua_State* L) {
    int k = (int)luaL_checkinteger(L, 1);
    bool down = lua_toboolean(L, 2);
    if (k >= 0 && k < 512) {
        if (down && !g_drive_key_down[k]) g_drive_key_pressed[k] = true;
        g_drive_key_down[k] = down;
    }
    return 0;
}
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
    lua_pushcfunction(L, l_drive_active); lua_setfield(L, -2, "active");
    lua_pushcfunction(L, l_drive_mouse);  lua_setfield(L, -2, "mouse");
    lua_pushcfunction(L, l_drive_button); lua_setfield(L, -2, "button");
    lua_pushcfunction(L, l_drive_wheel);  lua_setfield(L, -2, "wheel");
    lua_pushcfunction(L, l_drive_key);    lua_setfield(L, -2, "key");
    lua_pushcfunction(L, l_drive_frame);  lua_setfield(L, -2, "frame");
    lua_setfield(L, -2, "drive");
    lua_pop(L, 1);
}

// ── File Helpers (lp.file.*) ────────────────────────────────────────────────
static int l_file_mkdirs(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    char buf[1024];
    snprintf(buf, sizeof(buf), "%s", path);
    for (char* p = buf + 1; *p; p++) {
        if (*p == '/' || *p == '\\') {
            char save = *p;
            *p = '\0';
            _mkdir(buf);
            *p = save;
        }
    }
    _mkdir(buf);
    return 0;
}

static int l_file_exists(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    DWORD attr = GetFileAttributesA(path);
    lua_pushboolean(L, (attr != INVALID_FILE_ATTRIBUTES));
    return 1;
}

static int l_file_list_dir(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    char pattern[1024];
    snprintf(pattern, sizeof(pattern), "%s/*", path);

    WIN32_FIND_DATAA fd;
    HANDLE hFind = FindFirstFileA(pattern, &fd);
    lua_newtable(L); // dirs
    lua_newtable(L); // files
    int nd = 0, nf = 0;

    if (hFind != INVALID_HANDLE_VALUE) {
        do {
            if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) continue;
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                nd++;
                lua_pushstring(L, fd.cFileName);
                lua_rawseti(L, -3, nd);
            } else {
                nf++;
                lua_pushstring(L, fd.cFileName);
                lua_rawseti(L, -2, nf);
            }
        } while (FindNextFileA(hFind, &fd));
        FindClose(hFind);
    }
    return 2;
}

static void file_register(lua_State* L) {
    lua_getglobal(L, "lp");
    lua_newtable(L);
    lua_pushcfunction(L, l_file_mkdirs);   lua_setfield(L, -2, "mkdirs");
    lua_pushcfunction(L, l_file_exists);   lua_setfield(L, -2, "exists");
    lua_pushcfunction(L, l_file_list_dir); lua_setfield(L, -2, "list_dir");
    lua_setfield(L, -2, "file");
    lua_pop(L, 1);
}

// ── Lua VM Init ─────────────────────────────────────────────────────────────
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
    lua_pushcfunction(L_global, [](lua_State* L) -> int {
        const char* p = win_open_file_dialog();
        if (p) lua_pushstring(L, p);
        else lua_pushnil(L);
        return 1;
    });
    lua_setfield(L_global, -2, "open_file_dialog");
    lua_pushcfunction(L_global, [](lua_State* L) -> int {
        lua_pushstring(L, "Direct3D 11 (DXGI Flip Model)");
        return 1;
    });
    lua_setfield(L_global, -2, "backend_name");
    lua_setfield(L_global, -2, "app");
    lua_setglobal(L_global, "lp");

    app_paths::register_lua_bindings(L_global, "Direct3D 11 (DXGI Flip Model)");

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

void lua_shutdown() {
    if (L_global) { lua_close(L_global); L_global = nullptr; }
}

// ── Theme & Fonts ───────────────────────────────────────────────────────────
static void setup_imgui_fonts_and_theme() {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    apply_modern_dark_theme();
    build_imgui_font_atlas();
}

// ── Direct3D 11 Pipeline Setup ──────────────────────────────────────────────
static const char* HLSL_3D_SHADER = R"HLSL(
cbuffer SceneBuffer : register(b0) {
    matrix u_mvp;
    matrix u_model;
    float4 u_ambient;
    float4 u_sun_dir;
    float4 u_sun_color;
    float4 u_color_tint;
    int    u_use_texture;
    int    u_pad[3];
};

struct VSInput {
    float3 pos   : POSITION;
    float4 col   : COLOR;
    float3 norm  : NORMAL;
    float2 uv    : TEXCOORD;
};

struct PSInput {
    float4 pos   : SV_POSITION;
    float4 col   : COLOR;
    float3 norm  : NORMAL;
    float2 uv    : TEXCOORD;
    float3 wpos  : POSITION;
};

PSInput VSMain(VSInput input) {
    PSInput output;
    output.pos  = mul(u_mvp, float4(input.pos, 1.0f));
    output.wpos = mul(u_model, float4(input.pos, 1.0f)).xyz;
    float lnorm = length(input.norm);
    output.norm = lnorm > 0.01f ? normalize(mul((float3x3)u_model, input.norm)) : float3(0, 1, 0);
    output.col  = input.col * u_color_tint;
    output.uv   = input.uv;
    return output;
}

Texture2D g_tex : register(t0);
SamplerState g_sampler : register(s0);

float4 PSMain(PSInput input) : SV_TARGET {
    float4 tex_col = u_use_texture ? g_tex.Sample(g_sampler, input.uv) : float4(1,1,1,1);
    float lnorm = length(input.norm);
    float3 n = lnorm > 0.01f ? normalize(input.norm) : float3(0, 1, 0);
    float3 l1 = normalize(float3(0.5f, 0.8f, 0.6f));
    float3 l2 = normalize(float3(-0.5f, 0.3f, -0.6f));
    float diff1 = max(0.0f, dot(n, l1));
    float diff2 = max(0.0f, dot(n, l2)) * 0.35f;
    float3 lighting = u_ambient.xyz + u_sun_color.xyz * diff1 + float3(0.35f, 0.38f, 0.42f) * diff2 * (u_sun_color.x > 0.01f ? 1.0f : 0.0f);
    float4 final_col = input.col * tex_col;
    return float4(final_col.rgb * min(lighting, float3(1.4f, 1.4f, 1.4f)), 1.0f);
}
)HLSL";

static const char* HLSL_UNLIT_SHADER = R"HLSL(
cbuffer SceneBuffer : register(b0) {
    matrix u_mvp;
    matrix u_model;
    float4 u_ambient;
    float4 u_sun_dir;
    float4 u_sun_color;
    float4 u_color_tint;
    int    u_use_texture;
    int    u_pad[3];
};

struct VSInput {
    float3 pos   : POSITION;
    float4 col   : COLOR;
    float3 norm  : NORMAL;
    float2 uv    : TEXCOORD;
};

struct PSInput {
    float4 pos : SV_POSITION;
    float4 col : COLOR;
};

PSInput VSUnlit(VSInput input) {
    PSInput output;
    output.pos = mul(u_mvp, float4(input.pos, 1.0f));
    output.col = input.col * u_color_tint;
    return output;
}

float4 PSUnlit(PSInput input) : SV_TARGET {
    return input.col;
}
)HLSL";

static void app_init_d3d_pipeline() {
    // Compile 3D shaders
    ID3DBlob* vs_blob = nullptr;
    ID3DBlob* ps_blob = nullptr;
    ID3DBlob* err = nullptr;

    HRESULT hr = D3DCompile(HLSL_3D_SHADER, strlen(HLSL_3D_SHADER), "3DShader", nullptr, nullptr, "VSMain", "vs_4_0", 0, 0, &vs_blob, &err);
    if (FAILED(hr)) {
        if (err) app_log("[D3D11 VS ERR] %s", (char*)err->GetBufferPointer());
    }
    g_d3d_device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nullptr, &g_vs_3d);

    D3D11_INPUT_ELEMENT_DESC layout_desc[] = {
        { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT,    0, 0,  D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "COLOR",    0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "NORMAL",   0, DXGI_FORMAT_R32G32B32_FLOAT,    0, 28, D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT,       0, 40, D3D11_INPUT_PER_VERTEX_DATA, 0 },
    };
    g_d3d_device->CreateInputLayout(layout_desc, 4, vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &g_layout_3d);
    vs_blob->Release();

    hr = D3DCompile(HLSL_3D_SHADER, strlen(HLSL_3D_SHADER), "3DShader", nullptr, nullptr, "PSMain", "ps_4_0", 0, 0, &ps_blob, &err);
    if (FAILED(hr)) {
        if (err) app_log("[D3D11 PS ERR] %s", (char*)err->GetBufferPointer());
    }
    g_d3d_device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nullptr, &g_ps_3d);
    ps_blob->Release();

    // Compile Unlit shaders
    hr = D3DCompile(HLSL_UNLIT_SHADER, strlen(HLSL_UNLIT_SHADER), "Unlit", nullptr, nullptr, "VSUnlit", "vs_4_0", 0, 0, &vs_blob, &err);
    g_d3d_device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nullptr, &g_vs_unlit);
    g_d3d_device->CreateInputLayout(layout_desc, 4, vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &g_layout_unlit);
    vs_blob->Release();

    hr = D3DCompile(HLSL_UNLIT_SHADER, strlen(HLSL_UNLIT_SHADER), "Unlit", nullptr, nullptr, "PSUnlit", "ps_4_0", 0, 0, &ps_blob, &err);
    g_d3d_device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nullptr, &g_ps_unlit);
    ps_blob->Release();

    // Constant buffer
    D3D11_BUFFER_DESC cbd = {};
    cbd.ByteWidth = sizeof(SceneCBuffer);
    cbd.Usage = D3D11_USAGE_DEFAULT;
    cbd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    g_d3d_device->CreateBuffer(&cbd, nullptr, &g_cbuffer_scene);

    // Rasterizer states
    D3D11_RASTERIZER_DESC rd = {};
    rd.FillMode = D3D11_FILL_SOLID;
    rd.CullMode = D3D11_CULL_NONE;
    rd.DepthClipEnable = TRUE;
    rd.AntialiasedLineEnable = TRUE;
    rd.MultisampleEnable = FALSE;
    g_d3d_device->CreateRasterizerState(&rd, &g_raster_solid);

    rd.FillMode = D3D11_FILL_WIREFRAME;
    rd.AntialiasedLineEnable = TRUE;
    rd.MultisampleEnable = FALSE;
    g_d3d_device->CreateRasterizerState(&rd, &g_raster_wire);

    // Depth Stencil States
    D3D11_DEPTH_STENCIL_DESC dsd = {};
    dsd.DepthEnable = TRUE;
    dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL;
    dsd.DepthFunc = D3D11_COMPARISON_LESS_EQUAL;
    g_d3d_device->CreateDepthStencilState(&dsd, &g_depth_state_3d);

    dsd.DepthEnable = FALSE;
    dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
    dsd.DepthEnable = FALSE;
    dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
    g_d3d_device->CreateDepthStencilState(&dsd, &g_depth_state_2d);

    // Overlay Depth Stencil State (Depth read / test enabled, NO depth write)
    dsd.DepthEnable = TRUE;
    dsd.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
    dsd.DepthFunc = D3D11_COMPARISON_LESS_EQUAL;
    g_d3d_device->CreateDepthStencilState(&dsd, &g_depth_state_overlay);

    // Blend State
    D3D11_BLEND_DESC bld = {};
    bld.RenderTarget[0].BlendEnable = TRUE;
    bld.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
    bld.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
    bld.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
    bld.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
    bld.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
    bld.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
    bld.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    g_d3d_device->CreateBlendState(&bld, &g_blend_state);

    // Sampler State
    D3D11_SAMPLER_DESC smpd = {};
    smpd.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    smpd.AddressU = D3D11_TEXTURE_ADDRESS_WRAP;
    smpd.AddressV = D3D11_TEXTURE_ADDRESS_WRAP;
    smpd.AddressW = D3D11_TEXTURE_ADDRESS_WRAP;
    smpd.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
    g_d3d_device->CreateSamplerState(&smpd, &g_sampler_state);
}

// ── Render & Resize ─────────────────────────────────────────────────────────
static void create_render_target(int width, int height) {
    ID3D11Texture2D* back_buffer = nullptr;
    g_swapchain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&back_buffer);
    if (back_buffer) {
        g_d3d_device->CreateRenderTargetView(back_buffer, nullptr, &g_main_rtv);
        back_buffer->Release();
    }

    D3D11_TEXTURE2D_DESC dd = {};
    dd.Width = width;
    dd.Height = height;
    dd.MipLevels = 1;
    dd.ArraySize = 1;
    dd.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
    dd.SampleDesc.Count = 1;
    dd.Usage = D3D11_USAGE_DEFAULT;
    dd.BindFlags = D3D11_BIND_DEPTH_STENCIL;
    g_d3d_device->CreateTexture2D(&dd, nullptr, &g_depth_stencil_tex);
    g_d3d_device->CreateDepthStencilView(g_depth_stencil_tex, nullptr, &g_depth_stencil_view);
}

static void cleanup_render_target() {
    if (g_main_rtv) { g_main_rtv->Release(); g_main_rtv = nullptr; }
    if (g_depth_stencil_view) { g_depth_stencil_view->Release(); g_depth_stencil_view = nullptr; }
    if (g_depth_stencil_tex) { g_depth_stencil_tex->Release(); g_depth_stencil_tex = nullptr; }
}

static void d3d11_handle_resize(int width, int height) {
    if (width <= 0 || height <= 0 || !g_swapchain) return;
    g_win_w = width;
    g_win_h = height;

    cleanup_render_target();
    HRESULT hr = g_swapchain->ResizeBuffers(0, width, height, DXGI_FORMAT_UNKNOWN, 0);
    if (SUCCEEDED(hr)) {
        create_render_target(width, height);
    }
}

static void app_render_frame() {
    if (g_in_render || !g_main_rtv || !g_d3d_context || !g_swapchain) return;
    g_in_render = true;

    // Viewport setup
    D3D11_VIEWPORT vp = {};
    vp.Width = (float)g_win_w;
    vp.Height = (float)g_win_h;
    vp.MinDepth = 0.0f;
    vp.MaxDepth = 1.0f;
    g_d3d_context->RSSetViewports(1, &vp);

    float clear_col[4] = { 24.0f/255.0f, 24.0f/255.0f, 28.0f/255.0f, 1.0f };
    g_d3d_context->ClearRenderTargetView(g_main_rtv, clear_col);
    g_d3d_context->ClearDepthStencilView(g_depth_stencil_view, D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 1.0f, 0);
    g_d3d_context->OMSetRenderTargets(1, &g_main_rtv, g_depth_stencil_view);

    // 1. Render 3D Scene
    lp_call_global("lp_draw3d");

    // 2. Render 2D Canvas (Mode 5)
    lp_call_global("lp_draw2d");

    // 3. ImGui Overlay
    ImGui_ImplDX11_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    if (g_drive_active) {
        ImGuiIO& io = ImGui::GetIO();
        io.AddMousePosEvent(g_drive_mx, g_drive_my);
        io.AddMouseButtonEvent(0, g_drive_btn[0]);
        io.AddMouseButtonEvent(1, g_drive_btn[1]);
        io.AddMouseButtonEvent(2, g_drive_btn[2]);
        if (g_drive_wheel != 0) io.AddMouseWheelEvent(0.0f, g_drive_wheel);
        io.AddKeyEvent(ImGuiMod_Ctrl, g_drive_key_down[VK_LCONTROL] || g_drive_key_down[VK_RCONTROL]);
        io.AddKeyEvent(ImGuiMod_Shift, g_drive_key_down[VK_LSHIFT] || g_drive_key_down[VK_RSHIFT]);
        io.AddKeyEvent(ImGuiMod_Alt, g_drive_key_down[VK_LMENU] || g_drive_key_down[VK_RMENU]);
    }

    lua_frame();

    ImGui::Render();
    g_d3d_context->OMSetRenderTargets(1, &g_main_rtv, g_depth_stencil_view);
    ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());

    // 4. DXGI Flip Model Present: sync interval 1 for VSync, or 0 when using CPU frame limiter
    UINT sync_interval = (g_target_fps <= 0) ? 1 : 0;
    g_swapchain->Present(sync_interval, 0);
    g_in_render = false;
}

// ── Window Procedure ────────────────────────────────────────────────────────
static LRESULT CALLBACK MainWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (ImGui_ImplWin32_WndProcHandler(hwnd, msg, wParam, lParam))
        return true;

    switch (msg) {
        case WM_ENTERSIZEMOVE:
            g_in_sizemove = true;
            return 0;

        case WM_EXITSIZEMOVE:
            g_in_sizemove = false;
            app_render_frame();
            return 0;

        case WM_SIZING: {
            RECT* prc = (RECT*)lParam;
            d3d11_handle_resize(prc->right - prc->left, prc->bottom - prc->top);
            app_render_frame();
            return TRUE;
        }

        case WM_SIZE:
            if (wParam != SIZE_MINIMIZED) {
                d3d11_handle_resize(LOWORD(lParam), HIWORD(lParam));
                if (g_in_sizemove) app_render_frame();
            }
            return 0;

        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(hwnd, &ps);
            app_render_frame();
            EndPaint(hwnd, &ps);
            return 0;
        }

        case WM_MOUSEMOVE: {
            float x = (float)GET_X_LPARAM(lParam);
            float y = (float)GET_Y_LPARAM(lParam);
            g_mouse_dx = x - g_mouse_x;
            g_mouse_dy = y - g_mouse_y;
            g_mouse_x = x;
            g_mouse_y = y;
            return 0;
        }

        case WM_SETCURSOR:
            if (LOWORD(lParam) == HTCLIENT) {
                SetCursor(g_current_cursor ? g_current_cursor : LoadCursor(nullptr, IDC_ARROW));
                return TRUE;
            }
            break;

        case WM_LBUTTONDOWN: g_mouse_down[0] = true; g_mouse_pressed[0] = true; return 0;
        case WM_LBUTTONUP:   g_mouse_down[0] = false; return 0;
        case WM_RBUTTONDOWN: g_mouse_down[1] = true; g_mouse_pressed[1] = true; return 0;
        case WM_RBUTTONUP:   g_mouse_down[1] = false; return 0;
        case WM_MBUTTONDOWN: g_mouse_down[2] = true; g_mouse_pressed[2] = true; return 0;
        case WM_MBUTTONUP:   g_mouse_down[2] = false; return 0;

        case WM_MOUSEWHEEL:
            g_mouse_wheel += (float)GET_WHEEL_DELTA_WPARAM(wParam) / (float)WHEEL_DELTA;
            return 0;

        case WM_KEYDOWN:
        case WM_SYSKEYDOWN:
            if (wParam < 512) {
                bool was_down = (lParam & (1 << 30)) != 0;
                g_keys_down[wParam] = true;
                if (!was_down) {
                    g_keys_pressed[wParam] = true;
                }
            }
            return 0;

        case WM_KEYUP:
        case WM_SYSKEYUP:
            if (wParam < 512) g_keys_down[wParam] = false;
            return 0;

        case WM_DROPFILES: {
            HDROP hDrop = (HDROP)wParam;
            char path[1024] = {};
            if (DragQueryFileA(hDrop, 0, path, sizeof(path))) {
                g_dropped_file = path;
            }
            DragFinish(hDrop);
            return 0;
        }

        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

// ── CLI Helpers ─────────────────────────────────────────────────────────────
static bool has_arg(int argc, char** argv, const char* name) {
    for (int i = 1; i < argc; i++) if (strcmp(argv[i], name) == 0) return true;
    return false;
}
static const char* get_arg(int argc, char** argv, const char* name, const char* def) {
    for (int i = 1; i < argc - 1; i++) if (strcmp(argv[i], name) == 0) return argv[i + 1];
    return def;
}

// ── Main Entry Point ────────────────────────────────────────────────────────
int main(int argc, char** argv) {
    const char* shot_path = get_arg(argc, argv, "--shot", nullptr);
    int shot_frames = atoi(get_arg(argc, argv, "--frames", "20"));
    const char* drive_script = get_arg(argc, argv, "--drive", nullptr);
    bool headless = (shot_path != nullptr);

    // Root resolution
    char root[2048] = ".";
    DWORD attr = GetFileAttributesA("editor/lua/main.lua");
    if (attr == INVALID_FILE_ATTRIBUTES) {
        attr = GetFileAttributesA("lua/main.lua");
        if (attr == INVALID_FILE_ATTRIBUTES) {
            GetModuleFileNameA(nullptr, root, sizeof(root));
            char* p = strrchr(root, '\\');
            if (p) *p = '\0';
            SetCurrentDirectoryA(root);
        }
    }

    if (has_arg(argc, argv, "--test")) {
        lua_init(root);
        const char* candidates[] = { "editor/tests/testmain.lua", "tests/testmain.lua" };
        const char* found = nullptr;
        for (const char* c : candidates) {
            if (GetFileAttributesA(c) != INVALID_FILE_ATTRIBUTES) { found = c; break; }
        }
        if (found) {
            if (luaL_dofile(L_global, found) != LUA_OK) {
                app_log("[TEST ERROR] %s", lua_tostring(L_global, -1));
                lua_shutdown();
                return 1;
            }
        }
        lua_shutdown();
        return 0;
    }

    // Work area query for low-res clamping
    int req_w = 1280;
    int req_h = 800;
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
    g_win_w = req_w;
    g_win_h = req_h;

    WNDCLASSEXW wc = { sizeof(WNDCLASSEXW), CS_CLASSDC, MainWndProc, 0L, 0L,
                       GetModuleHandle(nullptr), nullptr, nullptr, nullptr, nullptr,
                       L"CubeForgeD3D11Class", nullptr };
    RegisterClassExW(&wc);

    DWORD style = WS_OVERLAPPEDWINDOW;
    if (headless) style = WS_POPUP;

    g_hwnd = CreateWindowW(wc.lpszClassName, L"CubeForge — Direct3D 11 + ImGui + Lua",
                           style, 100, 100, req_w, req_h,
                           nullptr, nullptr, wc.hInstance, nullptr);
    if (!g_hwnd) {
        app_log("Failed to create Win32 window");
        return 1;
    }

    DragAcceptFiles(g_hwnd, TRUE);

    // Initialize D3D11 & DXGI Swapchain
    DXGI_SWAP_CHAIN_DESC sd = {};
    sd.BufferCount = 2;
    sd.BufferDesc.Width = req_w;
    sd.BufferDesc.Height = req_h;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = g_hwnd;
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;

    D3D_FEATURE_LEVEL featureLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };
    D3D_FEATURE_LEVEL featureLevel;

    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
        featureLevels, 4, D3D11_SDK_VERSION, &sd,
        &g_swapchain, &g_d3d_device, &featureLevel, &g_d3d_context);

    if (FAILED(hr)) {
        sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
        hr = D3D11CreateDeviceAndSwapChain(
            nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
            featureLevels, 4, D3D11_SDK_VERSION, &sd,
            &g_swapchain, &g_d3d_device, &featureLevel, &g_d3d_context);
    }

    if (FAILED(hr)) {
        app_log("D3D11CreateDeviceAndSwapChain failed: 0x%08lX", (unsigned long)hr);
        return 1;
    }

    create_render_target(req_w, req_h);
    app_init_d3d_pipeline();
    setup_imgui_fonts_and_theme();

    ImGui_ImplWin32_Init(g_hwnd);
    ImGui_ImplDX11_Init(g_d3d_device, g_d3d_context);

    lua_init(root);

    bool drive_loaded = false;
    if (drive_script) {
        char dpath[2048];
        if (strchr(drive_script, '/')) snprintf(dpath, sizeof(dpath), "%s", drive_script);
        else snprintf(dpath, sizeof(dpath), "%s/lua/%s", root, drive_script);
        if (luaL_dofile(L_global, dpath) == LUA_OK) {
            drive_loaded = true;
            lp_call_global("drive_begin");
            app_log("[drive] loaded %s", dpath);
        } else {
            app_log("[drive] LOAD ERROR %s", lua_tostring(L_global, -1));
            lua_pop(L_global, 1);
        }
    }

    if (!headless) {
        ShowWindow(g_hwnd, SW_SHOWDEFAULT);
        UpdateWindow(g_hwnd);
    }

    timeBeginPeriod(1);
    auto prev_time = std::chrono::high_resolution_clock::now();
    int frame = 0;
    bool running = true;

    while (running) {
        auto frame_start = std::chrono::high_resolution_clock::now();

        MSG msg;
        while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                running = false;
                break;
            }
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        if (!running) break;

        auto now = std::chrono::high_resolution_clock::now();
        g_last_frame_time = std::chrono::duration<double>(now - prev_time).count();
        prev_time = now;

        if (drive_loaded) lp_call_global("drive_step");

        app_render_frame();
        frame++;

        // Reset single-frame mouse/key pressed edges
        memset(g_mouse_pressed, 0, sizeof(g_mouse_pressed));
        memset(g_keys_pressed, 0, sizeof(g_keys_pressed));
        g_mouse_dx = 0; g_mouse_dy = 0;
        g_mouse_wheel = 0;

        if (drive_loaded) lp_call_global("drive_frame");

        if (g_target_fps > 0) {
            double target_sec = 1.0 / (double)g_target_fps;
            auto target_deadline = frame_start + std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::duration<double>(target_sec));
            while (std::chrono::high_resolution_clock::now() < target_deadline) {
                auto rem = std::chrono::duration_cast<std::chrono::milliseconds>(target_deadline - std::chrono::high_resolution_clock::now()).count();
                if (rem > 2) Sleep((DWORD)(rem - 1));
                else YieldProcessor();
            }
        }

        if (headless && frame >= shot_frames) {
            lua_pushstring(L_global, shot_path);
            l_rl_take_screenshot(L_global);
            lua_pop(L_global, 1);
            app_log("Screenshot saved to %s", shot_path);
            running = false;
        }
    }

    timeEndPeriod(1);
    lua_shutdown();
    ImGui_ImplDX11_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();

    cleanup_render_target();
    if (g_swapchain) g_swapchain->Release();
    if (g_d3d_context) g_d3d_context->Release();
    if (g_d3d_device) g_d3d_device->Release();
    DestroyWindow(g_hwnd);
    UnregisterClassW(wc.lpszClassName, wc.hInstance);

    return 0;
}
