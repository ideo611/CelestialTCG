"""Edits one card's numbers in build/ReplicatedStorage.CardDatabase.lua.
python3 tune.py CARD-ID Field=value [Field=value...]"""
import re, sys
p = "/home/claude/roblox/build/ReplicatedStorage.CardDatabase.lua"
s = open(p).read()
cid = sys.argv[1]
i = s.index(f'Id = "{cid}"')
j = s.index("\n}", i)
block = s[i:j]
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    new, n = re.subn(rf"\b{k} = [^,\n}}]+", f"{k} = {v}", block, count=1)
    assert n == 1, (cid, k)
    block = new
s = s[:i] + block + s[j:]
open(p, "w").write(s)
print(cid, "->", " ".join(sys.argv[2:]))
