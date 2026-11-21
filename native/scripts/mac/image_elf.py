"""(longshot-mac) The guest image (<work>/sa/image: image.bin, image.json, functions.json) as an AArch64 ELF for a
disassembler (Ghidra through REA): each module's .text/.rodata/.data a PT_LOAD at its guest address with its rights, its
bss zero-filled, and a symbol table of every function the lifter knows (f_<address>, or the export's own name).
python3 image_elf.py <image dir> <out.elf> [lo-hi ...]
lo-hi (hex guest addresses, any number): only those code ranges, for a disassembler that cannot take the whole image at once
(Ghidra through REA ran out of a 40 GB heap analysing all of it)."""
import json, os, struct, sys

def main(src, out, ranges=()):
    meta = json.load(open(os.path.join(src, 'image.json')))
    funcs = json.load(open(os.path.join(src, 'functions.json')))
    blob = open(os.path.join(src, 'image.bin'), 'rb').read()
    base = meta['base']
    names = {}
    exports = meta.get('exports') or {}
    items = exports.items() if isinstance(exports, dict) else ((e.get('name'), e.get('addr')) for e in exports)
    for name, addr in items:
        if isinstance(addr, int) and name: names.setdefault(addr, name)
    segs = []   # (vaddr, file bytes, memsz, flags, name)
    for m in meta['modules']:
        for s in m['segments']:
            flags = 5 if s['name'] == '.text' else 4 if s['name'] == '.rodata' else 6
            off = s['addr'] - base
            if ranges:
                for lo, hi in ranges:
                    a, b = max(lo, s['addr']), min(hi, s['addr'] + s['size'])
                    if a < b:
                        segs.append((a, blob[a - base:b - base], b - a, flags, '%s%s_%x' % (m['name'], s['name'], a)))
                continue
            segs.append((s['addr'], blob[off:off + s['size']], s['size'], flags, m['name'] + s['name']))
        if not ranges and m.get('bss') and m['bss'][1] > m['bss'][0]:
            segs.append((m['bss'][0], b'', m['bss'][1] - m['bss'][0], 6, m['name'] + '.bss'))
    # sections: null, each segment, .symtab, .strtab, .shstrtab
    shstr = bytearray(b'\0')
    def sname(n):
        o = len(shstr); shstr.extend(n.encode() + b'\0'); return o
    strtab = bytearray(b'\0')
    syms = [struct.pack('<IBBHQQ', 0, 0, 0, 0, 0, 0)]
    seg_index = lambda a: next((i + 1 for i, s in enumerate(segs) if s[0] <= a < s[0] + s[2]), 0)
    for k, v in sorted(funcs.items(), key=lambda kv: int(kv[0], 16)):
        a = int(k, 16)
        if ranges and not seg_index(a): continue
        n = names.get(a) or 'f_%x' % a
        no = len(strtab); strtab.extend(n.encode() + b'\0')
        size = (v[0] * 4) if isinstance(v, list) and v and isinstance(v[0], int) else 0
        syms.append(struct.pack('<IBBHQQ', no, 0x12, 0, seg_index(a), a, size))   # (STB_GLOBAL, STT_FUNC)
    ehdr_size, ph_size, sh_size = 64, 56, 64
    phoff = ehdr_size
    data_off = (phoff + ph_size * len(segs) + 0xfff) & ~0xfff
    layout, cur = [], data_off
    for s in segs:
        cur = (cur + 0xfff) & ~0xfff
        cur += (s[0] - cur) % 0x1000   # (file offset congruent to the address, page-wise)
        layout.append(cur); cur += len(s[1])
    sym_off = (cur + 7) & ~7; symbytes = b''.join(syms)
    str_off = sym_off + len(symbytes)
    sec_names = [sname(s[4]) for s in segs]
    n_sym, n_str, n_shstr = sname('.symtab'), sname('.strtab'), sname('.shstrtab')
    shstr_off = str_off + len(strtab)
    shoff = (shstr_off + len(shstr) + 7) & ~7
    nsec = 1 + len(segs) + 3
    with open(out, 'wb') as f:
        f.write(b'\x7fELF' + bytes([2, 1, 1, 0]) + b'\0' * 8)
        entry = next((m.get('init') or m['base'] for m in meta['modules'] if m['name'] == 'main'), base)
        f.write(struct.pack('<HHIQQQIHHHHHH', 2, 183, 1, entry, phoff, shoff, 0, ehdr_size, ph_size, len(segs), sh_size, nsec, nsec - 1))
        for s, off in zip(segs, layout):
            f.write(struct.pack('<IIQQQQQQ', 1, s[3], off if s[1] else 0, s[0], s[0], len(s[1]), s[2], 0x1000))
        for s, off in zip(segs, layout):
            f.seek(off); f.write(s[1])
        f.seek(sym_off); f.write(symbytes); f.write(strtab); f.write(shstr)
        f.seek(shoff)
        f.write(b'\0' * sh_size)
        for s, off, no in zip(segs, layout, sec_names):
            typ = 8 if not s[1] else 1
            fl = 2 | (4 if s[3] & 1 else 0) | (1 if s[3] & 2 else 0)
            f.write(struct.pack('<IIQQQQIIQQ', no, typ, fl, s[0], off if s[1] else 0, s[2], 0, 0, 16, 0))
        nseg = len(segs)
        f.write(struct.pack('<IIQQQQIIQQ', n_sym, 2, 0, 0, sym_off, len(symbytes), nseg + 2, 1, 8, 24))
        f.write(struct.pack('<IIQQQQIIQQ', n_str, 3, 0, 0, str_off, len(strtab), 0, 0, 1, 0))
        f.write(struct.pack('<IIQQQQIIQQ', n_shstr, 3, 0, 0, shstr_off, len(shstr), 0, 0, 1, 0))
    print('%s: %d segments, %d symbols' % (out, len(segs), len(syms) - 1))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], [tuple(int(x, 16) for x in r.split('-')) for r in sys.argv[3:]])
