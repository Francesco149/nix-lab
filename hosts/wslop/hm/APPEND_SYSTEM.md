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
