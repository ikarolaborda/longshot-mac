#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate host/mtl_nvn_sigs.h from third_party/d2r_gfx/gfx/nvn/nvn_protos.h.

One row per NVN function: which integer-register arguments are guest pointers (moved into host memory before the
call), which are guest function pointers (callbacks), how many integer arguments go past x7 (read from the guest
stack), and what the result is. The Metal layer's functions take host pointers; Longshot's lifted code passes guest
addresses. mtl_nvn_glue.c reads this table to move one into the other.

usage: gen_nvn_glue.py [protos.h] [out.h]
"""
import os
import re
import sys

POINTER_TYPEDEFS = {"NVNnativeWindow"}           # typedefs of pointers (checked with __builtin_classify_type)
CALLBACK_TYPEDEFS = {"PFNNVNCOMMANDBUFFERMEMORYCALLBACKPROC", "PFNNVNDEBUGCALLBACKPROC",
                     "PFNNVNWALKDEBUGDATABASECALLBACKPROC"}
FLOATS = {"float", "double"}
# nvn_protos.h spells these three as returning NVNmemoryPool by value; NVN returns const NVNmemoryPool *
POINTER_RESULTS = {"nvnBufferBuilderGetMemoryPool", "nvnTextureBuilderGetMemoryPool", "nvnTextureGetMemoryPool"}
RAW_RESULTS = {"nvnDeviceGetProcAddress", "nvnBootstrapLoader"}   # already a guest address (runtime_hle_wrap_named)


def kind(t):
    t = t.replace("const ", "").strip()
    if t in CALLBACK_TYPEDEFS or t == "PFNNVNGENERICFUNCPTRPROC":
        return "fn"
    if re.search(r"\*\s*(const\s*)?\*", t):
        return "parr"   # an array of guest pointers: its count is the nearest integer argument before it that is no array
    if "*" in t or t in POINTER_TYPEDEFS:
        return "ptr"
    if t in FLOATS:
        return "fp"
    return "int"


def split_args(text):
    """Top-level comma split (function-pointer parameters carry their own parentheses)."""
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
            continue
        depth += ch == "("
        depth -= ch == ")"
        cur += ch
    out.append(cur)
    return [x.strip() for x in out]


TYPE_WORDS = {"int", "float", "double", "char", "void", "size_t", "ptrdiff_t", "unsigned", "long", "short", "const"}


def strip_name(a):
    """'NVNbuffer *b' -> 'NVNbuffer *'; 'int n' -> 'int'; an unnamed 'int' or 'NVNformat' stays."""
    if "(" in a:
        return a
    words = a.replace("*", " * ").split()
    if len(words) >= 2 and words[-1] != "*" and words[-1] not in TYPE_WORDS and re.fullmatch(r"[a-z_]\w*", words[-1]):
        words = words[:-1]
    return " ".join(words).replace(" * ", "*").replace(" *", "*")


def implementations(src):
    """{name: (ret, "args")} from NVN, NVN_NOPROTO and NVN_EXTRA implementations"""
    found = {}
    for m in re.finditer(r"^NVN(?:_NOPROTO|_EXTRA)?\(", src, re.M):
        depth, i = 1, m.end()
        while i < len(src) and depth:
            depth += src[i] == "("
            depth -= src[i] == ")"
            i += 1
        parts = split_args(src[m.end():i - 1])
        if len(parts) >= 2 and re.fullmatch(r"\w+", parts[0]):
            args = [strip_name(a) for a in parts[2:]]
            found[parts[0]] = (parts[1], ", ".join(args))
    return found


def main():
    protos = sys.argv[1] if len(sys.argv) > 1 else "third_party/d2r_gfx/gfx/nvn/nvn_protos.h"
    out = sys.argv[2] if len(sys.argv) > 2 else "host/mtl_nvn_sigs.h"
    rx = re.compile(r"typedef\s+(.+?)\s*\(\*NVNT_(\w+)\)\((.*?)\);")
    sigs = {name: (ret, args) for ret, name, args in rx.findall(open(protos).read())}
    # the implementations' own signatures (NVN(name, ret, args) and NVN_NOPROTO(...) in gfx/nvn): what is really
    # called, including the functions nvn_protos.h has no prototype for
    impl_dir = os.path.dirname(protos)
    for f in sorted(os.listdir(impl_dir)):
        if f.endswith((".c", ".m")):
            sigs.update(implementations(open(os.path.join(impl_dir, f), errors="replace").read()))
    rows = []
    for name, (ret, args) in sorted(sigs.items()):
        ptr = fn = arr = 0
        ni = nf = 0
        for a in [x for x in split_args(args) if x and x != "void"]:
            k = kind(a)
            if k == "fp":
                if nf >= 8:
                    raise SystemExit(f"{name}: more than 8 floating-point arguments")
                nf += 1
                continue
            if k == "parr":
                ptr |= 1 << ni
                arr |= 1 << ni
            elif k == "ptr":
                ptr |= 1 << ni
            elif k == "fn":
                fn |= 1 << ni
            ni += 1
        if ni > 16:
            raise SystemExit(f"{name}: more than 16 integer arguments")
        if name in RAW_RESULTS:
            r = "MTL_RET_RAW"
        elif name in POINTER_RESULTS or kind(ret) == "ptr":
            r = "MTL_RET_PTR"
        elif ret.strip() == "void":
            r = "MTL_RET_VOID"
        elif kind(ret) == "fp":
            r = "MTL_RET_FP"
        elif kind(ret) == "fn":
            r = "MTL_RET_RAW"
        else:
            r = "MTL_RET_INT"
        rows.append((name, ptr, fn, arr, ni, r))
    rows.sort()
    with open(out, "w") as f:
        f.write("/* Generated by scripts/mac/gen_nvn_glue.py from nvn_protos.h; do not edit. */\n#pragma once\n")
        f.write("/* name, guest-pointer integer arguments (bit i: argument i), callback arguments, pointer-array arguments\n"
                "   (their elements are guest pointers too; the count is the argument before), integer argument count, result */\n")
        f.write("static const MtlNvnSig mtl_nvn_sigs[] = {\n")
        for name, ptr, fn, arr, ni, r in rows:
            f.write(f'    {{"{name}", {ptr:#x}, {fn:#x}, {arr:#x}, {ni}, {r}}},\n')
        f.write("};\n")
    print(f"{len(rows)} signatures -> {out}")


if __name__ == "__main__":
    main()
