"""(longshot-mac) A small BYML (v2-v7, either byte order: "YB" little, "BY" big) reader: python3 byml_dump.py <file.byml> [--json out.json]
Enough for the GameData list: dicts, arrays, hash maps (0x20 32-bit, 0x21 64-bit keys), the scalar types."""
import json, struct, sys

class Byml:
    def __init__(self, d):
        self.d = d
        assert d[:2] in (b'BY', b'YB'), 'not BYML'
        self.e = '>' if d[:2] == b'BY' else '<'
        self.keys = self.strtab(struct.unpack_from(self.e + 'I', d, 4)[0])
        self.strs = self.strtab(struct.unpack_from(self.e + 'I', d, 8)[0])
        self.root = struct.unpack_from(self.e + 'I', d, 12)[0]
    def strtab(self, off):
        if not off: return []
        w = struct.unpack_from(self.e + 'I', self.d, off)[0]
        n = w & 0xffffff if self.e == '>' else w >> 8
        offs = struct.unpack_from(self.e + '%dI' % (n + 1), self.d, off + 4)
        return [self.d[off + o:self.d.index(b'\0', off + o)].decode('utf-8', 'replace') for o in offs[:n]]
    def node(self, t, v):
        d = self.d
        if t == 0xA0: return self.strs[v]
        if t in (0xC0, 0xC1, 0x20, 0x21): return self.container(v)
        if t == 0xD0: return bool(v)
        if t == 0xD1: return struct.unpack(self.e + 'i', struct.pack(self.e + 'I', v))[0]
        if t == 0xD2: return struct.unpack(self.e + 'f', struct.pack(self.e + 'I', v))[0]
        if t == 0xD3: return v
        if t in (0xD4, 0xD5, 0xD6):
            raw = d[v:v + 8]
            return struct.unpack(self.e + ('q' if t == 0xD4 else 'Q' if t == 0xD5 else 'd'), raw)[0]
        if t == 0xFF: return None
        if t == 0xA1:   # binary: size + bytes
            n = struct.unpack_from(self.e + 'I', d, v)[0]
            return d[v + 4:v + 4 + n].hex()
        return '<type %#x @%#x>' % (t, v)
    def container(self, off):
        d = self.d
        t = d[off]; n = int.from_bytes(d[off + 1:off + 4], 'big' if self.e == '>' else 'little')
        if t == 0xC0:
            types = d[off + 4:off + 4 + n]
            vo = (off + 4 + n + 3) & ~3
            return [self.node(types[i], struct.unpack_from(self.e + 'I', d, vo + 4 * i)[0]) for i in range(n)]
        if t == 0xC1:
            out = {}
            for i in range(n):
                e = off + 4 + 8 * i
                k = int.from_bytes(d[e:e + 3], 'big' if self.e == '>' else 'little'); typ = d[e + 3]; v = struct.unpack_from(self.e + 'I', d, e + 4)[0]
                out[self.keys[k]] = self.node(typ, v)
            return out
        if t in (0x20, 0x21):   # hash maps: entries of (hash, value), then the value types
            ks = 4 if t == 0x20 else 8
            es = ks + 4
            types = d[off + 4 + es * n:off + 4 + es * n + n]
            out = {}
            for i in range(n):
                e = off + 4 + es * i
                h = int.from_bytes(d[e:e + ks], 'big' if self.e == '>' else 'little'); v = struct.unpack_from(self.e + 'I', d, e + ks)[0]
                out['%#x' % h] = self.node(types[i], v)
            return out
        return '<container %#x>' % t
    def parse(self):
        return self.container(self.root)

if __name__ == '__main__':
    doc = Byml(open(sys.argv[1], 'rb').read()).parse()
    if '--json' in sys.argv:
        json.dump(doc, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1, default=str)
    def shape(x, depth=0):
        if isinstance(x, dict):
            for k, v in list(x.items())[:40]:
                print('  ' * depth + str(k), (type(v).__name__, len(v)) if isinstance(v, (list, dict)) else repr(v)[:80])
                if depth < 1: shape(v, depth + 1)
        elif isinstance(x, list) and x and depth < 2:
            print('  ' * depth + '[0]:', repr(x[0])[:300])
    shape(doc)
