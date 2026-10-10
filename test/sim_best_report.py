"""Report for sim_best.py: python3 sim_best_report.py OUT_PREFIX"""
import json, glob, math, re, sys
OUT = sys.argv[1]
decks = json.load(open(OUT + "_decks.json"))
games = []
for p in sorted(glob.glob(OUT + "_games_*.json")):
    games += json.load(open(p))
errs = [g for g in games if "Err" in g]
games = [g for g in games if "Err" not in g and g["W"] in (1, 2)]

src = open("/home/claude/roblox/build/ReplicatedStorage.CardDatabase.lua").read()
names = dict(re.findall(r'Id = "([A-Z0-9-]+)",\s*Name = "([^"]+)"', src))
def nm(cid): return names.get(cid, cid)

def wilson(w, n, z=1.96):
    if n == 0: return (0, 1)
    p = w / n; d = 1 + z*z/n; c = p + z*z/(2*n); r = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n))
    return ((c - r)/d, (c + r)/d)

print(f"{len(games)} games, errors {len(errs)}, avg turns {sum(g['T'] for g in games)/len(games):.1f}")
fw = sum(1 for g in games if g["W"] == g["F"])
print(f"First player wins {fw/len(games)*100:.1f}%")
rec = {i: [0, 0] for i in range(len(decks))}
mu = {}
for g in games:
    a, b = g["A"], g["B"]
    rec[a][1] += 1; rec[b][1] += 1
    winner = a if g["W"] == 1 else b
    rec[winner][0] += 1
    for x, y in ((a, b), (b, a)):
        m = mu.setdefault((x, y), [0, 0]); m[1] += 1; m[0] += winner == x
print("\nBest decks, win rate (Hard bot both sides):")
order = sorted(rec, key=lambda i: -rec[i][0] / max(1, rec[i][1]))
for i in order:
    w, n = rec[i]; lo, hi = wilson(w, n)
    d = decks[i]
    print(f"  {nm(d['Commander']):30s} + {nm(d['Celestial']):22s} {w/n*100:5.1f}%  ({lo*100:4.1f}-{hi*100:4.1f}, n={n})")
print("\nMatchups (row's win rate vs column):")
short = [nm(decks[i]["Commander"]).split(",")[0].split(" ")[-1][:7] for i in range(len(decks))]
print("         " + " ".join(f"{short[j]:>7s}" for j in order))
for i in order:
    row = []
    for j in order:
        if i == j: row.append("    -  ")
        else:
            w, n = mu.get((i, j), [0, 0]); row.append(f"{(w/n*100 if n else 0):6.0f}%")
    print(f"  {short[i]:7s}" + " ".join(row))
# cards in the best decks: win rate when the card got played
cp = {}
for g in games:
    for seat, key in ((1, "P1"), (2, "P2")):
        for cid in g[key]:
            a = cp.setdefault(cid, [0, 0]); a[1] += 1; a[0] += g["W"] == seat
print("\nCards in the best decks, win rate when played (n>=150):")
rows = sorted(((w/n, cid, n) for cid, (w, n) in cp.items() if n >= 150), reverse=True)
for p, cid, n in rows[:12]:
    print(f"  {cid:9s} {nm(cid):28s} {p*100:5.1f}%  (n={n})")
print("  ...")
for p, cid, n in rows[-8:]:
    print(f"  {cid:9s} {nm(cid):28s} {p*100:5.1f}%  (n={n})")
print("\nDecklists:")
for i in order:
    d = decks[i]
    counts = {}
    for c in d["Cards"]: counts[c] = counts.get(c, 0) + 1
    print(f"  {nm(d['Commander'])} + {nm(d['Celestial'])}: " + ", ".join(f"{n}x {nm(c)}" for c, n in sorted(counts.items())))
