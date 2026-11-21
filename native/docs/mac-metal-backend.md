# Native Metal renderer for the Mac port

Longshot draws through Vulkan. On the Mac that means MoltenVK, which translates every Vulkan call and shader to Metal at runtime. Measured on OoT 131072 (M5, macOS 26):

- About 990 shader programs fail translation (descriptor aliasing) and their draws are skipped.
- Compute programs that bind more than Metal's 31 buffers fail, and their passes are skipped.
- 8-bit index draws are converted per draw into temporary buffers held until the submission finishes. Loading Kokiri Forest from a save grew that pool to about 48 GB, and Metal failed the command buffer (`kIOGPUCommandBufferCallbackErrorOutOfMemory`, reported as `VK_ERROR_DEVICE_LOST`).
- Every pipeline is translated to Metal source and compiled again at each start: about 15 minutes before the title when all of them are prepared first.

The native renderer replaces that layer with a direct NVN-to-Metal implementation.

## Source

The NVN-to-Metal layer of MacNativeGames, `d2r_gfx` (MIT; `nvn_tex.c` adapts deko3d, zlib-style), copied with its notices into `third_party/d2r_gfx`. MacNativeGames runs OoT 131072 on it into Kokiri Forest and the village. Shaders are translated ahead of time from the game's own data (Ryujinx's shader translator emits Metal source) and compiled into Metal libraries at build time, so nothing is compiled while the game runs.

## How it fits

Both projects take over `nvnBootstrapLoader` and hand the game a table of NVN functions by name. With `RX_RENDERER=metal`, Longshot's `nvnBootstrapLoader` returns `d2r_gfx`'s table instead of `host/nvn_native.c`'s.

The difference is addressing. MacNativeGames runs the game at its real addresses. Longshot's lifted code reaches guest memory at `A64_MEM + address`, and calls functions through a `Ctx` of registers. A generated layer sits between them, one entry per NVN function, from `nvn_protos.h`:

1. Arguments in `x0`-`x7`, `d0`-`d7` per the AArch64 calling convention, read from `Ctx`.
2. Pointer arguments: guest to host (`+ A64_MEM`, null stays null).
3. Pointer results (`nvnMemoryPoolMap`, `nvnBufferMap` and the like): host to guest.
4. Function-pointer arguments (debug and out-of-memory callbacks): a host trampoline that calls the guest function through the lifted-code dispatcher.

## Milestones

1. Vendor `d2r_gfx`, build it into the Mac game binary, generate the glue, and route `nvnBootstrapLoader` to it under `RX_RENDERER=metal`. Done when the game reaches the title with Metal clearing and presenting frames.
2. Shader corpus: extract, translate and compile the game's shaders at build time into a Metal library bundle beside the game. Done when the title renders correctly.
3. Gameplay: New Game and a save both load Kokiri Forest, rendered correctly, at 120 fps.
4. Longshot's own overlay on Metal: the menu (Cheats, About, Controls), the FPS counter and screenshots.
5. MoltenVK stays available as `RX_RENDERER=vulkan` until the Metal renderer is the default.
