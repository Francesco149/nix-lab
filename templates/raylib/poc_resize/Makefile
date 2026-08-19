# poc_resize/Makefile — cross-build raylib OGL resize PoCs (mingw, via flake devshell)
BUILD := ../build/poc
CC  := x86_64-w64-mingw32-gcc

CFLAGS := -O2 -g -Wall -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 \
  -I $(RAYLIB_CROSS_INC)

LIBS := -L $(RAYLIB_CROSS_LIB) -lraylib \
  -lopengl32 -lgdi32 -lwinmm -luser32 -lshell32 -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic

BINS := $(BUILD)/poc_min.exe $(BUILD)/poc_imgui.exe $(BUILD)/poc_lua.exe

all: $(BINS)

	mkdir -p $(BUILD)


# stage 2: rlImGui. Needs IMGUI_DIR + rlImGui vendor sources.
CXX := x86_64-w64-mingw32-g++
CXXFLAGS := $(CFLAGS) -std=c++17 -I $(IMGUI_DIR) -I editor/../editor/src/vendor/rlImGui -I ../editor/src/vendor/rlImGui
IMGUI_SRC := $(IMGUI_DIR)/imgui.cpp $(IMGUI_DIR)/imgui_draw.cpp $(IMGUI_DIR)/imgui_tables.cpp $(IMGUI_DIR)/imgui_widgets.cpp
RLIMGUI_SRC := ../editor/src/vendor/rlImGui/rlImGui.cpp

$(BUILD)/poc_imgui.exe: poc_imgui.cpp $(RLIMGUI_SRC) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(RLIMGUI_SRC) $(IMGUI_SRC) -o $@ $(LIBS) -static-libgcc -static-libstdc++
LUA_C := $(filter-out $(LUA_SRC)/src/lua.c $(LUA_SRC)/src/luac.c,$(wildcard $(LUA_SRC)/src/*.c))
LUA_OBJS := $(addprefix $(BUILD)/,$(notdir $(LUA_C:.c=.lo)))

$(BUILD)/%.lo: $(LUA_SRC)/src/%.c | $(BUILD)
	$(CC) -O2 -I $(LUA_SRC)/src -c $< -o $@

$(BUILD)/poc_lua.exe: poc_lua.cpp $(RLIMGUI_SRC) $(LUA_OBJS) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(RLIMGUI_SRC) $(IMGUI_SRC) $(LUA_OBJS) -o $@ $(LIBS) -static-libgcc -static-libstdc++

$(BUILD)/%.exe: %.cpp | $(BUILD)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)

stage:
	cp $(RAYLIB_CROSS_DLL) $(GLFW_CROSS_DLL) $(MCFG_DLL) $(BUILD)/

clean:
	rm -rf $(BUILD)

.PHONY: all stage clean
