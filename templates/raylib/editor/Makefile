# editor/Makefile — cubeforge-raylib
IMGUI ?= $(IMGUI_DIR)
LUA   ?= $(LUA_SRC)

BUILD := ../build
OBJ   := $(BUILD)/obj-linux
OUT   := $(BUILD)/cubeforge-raylib

# Windows cross (mingw)
WIN_OUT := $(BUILD)/cubeforge-raylib.exe
WIN_OBJ := $(BUILD)/obj-win

SRC := src/main.cpp src/ig.cpp src/app_paths.cpp
TINYFD_C := src/vendor/tinyfiledialogs/tinyfiledialogs.c

IMGUI_CORE := imgui.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp imgui_stdlib.cpp
RLIMGUI_SRC := src/vendor/rlImGui/rlImGui.cpp

LUA_C := $(filter-out $(LUA)/src/lua.c $(LUA)/src/luac.c,$(wildcard $(LUA)/src/*.c))

RAYLIB_CFLAGS := -I$(RAYLIB_INC)
RAYLIB_LIBS := -L$(RAYLIB_LIB) -lraylib -lm -ldl -lpthread -lGL \
  -Wl,-rpath,$(RAYLIB_LIB)

CXXFLAGS := -std=c++17 -O2 -g -Wall -Wno-unknown-pragmas \
  -I src -I $(BUILD) -I $(IMGUI) -I $(IMGUI)/misc/cpp \
  -I $(LUA)/src \
  -I src/vendor/rlImGui \
  -I src/vendor/tinyfiledialogs \
  $(RAYLIB_CFLAGS)

OBJ_CXX := $(addprefix $(OBJ)/,$(notdir $(SRC:.cpp=.o)) \
             $(IMGUI_CORE:.cpp=.o) rlImGui.o tinyfiledialogs.o)
OBJ_LUA := $(addprefix $(OBJ)/lua/,$(notdir $(LUA_C:.c=.o)))

linux: $(OUT)
$(OUT): $(OBJ_CXX) $(OBJ_LUA) | $(BUILD)
	$(CXX) $(OBJ_CXX) $(OBJ_LUA) -o $(OUT) -static-libgcc -static-libstdc++ $(RAYLIB_LIBS)
	@echo "built $(OUT)"

$(OBJ)/%.o: src/%.cpp src/editor.h | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@
$(OBJ)/tinyfiledialogs.o: $(TINYFD_C) | $(OBJ)
	$(CC) -O2 -std=gnu11 -I src/vendor/tinyfiledialogs -c $< -o $@
$(OBJ)/%.o: $(IMGUI)/%.cpp | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@
$(OBJ)/%.o: $(IMGUI)/misc/cpp/%.cpp | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@
$(OBJ)/rlImGui.o: src/vendor/rlImGui/rlImGui.cpp | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@
$(OBJ)/lua/%.o: $(LUA)/src/%.c | $(OBJ)/lua
	$(CC) -O2 -std=c11 -I $(LUA)/src -c $< -o $@

# ── Windows cross (mingw) ────────────────────────────────────────────────────
# raylib 6.0 from pkgsCross.mingwW64: import lib (libraylib.dll.a) + runtime
# DLL (bin/libraylib.dll). raylib bundles its own GLFW; link the Win32 system
# libs raylib needs. Static C/C++ runtime; libmcfgthread shipped by package.
WIN_CXX := $(MINGW_CXX)
WIN_CC   := $(MINGW_CC)

WIN_CXXFLAGS := $(CXXFLAGS) -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -DUNICODE -D_UNICODE \
  -I $(RAYLIB_CROSS_INC)
WIN_LDFLAGS := -static-libgcc -static-libstdc++
WIN_LIBS := -L$(RAYLIB_CROSS_LIB) -lraylib \
  -lopengl32 -lgdi32 -lwinmm -luser32 -lshell32 -lcomdlg32 \
  -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic \
  -ldwmapi -lole32 -lsetupapi

WIN_OBJ_CXX := $(addprefix $(WIN_OBJ)/,$(notdir $(SRC:.cpp=.o)) \
                 $(IMGUI_CORE:.cpp=.o) rlImGui.o tinyfiledialogs.o winclip.o)
WIN_OBJ_LUA := $(addprefix $(WIN_OBJ)/lua/,$(notdir $(LUA_C:.c=.o)))

win: package

$(WIN_OUT): $(WIN_OBJ_CXX) $(WIN_OBJ_LUA) | $(BUILD)
	$(WIN_CXX) $(WIN_OBJ_CXX) $(WIN_OBJ_LUA) -o $(WIN_OUT) $(WIN_LDFLAGS) $(WIN_LIBS)
	@echo "built $(WIN_OUT)"

$(WIN_OBJ)/%.o: src/%.cpp src/editor.h | $(WIN_OBJ)
	$(WIN_CXX) $(WIN_CXXFLAGS) -c $< -o $@
$(WIN_OBJ)/tinyfiledialogs.o: $(TINYFD_C) | $(WIN_OBJ)
	$(WIN_CC) -O2 -std=gnu11 -I src/vendor/tinyfiledialogs -c $< -o $@
$(WIN_OBJ)/winclip.o: src/winclip.c | $(WIN_OBJ)
	$(WIN_CC) -O2 -std=c11 -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -DUNICODE -D_UNICODE -c $< -o $@
$(WIN_OBJ)/%.o: $(IMGUI)/%.cpp | $(WIN_OBJ)
	$(WIN_CXX) $(WIN_CXXFLAGS) -c $< -o $@
$(WIN_OBJ)/%.o: $(IMGUI)/misc/cpp/%.cpp | $(WIN_OBJ)
	$(WIN_CXX) $(WIN_CXXFLAGS) -c $< -o $@
$(WIN_OBJ)/rlImGui.o: src/vendor/rlImGui/rlImGui.cpp | $(WIN_OBJ)
	$(WIN_CXX) $(WIN_CXXFLAGS) -c $< -o $@
$(WIN_OBJ)/lua/%.o: $(LUA)/src/%.c | $(WIN_OBJ)/lua
	$(WIN_CC) -O2 -std=c11 -I $(LUA)/src -c $< -o $@

# Standalone folder: exe + raylib DLL + glfw DLL + mcfgthread DLL + lua/ + tests/
package: $(WIN_OUT)
	mkdir -p $(BUILD)/cubeforge-raylib-win64
	rm -f $(BUILD)/cubeforge-raylib-win64/libraylib.dll $(BUILD)/cubeforge-raylib-win64/glfw3.dll $(BUILD)/cubeforge-raylib-win64/libmcfgthread-2.dll
	cp $(WIN_OUT) $(BUILD)/cubeforge-raylib-win64/
	cp $(RAYLIB_CROSS_DLL) $(BUILD)/cubeforge-raylib-win64/
	cp $(GLFW_CROSS_DLL) $(BUILD)/cubeforge-raylib-win64/
	cp $(MCFG_DLL) $(BUILD)/cubeforge-raylib-win64/
	rm -rf $(BUILD)/cubeforge-raylib-win64/lua $(BUILD)/cubeforge-raylib-win64/tests $(BUILD)/cubeforge-raylib-win64/assets
	cp -r ../editor/lua $(BUILD)/cubeforge-raylib-win64/lua
	cp -r ../editor/tests $(BUILD)/cubeforge-raylib-win64/tests
	mkdir -p $(BUILD)/cubeforge-raylib-win64/assets/fonts
	cp $(FONT_LATIN) $(BUILD)/cubeforge-raylib-win64/assets/fonts/InterVariable.ttf
	cp $(FONT_CJK) $(BUILD)/cubeforge-raylib-win64/assets/fonts/ipag.ttf
	@echo "packaged $(BUILD)/cubeforge-raylib-win64/"


# ── Direct3D 11 Windows target ───────────────────────────────────────────────
WIN_D3D11_OUT := $(BUILD)/cubeforge-d3d11.exe
WIN_D3D11_OBJ := $(BUILD)/obj-win-d3d11

WIN_D3D11_CXXFLAGS := -std=c++17 -O2 -g -Wall -Wno-unknown-pragmas \
  -I src -I $(BUILD) -I $(IMGUI) -I $(IMGUI)/misc/cpp -I $(IMGUI)/backends \
  -I $(LUA)/src -I $(STB_INC) \
  -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -DUNICODE -D_UNICODE

WIN_D3D11_LIBS := -ld3d11 -ldxgi -ld3dcompiler -lgdi32 -luser32 -lshell32 -lole32 \
  -ldwmapi -lcomdlg32 -lwinmm -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic

D3D11_SRC_OBJS := $(WIN_D3D11_OBJ)/main_d3d11.o $(WIN_D3D11_OBJ)/ig.o $(WIN_D3D11_OBJ)/app_paths.o $(WIN_D3D11_OBJ)/winclip.o \
  $(WIN_D3D11_OBJ)/imgui.o $(WIN_D3D11_OBJ)/imgui_draw.o $(WIN_D3D11_OBJ)/imgui_tables.o \
  $(WIN_D3D11_OBJ)/imgui_widgets.o $(WIN_D3D11_OBJ)/imgui_stdlib.o \
  $(WIN_D3D11_OBJ)/imgui_impl_win32.o $(WIN_D3D11_OBJ)/imgui_impl_dx11.o

WIN_D3D11_OBJ_LUA := $(addprefix $(WIN_D3D11_OBJ)/lua/,$(notdir $(LUA_C:.c=.o)))

win-d3d11: package-d3d11

$(WIN_D3D11_OUT): $(D3D11_SRC_OBJS) $(WIN_D3D11_OBJ_LUA) | $(BUILD)
	$(WIN_CXX) $(D3D11_SRC_OBJS) $(WIN_D3D11_OBJ_LUA) -o $(WIN_D3D11_OUT) $(WIN_LDFLAGS) $(WIN_D3D11_LIBS)
	@echo "built $(WIN_D3D11_OUT)"

$(WIN_D3D11_OBJ)/%.o: src/%.cpp src/editor.h | $(WIN_D3D11_OBJ)
	$(WIN_CXX) $(WIN_D3D11_CXXFLAGS) -c $< -o $@
$(WIN_D3D11_OBJ)/winclip.o: src/winclip.c | $(WIN_D3D11_OBJ)
	$(WIN_CC) -O2 -std=c11 -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -DUNICODE -D_UNICODE -c $< -o $@
$(WIN_D3D11_OBJ)/%.o: $(IMGUI)/%.cpp | $(WIN_D3D11_OBJ)
	$(WIN_CXX) $(WIN_D3D11_CXXFLAGS) -c $< -o $@
$(WIN_D3D11_OBJ)/%.o: $(IMGUI)/misc/cpp/%.cpp | $(WIN_D3D11_OBJ)
	$(WIN_CXX) $(WIN_D3D11_CXXFLAGS) -c $< -o $@
$(WIN_D3D11_OBJ)/%.o: $(IMGUI)/backends/%.cpp | $(WIN_D3D11_OBJ)
	$(WIN_CXX) $(WIN_D3D11_CXXFLAGS) -c $< -o $@
$(WIN_D3D11_OBJ)/lua/%.o: $(LUA)/src/%.c | $(WIN_D3D11_OBJ)/lua
	$(WIN_CC) -O2 -std=c11 -I $(LUA)/src -c $< -o $@

package-d3d11: $(WIN_D3D11_OUT)
	mkdir -p $(BUILD)/cubeforge-d3d11-win64
	rm -f $(BUILD)/cubeforge-d3d11-win64/libmcfgthread-2.dll
	cp $(WIN_D3D11_OUT) $(BUILD)/cubeforge-d3d11-win64/
	cp $(MCFG_DLL) $(BUILD)/cubeforge-d3d11-win64/
	rm -rf $(BUILD)/cubeforge-d3d11-win64/lua $(BUILD)/cubeforge-d3d11-win64/tests $(BUILD)/cubeforge-d3d11-win64/assets
	cp -r ../editor/lua $(BUILD)/cubeforge-d3d11-win64/lua
	cp -r ../editor/tests $(BUILD)/cubeforge-d3d11-win64/tests
	mkdir -p $(BUILD)/cubeforge-d3d11-win64/assets/fonts
	cp $(FONT_LATIN) $(BUILD)/cubeforge-d3d11-win64/assets/fonts/InterVariable.ttf
	cp $(FONT_CJK) $(BUILD)/cubeforge-d3d11-win64/assets/fonts/ipag.ttf
	@echo "packaged $(BUILD)/cubeforge-d3d11-win64/"

# Standalone Linux package: binary + lua/ + tests/ + assets/fonts/
package-linux: $(OUT)
	mkdir -p $(BUILD)/cubeforge-raylib-linux
	cp $(OUT) $(BUILD)/cubeforge-raylib-linux/
	rm -rf $(BUILD)/cubeforge-raylib-linux/lua $(BUILD)/cubeforge-raylib-linux/tests $(BUILD)/cubeforge-raylib-linux/assets
	cp -r ../editor/lua $(BUILD)/cubeforge-raylib-linux/lua
	cp -r ../editor/tests $(BUILD)/cubeforge-raylib-linux/tests
	mkdir -p $(BUILD)/cubeforge-raylib-linux/assets/fonts
	cp $(FONT_LATIN) $(BUILD)/cubeforge-raylib-linux/assets/fonts/InterVariable.ttf
	cp $(FONT_CJK) $(BUILD)/cubeforge-raylib-linux/assets/fonts/ipag.ttf
	@echo "packaged $(BUILD)/cubeforge-raylib-linux/"

# Standalone ZIP distributions
zip-linux: package-linux
	cd $(BUILD) && python3 -m zipfile -c cubeforge-raylib-linux.zip cubeforge-raylib-linux
	@echo "Created $(BUILD)/cubeforge-raylib-linux.zip"

zip-win: package
	cd $(BUILD) && python3 -m zipfile -c cubeforge-raylib-win64.zip cubeforge-raylib-win64
	@echo "Created $(BUILD)/cubeforge-raylib-win64.zip"

zip-d3d11: package-d3d11
	cd $(BUILD) && python3 -m zipfile -c cubeforge-d3d11-win64.zip cubeforge-d3d11-win64
	@echo "Created $(BUILD)/cubeforge-d3d11-win64.zip"

zip-all: zip-linux zip-win zip-d3d11
	@echo "All 3 standalone distributions zipped in $(BUILD)/"


$(WIN_D3D11_OBJ):
	mkdir -p $(WIN_D3D11_OBJ)
$(WIN_D3D11_OBJ)/lua:
	mkdir -p $(WIN_D3D11_OBJ)/lua
$(BUILD):
	mkdir -p $(BUILD)
$(OBJ):
	mkdir -p $(OBJ)
$(OBJ)/lua:
	mkdir -p $(OBJ)/lua
$(WIN_OBJ):
	mkdir -p $(WIN_OBJ)
$(WIN_OBJ)/lua:
	mkdir -p $(WIN_OBJ)/lua

# ── Headless verification (no window focus, no input injection tools) ───────
run: linux
	cd .. && ./build/cubeforge-raylib

# Headless screenshot: hidden window, N frames, PNG out
shot: linux
	cd .. && ./build/cubeforge-raylib --shot build/shot.png --frames 20

# Headless drive + capture: inject a right-drag orbit, assert the camera moved
shot-drive: linux
	cd .. && ./build/cubeforge-raylib --shot build/shot_orbit.png --frames 40 --drive editor/tests/drive_orbit.lua

# Headless drive + capture: 2D texture-paint mode, assert MMB pan moved the 2D camera
shot-pan: linux
	cd .. && ./build/cubeforge-raylib --shot build/shot_pan.png --frames 30 --drive editor/tests/drive_pan.lua

# Headless drive + capture: paint a stroke in 2D, exit to 3D, assert canvas is
# bound to the cube — the shot must show painted marks on the cube (2D↔3D)
shot-paint: linux
	cd .. && ./build/cubeforge-raylib --shot build/shot_paint3d.png --frames 24 --drive editor/tests/drive_paint3d.lua

# Headless drive + capture: image-import pipeline (export → import round-trip,
# rejection of bad paths) — same code path as drag&drop / paste / file picker
shot-import: linux
	cd .. && ./build/cubeforge-raylib --shot build/shot_import.png --frames 10 --drive editor/tests/drive_import.lua

# Headless drive + capture: panel resize via the in-window splitter (latched)
shot-resize: linux
	cd .. && ./build/cubeforge-raylib --shot build/shot_resize.png --frames 18 --drive editor/tests/drive_resize.lua

# Headless drive + capture: in-app file browser modal renders (file picker)
shot-browser: linux
	cd .. && ./build/cubeforge-raylib --shot build/shot_browser.png --frames 12 --drive editor/tests/drive_browser.lua

# Headless drive + capture: autonomous dynamic window resize test across resolutions
shot-win-resize: linux
	cd .. && ./build/cubeforge-raylib --shot build/shot_win_resize.png --frames 55 --drive editor/tests/drive_window_resize.lua

# Headless boot + binding checks
test: linux
	cd .. && ./build/cubeforge-raylib --test

# Windows: run the packaged exe from a Windows path (WSLInterop)
win-run-d3d11: package-d3d11
	powershell.exe -Command "& '$$(wslpath -w $(abspath $(BUILD)/cubeforge-d3d11-win64/cubeforge-d3d11.exe))' --test"

clean:
	rm -rf $(OBJ) $(WIN_OBJ) $(WIN_D3D11_OBJ) $(OUT) $(WIN_OUT) $(WIN_D3D11_OUT) $(BUILD)/cubeforge-raylib-win64 $(BUILD)/cubeforge-d3d11-win64

.PHONY: linux win win-d3d11 package package-d3d11 package-linux zip-linux zip-win zip-d3d11 zip-all clean run shot shot-drive shot-pan shot-paint shot-import shot-resize shot-browser shot-win-resize test win-run win-run-d3d11