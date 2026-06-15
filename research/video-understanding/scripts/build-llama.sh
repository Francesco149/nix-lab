#!/usr/bin/env bash
# Build llama-mtmd-cli + llama-bench from upstream llama.cpp with native video
# (MTMD_VIDEO) support. Run THIS ON the inference host (lame) — it needs the
# host's nixpkgs + GPU toolchain. It deliberately skips the web UI (npm/PWA/
# playwright build) which is not needed for the CLI/bench and breaks in the Nix
# sandbox.
#
#   Usage: build-llama.sh <vulkan|cuda> [rev] [srcdir]
#
# Notes:
#  - Native video landed upstream in 8f83d6c (2026-06-08); the default rev below
#    is HEAD as of 2026-06-14. nixpkgs llama-cpp (b9503, 2026-06-04) predates it,
#    which is why we build from source. Once nixpkgs crosses ~b9510 this whole
#    script can be replaced by `pkgs.llama-cpp` + ffmpeg in PATH.
#  - CUDA arch 86 = RTX 3080 (Ampere). Change for other cards.
set -euo pipefail
BACKEND="${1:?usage: build-llama.sh <vulkan|cuda> [rev] [srcdir]}"
REV="${2:-6e9007ae61f4e994c27484759caac6ef2aa32b30}"
SRC="${3:-/tmp/llama.cpp}"
BUILD="$SRC/build-$BACKEND"

if [ ! -e "$SRC/CMakeLists.txt" ]; then
  mkdir -p "$SRC"; cd "$SRC"; git init -q
  git remote add origin https://github.com/ggml-org/llama.cpp 2>/dev/null || true
  git fetch -q --depth 1 origin "$REV"
  git checkout -q FETCH_HEAD
fi

COMMON_FLAGS="-DGGML_NATIVE=ON -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_TESTS=OFF \
 -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=ON -DLLAMA_CURL=OFF \
 -DMTMD_VIDEO=ON -DCMAKE_BUILD_TYPE=Release"

if [ "$BACKEND" = cuda ]; then
  export NIXPKGS_ALLOW_UNFREE=1
  # Use the CUDA backend-stdenv so nvcc gets a host gcc it actually supports.
  exec nix-shell --impure -E '
    with import <nixpkgs> { config.allowUnfree = true; config.cudaSupport = true; };
    cudaPackages.backendStdenv.mkDerivation {
      name = "llama-cuda-shell";
      nativeBuildInputs = [ cmake ninja git pkg-config
        cudaPackages.cuda_nvcc cudaPackages.cuda_cudart cudaPackages.libcublas cudaPackages.cuda_cccl ];
    }' --run "cmake -B '$BUILD' -G Ninja -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 $COMMON_FLAGS \
      && cmake --build '$BUILD' --target llama-mtmd-cli llama-bench -j"
else
  exec nix-shell -p cmake ninja gcc shaderc vulkan-headers vulkan-loader glslang git \
    --run "cmake -B '$BUILD' -G Ninja -DGGML_VULKAN=ON $COMMON_FLAGS \
      && cmake --build '$BUILD' --target llama-mtmd-cli llama-bench -j"
fi
