"""Compile the shared Longshot settings menu and the Metal renderer for macOS."""
from pathlib import Path
import ui_fonts


def jobs(root, obj_dir, gen_dir, target_flags, cc, cxx, version, tree_headers, system_deps):
    root, generated = Path(root), Path(gen_dir)
    gpu = root / "gpu"
    shared = gpu / "vk"
    metal = gpu / "mtl"
    imgui = root / "third_party/imgui"
    font_source = generated / "ui_fonts.cpp"
    ui_fonts.write(str(font_source))
    includes = [root / "host/posix", shared, shared / "compat", imgui, generated,
                root / "third_party/zbic", root / "third_party/zstd", metal]
    common = target_flags + ["-O2", "-g0", "-fPIC", "-fvisibility=hidden", "-DNDEBUG",
                             "-DIMGUI_DISABLE_DEFAULT_SHELL_FUNCTIONS", "-DIMGUI_DISABLE_WIN32_FUNCTIONS",
                             "-DIMGUI_DISABLE_DEMO_WINDOWS", "-DIMGUI_DISABLE_DEBUG_TOOLS", "-DLONGSHOT_METAL_MENU"]
    common += ["-I" + str(directory) for directory in includes]
    deps = tree_headers(str(metal), str(shared), str(imgui), str(root / "host"), str(root / "third_party/zbic")) + system_deps
    sources = [metal / "mtl_main.m", metal / "metal_menu.mm", metal / "menu_device.cpp", imgui / "backends/imgui_impl_metal.mm",
               font_source, *(imgui / (name + ".cpp") for name in ("imgui", "imgui_draw", "imgui_tables", "imgui_widgets")),
               *(shared / (name + ".cpp") for name in ("menu_model", "vk_menu", "vk_imgui", "vk_menu_i18n", "vk_version", "vk_bug_report")),
               *sorted((shared / "menu").glob("*.cpp"))]
    built = []
    for src in sources:
        flags = list(common)
        if src.suffix in (".m", ".mm"):
            flags.append("-fobjc-arc")
        if src.suffix != ".m":
            flags.extend(["-std=c++20", "-include", "algorithm", "-include", "functional"])
        if src.name == "vk_version.cpp":
            flags.append(version)
        obj = str(Path(obj_dir) / ("metal_" + src.name + ".o"))
        built.append((cc if src.suffix == ".m" else cxx, str(src), obj, flags, deps))
    return built
