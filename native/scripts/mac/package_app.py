#!/usr/bin/env python3
"""Make a signed native macOS game app from the player's own compiled Longshot folder."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import plistlib
import uuid
import subprocess
import tempfile

APP_ID = "dev.longshot.game"
BACKENDS = ("longshot_vk.dylib", "longshot_mtl.dylib", "renhdrum.dylib", "libSDL3.0.dylib", "libSDL2-2.0.0.dylib")
GAME_FILES = ("romfs", "image.bin", "texts", "longshot_shaders.bin", "longshot_pipeline_states_shipped.bin",
              "longshot_version.txt", "longshot_options.ini", "language.txt")
METAL_FILES = ("c1_bounded.tsv", "compute-manifest.json", "pipelines", "pool_sources.tsv", "pso_manifest.tsv",
               "pso_title.tsv", "shader-libs", "shader-map.tsv", "shader-seed", "shader-service")


def run(*args):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE).stdout


def clone(source, dest):
    # APFS clones local game assets without another download or duplicate disk space.
    run("/bin/cp", "-cRLp", source, dest)


def make_app_icon(resources):
    source = Path(__file__).resolve().parents[2] / "assets/longshot.png"
    icon = resources / "Longshot.icns"
    with tempfile.TemporaryDirectory() as folder:
        iconset = Path(folder) / "Longshot.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale, suffix in ((1, ""), (2, "@2x")):
                pixels = str(points * scale)
                png = iconset / f"icon_{points}x{points}{suffix}.png"
                run("/usr/bin/sips", "-z", pixels, pixels, source, "--out", png)
        run("/usr/bin/iconutil", "-c", "icns", "-o", icon, iconset)
    return icon.name


def dependencies(path):
    lines = run("otool", "-arch", "arm64", "-L", path).splitlines()[1:]
    return [line.strip().split(" (", 1)[0] for line in lines]


def libraries(exe, game, contents):
    frameworks = contents / "Frameworks"
    frameworks.mkdir()
    loader = Path(run("brew", "--prefix", "vulkan-loader").strip()) / "lib/libvulkan.dylib"
    mesa = Path(run("brew", "--prefix", "mesa").strip())
    icd = json.loads(next((mesa / "share/vulkan/icd.d").glob("kosmickrisp*json")).read_text())
    driver = Path(icd["ICD"]["library_path"])
    if not driver.is_absolute():
        driver = mesa / "lib" / driver.name
    names = {}
    pending = []
    def add(source):
        real = source.resolve(strict=True)
        if real not in names:
            name = source.name
            if name in names.values():
                raise ValueError(f"Two different libraries are named {name}")
            names[real] = name
            pending.append(real)
        return names[real]
    for name in BACKENDS:
        add(game / name)
        (exe.parent / name).symlink_to(Path("../Frameworks") / name)
    add(loader)
    icd["ICD"]["library_path"] = "../Frameworks/" + add(driver)
    (contents / "Resources/kosmickrisp.json").write_text(json.dumps(icd, indent=2) + "\n")
    pending.append((game / "longshot").resolve())
    while pending:
        original = pending.pop()
        is_exe = original == (game / "longshot").resolve()
        dest = exe if is_exe else frameworks / names[original]
        clone(original, dest)
        dest.chmod(0o755)
        edits = [] if is_exe else ["-id", "@loader_path/" + dest.name]
        # otool lists a dylib's own install ID first.
        for dependency in dependencies(original)[0 if is_exe else 1:]:
            if dependency.startswith(("/System/", "/usr/lib/")):
                continue
            path = Path(dependency)
            if dependency.startswith(("@rpath/", "@loader_path/")):
                path = original.parent / path.name
            if not path.is_absolute() or not path.is_file():
                raise ValueError(f"Unresolved {dependency} in {original.name}")
            prefix = "@executable_path/../Frameworks/" if is_exe else "@loader_path/"
            edits.extend(["-change", dependency, prefix + add(path)])
        if edits:
            run("install_name_tool", *edits, dest)
        run("codesign", "--force", "--sign", "-", dest)


def install_app(staged, output):
    # Finder uses the bundle's modification time to refresh its cached icon.
    os.utime(staged, None)
    if not output.exists():
        staged.rename(output)
        return
    # Swap names in one operation on the destination filesystem. Launch Services
    # always sees a complete, signed bundle, including if installation is interrupted.
    swap = ctypes.CDLL(None, use_errno=True).renamex_np
    swap.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
    if swap(os.fsencode(staged), os.fsencode(output), 2):  # RENAME_SWAP, sys/stdio.h
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path, help="updated macOS game build")
    parser.add_argument("--output", type=Path, default=Path("/Applications/Longshot.app"))
    parser.add_argument("--data-home", type=Path, help="existing XDG data folder containing longshot/save")
    args = parser.parse_args()
    game, output = args.game.resolve(), args.output.absolute()
    if output.exists():
        if output.is_symlink() or not (output / "Contents/Info.plist").is_file():
            parser.error(f"{output} is not an installed Longshot game")
        info = plistlib.loads((output / "Contents/Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != APP_ID:
            parser.error(f"{output} belongs to another application")
    if args.data_home and not (args.data_home / "longshot/save").is_dir():
        parser.error("--data-home must contain the existing longshot/save folder")
    if "hos_mac_bundle_setup" not in run("nm", "-gU", game / "longshot"):
        parser.error("Rebuild the game using this release before packaging it.")
    versionfile = game / "longshot_version.txt"
    version = next((line.split("=", 1)[1] for line in versionfile.read_text().splitlines()
                    if line.startswith("version=")), "3.0.0").lstrip("v").split("-")[0]
    # The sealed application contains executable code. Locally built game assets live
    # in Application Support, away from Gatekeeper's per-file application inspection.
    data_root = Path.home() / "Library/Application Support/Longshot/GameData"
    data_root.mkdir(parents=True, exist_ok=True)
    data_name = str(uuid.uuid4())
    with tempfile.TemporaryDirectory(dir=data_root, prefix=".install-") as data_stage, \
         tempfile.TemporaryDirectory(dir=output.parent, prefix=".longshot-package-") as folder:
        app = Path(folder) / output.name
        contents = app / "Contents"
        exe = contents / "MacOS/longshot"
        exe.parent.mkdir(parents=True)
        (contents / "Resources").mkdir()
        icon_name = make_app_icon(contents / "Resources")
        clone(Path(__file__).with_name("resources") / "Credits.rtf", contents / "Resources/Credits.rtf")
        assets = Path(data_stage) / "Game"
        assets.mkdir()
        for name in GAME_FILES:
            clone(game / name, assets / name)
        for name in ("longshot_title.txt", "longshot_icon.png"):
            if (game / name).exists():
                clone(game / name, assets / name)
        metal = assets / "metal/build"
        metal.mkdir(parents=True)
        for name in METAL_FILES:
            source = game / "metal/build" / name
            if source.exists():
                target = metal
                if name in ("shader-seed", "shader-libs"):
                    target = contents / "Resources/Metal"
                    target.mkdir(exist_ok=True)
                clone(source, target / name)
                # Packed shader images are siblings of the resolved seed directory.
                real = source.resolve()
                for part in sorted(real.parent.glob(real.name + ".img.[0-9][0-9][0-9]")):
                    clone(part, target / part.name)
        libraries(exe, game, contents)
        info = dict(CFBundleIdentifier=APP_ID, CFBundleExecutable=exe.name, CFBundleName="Longshot",
                    CFBundleIconFile=icon_name,
                    CFBundleDisplayName="Longshot", CFBundlePackageType="APPL", CFBundleVersion=version,
                    CFBundleShortVersionString=version, NSHighResolutionCapable=True, LongshotDataDirectory=data_name,
                    LSApplicationCategoryType="public.app-category.adventure-games",
                    NSMicrophoneUsageDescription="Use the microphone during game actions that require it.")
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        run("codesign", "--force", "--sign", "-", app)
        run("codesign", "--verify", "--strict", app)
        installed_assets = data_root / data_name
        assets.rename(installed_assets)
        try:
            install_app(app, output)
        except OSError:
            installed_assets.rename(assets)
            raise
    if args.data_home:
        prefs = Path.home() / "Library/Application Support/Longshot/installation.plist"
        prefs.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=prefs.parent, delete=False) as f:
            plistlib.dump(dict(DataHome=str(args.data_home.resolve())), f)
        os.replace(f.name, prefs)
    print(output)


if __name__ == "__main__":
    main()
