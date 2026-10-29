# H.264 decoder for the app (GDExtension)

The live view streams H.264 (only the changes between frames travel: ~20 KB/s instead of ~500 KB/s of JPEG at
30 fps), so the app reaches 30/60 fps on a slow server uplink. Godot has no H.264 decoder, so this adds one.

- `h264bsd/` — Baseline H.264 decoder from the Android Open Source Project (Apache 2.0, see `h264bsd/LICENSE.md`),
  via github.com/oneam/h264bsd. Unmodified.
- `tt_h264.c` — decodes one access unit → RGBA picture (cropped to the display size).
- `gd_h264.c` — plain-C GDExtension registering `H264Decoder` (RefCounted): `decode()`, `get_width()`,
  `get_height()`, `get_rgba()`. Used by `native/stream_source.gd`; without the library the app falls back to JPEG.
- `include/gdextension_interface.h` — from `godot --dump-gdextension-interface` (Godot 4.7.2).
- `macos-shim/` — minimal libc headers to build the macOS library without the Apple SDK.

Build all platforms into `native/h264/bin/`: `bash scripts/build-h264.sh` (the built libraries are committed).
