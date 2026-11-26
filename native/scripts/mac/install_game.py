"""Build from private copies of the game inputs and install the selected Mac release."""
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

from package_app import METAL_FILES, clone


def copy_build_inputs(source, game):
    game.mkdir()
    # Some prepared builds link to shader packs with numbered image files beside them.
    # Resolve those links at their original location before staging independent copies.
    for name in (".longshot_exefs", "romfs", ".longshot_installed.json", ".longshot_romfs",
                 ".longshot_romfs_checked", "longshot_options.ini", "language.txt", "mods.json",
                 "modcache", "libSDL3.0.dylib", "libSDL2-2.0.0.dylib", "renhdrum.dylib",
                 "longshot_title.txt", "longshot_icon.png"):
        path = source / name
        if path.exists():
            clone(path, game / name)
    metal = game / "metal/build"
    metal.mkdir(parents=True)
    for name in METAL_FILES:
        src = source / "metal/build" / name
        if src.exists():
            real = src.resolve(strict=True)
            clone(real, metal / name)
            for part in real.parent.glob(real.name + ".img.[0-9][0-9][0-9]"):
                clone(part, metal / part.name)


def existing_player(support):
    profiles = []
    for name in ("Longshot", "Longshot Metal Preview"):
        app = support / name
        prefs = app / "installation.plist"
        configured = plistlib.loads(prefs.read_bytes()).get("DataHome") if prefs.is_file() else None
        player = (Path(configured) if configured else app / "UserData") / "longshot"
        slots = list((player / "save").glob("*/slot_*/progress.sav"))
        if slots:
            profiles.append((max(path.stat().st_mtime_ns for path in slots), player))
    return max(profiles, key=lambda row: row[0])[1] if profiles else None


def manifest(player):
    files = [path for path in (player / "save").rglob("*") if path.is_file()]
    if (player / "trainer.json").is_file():
        files.append(player / "trainer.json")
    return {path.relative_to(player): hashlib.sha256(path.read_bytes()).digest() for path in files}


def import_saves(support):
    home = support / "Longshot Experimental/UserData"
    dest = home / "longshot"
    if dest.exists():
        return
    source = existing_player(support)
    if source is None:
        return
    home.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=home, prefix=".import-") as folder:
        staged = Path(folder) / "longshot"
        for _ in range(3):
            before = manifest(source)
            if staged.exists():
                shutil.rmtree(staged)
            staged.mkdir()
            shutil.copytree(source / "save", staged / "save")
            if (source / "trainer.json").is_file():
                shutil.copy2(source / "trainer.json", staged / "trainer.json")
            if before == manifest(staged) == manifest(source):
                if not dest.exists():
                    try:
                        staged.rename(dest)
                    except OSError:
                        if not dest.is_dir():
                            raise
                return
        raise RuntimeError("The source saves changed during the copy. Run the installer again after saving.")


def main():
    source = Path(sys.argv[1]).resolve(strict=True)
    tag = sys.argv[2]
    with tempfile.TemporaryDirectory(prefix="longshot-install-build-") as folder:
        game = Path(folder) / "game"
        copy_build_inputs(source, game)
        subprocess.run([sys.executable, "-I", "nx2/make_game.py", "--update", game, "--no-prepare-shaders"], check=True)
        package = [sys.executable, "scripts/mac/package_app.py", game]
        if "-metal-experimental." in tag:
            import_saves(Path.home() / "Library/Application Support")
            package.extend(["--experimental-release", tag])
        elif tag:
            package.extend(["--stable-release", tag])
        subprocess.run(package, check=True)


if __name__ == "__main__":
    main()
