"""Pulls every script out of a binary Roblox place (.rbxl) file.
Usage: python3 rbxl_extract.py place.rbxl out_folder
Writes each script's Source to out_folder/<Path.To.Script>.lua"""
import os, struct, sys
import lz4.block
import zstandard


def read_string(buf, pos):
    n = struct.unpack_from("<I", buf, pos)[0]
    return buf[pos + 4:pos + 4 + n], pos + 4 + n


def interleaved_i32(buf, pos, count):
    raw = buf[pos:pos + count * 4]
    out = []
    for i in range(count):
        b = bytes(raw[i + count * k] for k in range(4))
        n = int.from_bytes(b, "big")
        out.append((n >> 1) ^ -(n & 1))
    return out, pos + count * 4


def referents(buf, pos, count):
    vals, pos = interleaved_i32(buf, pos, count)
    acc, out = 0, []
    for v in vals:
        acc += v
        out.append(acc)
    return out, pos


def chunks(data):
    assert data[:8] == b"<roblox!", "not a binary place file"
    pos = 32
    while pos < len(data):
        name = data[pos:pos + 4].decode("ascii", "replace")
        comp, uncomp = struct.unpack_from("<II", data, pos + 4)
        pos += 16
        if comp == 0:
            body = data[pos:pos + uncomp]
            pos += uncomp
        else:
            raw = data[pos:pos + comp]
            pos += comp
            if raw[:4] == b"\x28\xb5\x2f\xfd":
                body = zstandard.ZstdDecompressor().decompress(raw, max_output_size=uncomp)
            else:
                body = lz4.block.decompress(raw, uncompressed_size=uncomp)
        yield name, body
        if name == "END\x00":
            break


def main(path, out):
    data = open(path, "rb").read()
    classes = {}   # class id -> (name, [refs])
    cls_of = {}    # ref -> class name
    names, sources, parent = {}, {}, {}
    for name, body in chunks(data):
        if name == "INST":
            cid = struct.unpack_from("<I", body, 0)[0]
            cname, p = read_string(body, 4)
            p += 1
            count = struct.unpack_from("<I", body, p)[0]
            refs, p = referents(body, p + 4, count)
            classes[cid] = (cname.decode(), refs)
            for r in refs:
                cls_of[r] = cname.decode()
        elif name == "PROP":
            cid = struct.unpack_from("<I", body, 0)[0]
            pname, p = read_string(body, 4)
            ptype = body[p]
            p += 1
            pname = pname.decode()
            if ptype != 0x01 or pname not in ("Name", "Source"):
                continue
            refs = classes[cid][1]
            for r in refs:
                s, p = read_string(body, p)
                (names if pname == "Name" else sources)[r] = s.decode("utf-8", "replace")
        elif name == "PRNT":
            count = struct.unpack_from("<I", body, 1)[0]
            kids, p = referents(body, 5, count)
            pars, p = referents(body, p, count)
            for k, par in zip(kids, pars):
                parent[k] = par

    def full(r):
        parts = []
        while r is not None and r in names:
            parts.append(names[r])
            r = parent.get(r)
            if r == -1:
                break
        return ".".join(reversed(parts))

    os.makedirs(out, exist_ok=True)
    for r, src in sorted(sources.items(), key=lambda kv: full(kv[0])):
        p = full(r)
        fn = os.path.join(out, p + ".lua")
        open(fn, "w").write(src)
        print(f"{cls_of.get(r,'?'):12s} {len(src.splitlines()):5d} lines  {p}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
