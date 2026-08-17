# Image attachments on text-only models (auto-described)

When the active model has no vision support, omp automatically replaces an
attached/pasted image with a vision-model description in this form:

    <image path="local://image-<hash>.png">
    <description of the image, produced by a vision model>
    </image>

Rules:

1. The description inside the block IS the image content. Do NOT call
   inspect_image (or read the local:// path) just because the block exists —
   the image was already described by a vision model; re-inspecting wastes a
   round trip and adds nothing.
2. Only inspect the saved file when you need a specific detail the block does
   not cover (exact wording, small text, coordinates, precise layout) and the
   user asks for it.
3. If the block has an empty description, treat the image as unavailable and
   tell the user the description failed, or use `vision <path>` to retry.

# Vision vs. text-only models & xd:// devices

1. **Vision-capable models (e.g. Gemini, Claude)**:
   - Have native image support (`input: [text, image]`).
   - Receive image attachments and `read` tool outputs directly as native image payloads.
   - `inspect_image` is automatically deactivated (not mounted under `xd://`) because native vision handles images directly without routing through external vision endpoints.

2. **Text-only models (e.g. DeepSeek)**:
   - Lack native image input (`input: [text]`).
   - Pasted/attached images are auto-described into `<image path="local://...">` blocks using the configured `vision` model role (OpenRouter qwen3.7-flash, local lame fallback).
   - `inspect_image` is automatically mounted under `xd://inspect_image` to delegate ad-hoc image inspection to the `vision` model role:
     `write(path="xd://inspect_image", content={"path": "/tmp/shot.png", "question": "…"})`

3. **Other discoverable xd:// devices (browser, ast_edit, lsp, debug)**:
   - Available across sessions and invoked by writing JSON args to `xd://<tool>`.
