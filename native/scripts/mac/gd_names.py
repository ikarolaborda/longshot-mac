"""(longshot-mac) GameData flag names from their hashes: the GameData list keeps only MurmurHash3_x86_32 (seed 0) hashes of
the names, so names are recovered by hashing every printable string found in the guest image and the RomFS's text files
and keeping the ones that match. python3 gd_names.py <gdl.json> <out.json> <file or dir>..."""
import json, os, re, sys

def murmur3(data, seed=0):
    c1, c2 = 0xcc9e2d51, 0x1b873593
    h = seed
    n = len(data) & ~3
    for i in range(0, n, 4):
        k = int.from_bytes(data[i:i + 4], 'little')
        k = (k * c1) & 0xffffffff; k = ((k << 15) | (k >> 17)) & 0xffffffff; k = (k * c2) & 0xffffffff
        h ^= k; h = ((h << 13) | (h >> 19)) & 0xffffffff; h = (h * 5 + 0xe6546b64) & 0xffffffff
    k = 0
    tail = data[n:]
    if len(tail) >= 3: k ^= tail[2] << 16
    if len(tail) >= 2: k ^= tail[1] << 8
    if len(tail) >= 1:
        k ^= tail[0]; k = (k * c1) & 0xffffffff; k = ((k << 15) | (k >> 17)) & 0xffffffff; k = (k * c2) & 0xffffffff; h ^= k
    h ^= len(data)
    h ^= h >> 16; h = (h * 0x85ebca6b) & 0xffffffff; h ^= h >> 13; h = (h * 0xc2b2ae35) & 0xffffffff; h ^= h >> 16
    return h

TOKEN = re.compile(rb'[A-Za-z_][A-Za-z0-9_.\[\]]{2,95}')

DICTS = {}   # (the RomFS's zstd dictionaries, from Pack/ZsDic.pack.zs: --dicts <dir> with zs.zsdic, pack.zsdic, bcett.byml.zsdic)

def load(path):
    data = open(path, 'rb').read()
    if not path.endswith('.zs'):
        return data
    from compression import zstd
    name = os.path.basename(path)
    key = 'bcett.byml.zsdic' if name.endswith('.bcett.byml.zs') else 'pack.zsdic' if name.endswith('.pack.zs') else 'zs.zsdic'
    for d in (DICTS.get(key), None):
        try:
            return zstd.decompress(data, zstd_dict=zstd.ZstdDict(d) if d else None)
        except Exception:
            continue
    return b''

def strings_of(path):
    data = load(path)
    for m in TOKEN.finditer(data):
        yield m.group(0)
        # (a dotted path also names its prefixes and leaf: Struct members are hashed as "Parent.Member")
        tok = m.group(0)
        if b'.' in tok:
            parts = tok.split(b'.')
            for i in range(1, len(parts)):
                yield b'.'.join(parts[:i])
            yield parts[-1]

if __name__ == '__main__':
    assert murmur3(b'Sequence_IsChildhood') == 0xcea220d3 and murmur3(b'Sequence_CurrentBanc') == 0x1d6189da, 'hash differs'
    args = sys.argv[1:]
    if '--dicts' in args:
        i = args.index('--dicts')
        for n in os.listdir(args[i + 1]):
            if n.endswith('zsdic'):
                DICTS[n] = open(os.path.join(args[i + 1], n), 'rb').read()
        del args[i:i + 2]
    sys.argv[1:] = args
    gdl = json.load(open(sys.argv[1]))['Data']
    want = {}
    for kind, entries in gdl.items():
        for e in entries:
            if isinstance(e, dict) and 'Hash' in e:
                want.setdefault(e['Hash'], []).append(kind)
    found = {}
    files = []
    for p in sys.argv[3:]:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                files += [os.path.join(root, n) for n in names]
        else:
            files.append(p)
    for f in files:
        if os.path.getsize(f) > 40 << 20 and not f.endswith('image.bin'): continue
        for s in set(strings_of(f)):
            h = murmur3(s)
            if h in want and h not in found:
                found[h] = s.decode()
    out = {}
    for h, kinds in want.items():
        for k in kinds:
            out.setdefault(k, {})['%08x' % h] = found.get(h)
    json.dump(out, open(sys.argv[2], 'w'), indent=1, sort_keys=True)
    for k in sorted(out):
        named = sum(1 for v in out[k].values() if v)
        print('%-16s %5d named of %5d' % (k, named, len(out[k])))
