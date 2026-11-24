"""Build button artwork from the player's game with an isolated set of image tools."""
from pathlib import Path
import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys

NX2 = Path(__file__).resolve().parents[2] / "nx2"
REQUIREMENTS = NX2 / "prompt_requirements.txt"


def prompt_python(work):
    modules = ("fontTools", "PIL", "numpy", "zstandard", "astc_encoder", "texture2ddecoder")
    if all(importlib.util.find_spec(name) for name in modules):
        return sys.executable
    # Use a Python supported by the image encoder's Mac wheels when available.
    interpreter = shutil.which("python3.11") or shutil.which("python3.12") or sys.executable
    digest = hashlib.sha256(REQUIREMENTS.read_bytes() + os.fsencode(os.path.realpath(interpreter))).hexdigest()[:16]
    env = Path(work) / ("mac-prompt-tools-" + digest)
    python = env / "bin/python"
    if not (env / "ready").exists():
        subprocess.run([interpreter, "-m", "venv", env], check=True)
        subprocess.run([python, "-I", "-m", "pip", "install", "--disable-pip-version-check",
                        "-r", REQUIREMENTS, "numpy", "zstandard"], check=True)
        (env / "ready").touch()
    return python


if __name__ == "__main__":
    work, romfs, out = sys.argv[1:]
    subprocess.run([prompt_python(work), "-I", NX2 / "prompt_assets.py", "--romfs", romfs,
                    "--out", out, "--incremental"], check=True)
