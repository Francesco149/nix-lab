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

# xd:// devices (inspect_image, browser, ast_edit, lsp, debug) ARE AVAILABLE

The named-function tool list does NOT show these — they are xd:// devices and
are invoked by WRITING their JSON args to the device path with the write tool:

    write(path="xd://inspect_image", content={"path": "/tmp/shot.png", "question": "…"})

This works in every session: vision goes through the `vision` model role
(OpenRouter qwen3.7-flash, local lame fallback — see /opt/src/nix-lab/AGENTS.md).
Do NOT conclude "no vision in this session" from the function list. If a write
to xd://inspect_image errors with a schema complaint, fix the args and retry;
only if the device itself is rejected is the route actually missing (then use
the `vision` CLI per AGENTS.md and report it).

Same pattern for the other devices: xd://ast_edit, xd://debug, xd://lsp,
xd://browser (read the device doc first for its schema).
