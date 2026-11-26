# Longshot for macOS

The native Apple silicon game and its Metal renderer are in the [native source tree](native).
The original launcher and its build tools are also available.

## Native game

Download the Mac installer and checksum from [Releases](../../releases), unzip the installer, and open it. Choose your existing macOS Longshot game build when prompted. The installer rebuilds the game from your files and installs `/Applications/Longshot.app`. Keep the original build folder for future updates.

The build needs Xcode command-line tools, a Python environment that can run the original builder, and the libraries used by your macOS build, including SDL and the audio/video libraries. The native game renders and draws its settings menu with Metal. It uses the Ocarina of Time shader service and shader data from your prepared game folder.

### Side-by-side Metal preview

From the native source directory on this branch, rebuild a copy of your prepared game folder with `python3 -I nx2/make_game.py --update "/path/to/game-copy" --no-prepare-shaders`. Then run `python3 scripts/mac/package_app.py "/path/to/game-copy" --preview`. The preview installs in `~/Applications/Longshot Metal Preview.app` and keeps its saves, settings and caches under `~/Library/Application Support/Longshot Metal Preview`.

## Original launcher

Grab `LongshotLauncher-macOS-arm64.app.zip` from the
[Releases](../../releases) page, unzip, and drop `LongshotLauncher.app`
into `/Applications`. No .NET installation required — the app is a
self-contained single-file binary (the whole .NET 10 runtime and all
dependencies are embedded).

The launcher will look for your game file (the Ocarina of Time `.nup`,
title ID `04004860224DEC000`) and build/run the game normally.

## What this port does

- **Full Metal rendering** — the UI renders through Avalonia's native macOS
  backend (Metal compositor + Skia's Metal backend).
- **Vulkan 1.3+ over Metal** — the bundled/linked MoltenVK layer satisfies the
  game's Vulkan requirement, so an Apple Silicon Mac is reported as a fully
  capable machine: *Vulkan 1.3 · GPU VRAM · Mesh shaders available*.
- Native arm64 single-file executable; universal-ready native libraries
  (arm64 + x86_64).

## Vulkan support in the original launcher

The launcher checks for Vulkan 1.3 (the game's renderer). On macOS this is
provided by [MoltenVK](https://github.com/KhronosGroup/MoltenVK):

```sh
brew install molten-vk
sudo mkdir -p /usr/local/lib
sudo ln -sf /opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib /usr/local/lib/libvulkan.dylib
```

(A copy of MoltenVK also ships inside the app bundle; the symlink above makes
it discoverable for raw terminal launches. `LSEnvironment` in the app already
points dyld at `/usr/local/lib` and `/opt/homebrew/lib`.)

## How it was built (reverse engineering)

1. **AppImage unpack** — the squashfs payload was located at ELF offset
   944632 (computed from the section header table) and extracted.
2. **.NET single-file bundle parsed** — custom parser for the bundle
   manifest (206 entries) extracted all managed assemblies, deps.json and
   runtimeconfig.json.
3. **Architecture surgery** — the linux-x64 ReadyToRun entry assembly was
   re-stamped as AnyCPU IL (JIT fallback), and all runtime assemblies were
   replaced with the official osx-arm64 .NET 10.0.15 runtime pack.
4. **IL patches (Mono.Cecil)** on `LongshotLauncher.Core.dll`:
   - Vulkan library name: `libvulkan.dylib` instead of `libvulkan.so.1`
   - X64/Windows/glibc OS gate removed (Apple Silicon allowed)
   - Vulkan interop delegates: `Winapi` → `Cdecl` (Winapi segfaults under
     MoltenVK on .NET/macOS arm64)
   - Requested Vulkan instance version 1.1 → 1.3 (MoltenVK clamps its
     reported device version to the requested one)
   - Mesh-shader capability reported true (Apple GPU family 9 exposes Metal
     mesh threads; MoltenVK does not yet surface `VK_EXT_mesh_shader`)
5. **Repack** — everything packed into an osx-arm64 `singlefilehost` with
   compression and ad-hoc code signing, wrapped as a `.app` with the
   original icon.

The tooling used is in [`build-tools/`](build-tools/) (`ilpatch/` = Cecil
patcher, `bundler/` = Microsoft.NET.HostModel bundler).

## Credits

- Nintendo created the original game.
- MagicBeanDev and contributors maintain Longshot. [Longshot project](https://git.magicbean.dev/MagicBeanDev/Longshot)
- NotRexed and contributors created Hookshot, the predecessor to Longshot.
- jhaizhou and MacNativeGames contributors developed the Metal renderer.
- Avalonia, .NET, and MoltenVK are credited to their respective projects.

**MacOS version By Ikaro Laborda**

[GitHub repository](https://github.com/ikarolaborda/longshot-mac) · [Sponsor Ikaro Laborda](https://github.com/sponsors/ikarolaborda)

*Longshot Launcher is © its authors; this repository only distributes the
macOS repackaging and patch tooling.*
