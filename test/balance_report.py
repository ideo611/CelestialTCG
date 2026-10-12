"""Card balance from random-deck games (sim2.py records).

python3 balance_report.py OUT_DIR records1.json [records2.json ...]
Writes OUT_DIR/cards_balance.json (one row per card), factions.json,
commanders.json, celestials.json and summary.json.

For every card: how often decks ran it, their win rate, the card's "lift"
(win rate of decks with it minus same-faction decks without it, with a 95%
interval), how often it got played when in the deck, the win rate when it was
played, and a verdict.
"""
import json, math, sys, os
from collections import defaultdict

OUT = sys.argv[1]
paths = sys.argv[2:]

def seats(r):
    S = r["S"]
    return [(1, S[0]), (2, S[1])] if isinstance(S, list) else [(1, S["1"]), (2, S["2"])]

def wilson(w, n, z=1.96):
    if n == 0:
        return (0, 0)
    p = w / n; d = 1 + z * z / n; c = p + z * z / (2 * n); r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - r) / d, (c + r) / d)

games = 0; turns = 0; first_wins = 0
fac = defaultdict(lambda: [0, 0]); cmd = defaultdict(lambda: [0, 0]); cel = defaultdict(lambda: [0, 0])
celf = defaultdict(lambda: [0, 0])  # (faction, celestial)
allw = [0, 0]
cin = defaultdict(lambda: [0, 0])       # (faction, card) -> decks with it
cplay = defaultdict(lambda: [0, 0])     # (faction, card) -> decks that played it
neu_in = defaultdict(lambda: [0, 0])    # neutral card -> any deck with it
neu_play = defaultdict(lambda: [0, 0])
copies = defaultdict(int)
for p in paths:
    for r in json.load(open(p)):
        if r.get("W") not in (1, 2):
            continue
        games += 1; turns += r["T"]; first_wins += r["W"] == r["F"]
        for s, info in seats(r):
            w = r["W"] == s
            f = info["Fa"]
            for d, k in ((fac, f), (cmd, info["Cm"]), (cel, info["Ce"])):
                d[k][0] += w; d[k][1] += 1
            allw[0] += w; allw[1] += 1
            celf[(f, info["Ce"])][0] += w; celf[(f, info["Ce"])][1] += 1
            played = set(info.get("P") or [])
            for cid, n in info["D"].items():
                key = (f, cid)
                cin[key][0] += w; cin[key][1] += 1
                copies[key] += n
                if cid in played:
                    cplay[key][0] += w; cplay[key][1] += 1
                if cid.startswith("NEU"):
                    neu_in[cid][0] += w; neu_in[cid][1] += 1
                    if cid in played:
                        neu_play[cid][0] += w; neu_play[cid][1] += 1

def lift_stats(w, n, ow, on):
    if n < 30 or on < 30:
        return None
    p1, p0 = w / n, ow / on
    se = math.sqrt(p1 * (1 - p1) / n + p0 * (1 - p0) / on)
    lift = p1 - p0
    return lift * 100, (lift - 1.96 * se) * 100, (lift + 1.96 * se) * 100, (lift / se if se else 0)

def verdict(st):
    if st is None:
        return "Not enough games"
    lift, lo, hi, z = st
    if lo > 0 and lift >= 4:
        return "Too strong"
    if lo > 0 and lift >= 1.5:
        return "Strong"
    if hi < 0 and lift <= -4:
        return "Too weak"
    if hi < 0 and lift <= -1.5:
        return "Weak"
    return "Balanced"

rows = {}
for (f, cid), (w, n) in cin.items():
    if cid.startswith("NEU"):
        continue
    fw, fn = fac[f]
    st = lift_stats(w, n, fw - w, fn - n)
    pw, pn = cplay[(f, cid)]
    rows[cid] = {
        "id": cid, "decks": n, "deck_win_rate": round(w / n * 100, 1),
        "lift": round(st[0], 1) if st else None, "lift_low": round(st[1], 1) if st else None,
        "lift_high": round(st[2], 1) if st else None, "z": round(st[3], 1) if st else None,
        "avg_copies": round(copies[(f, cid)] / n, 2),
        "play_rate": round(pn / n * 100, 1) if n else None,
        "played_win_rate": round(pw / pn * 100, 1) if pn >= 30 else None,
        "verdict": verdict(st),
    }
for cid, (w, n) in neu_in.items():
    st = lift_stats(w, n, allw[0] - w, allw[1] - n)
    pw, pn = neu_play[cid]
    rows[cid] = {
        "id": cid, "decks": n, "deck_win_rate": round(w / n * 100, 1),
        "lift": round(st[0], 1) if st else None, "lift_low": round(st[1], 1) if st else None,
        "lift_high": round(st[2], 1) if st else None, "z": round(st[3], 1) if st else None,
        "avg_copies": None, "play_rate": round(pn / n * 100, 1) if n else None,
        "played_win_rate": round(pw / pn * 100, 1) if pn >= 30 else None, "verdict": verdict(st),
    }
# a Celestial against the other Celestials its decks could have run: per faction,
# its decks' win rate minus that faction's decks with a different Celestial
for cid, (w, n) in cel.items():
    num, var, tot = 0.0, 0.0, 0
    for (f, ce), (cw, cn) in celf.items():
        if ce != cid or cn < 30:
            continue
        fw, fn = fac[f]
        ow, on = fw - cw, fn - cn
        if on < 30:
            continue
        p1, p0 = cw / cn, ow / on
        num += (p1 - p0) * cn
        var += (p1 * (1 - p1) / cn + p0 * (1 - p0) / on) * cn * cn
        tot += cn
    st = None
    if tot:
        lift = num / tot; se = math.sqrt(var) / tot
        st = (lift * 100, (lift - 1.96 * se) * 100, (lift + 1.96 * se) * 100, lift / se if se else 0)
    rows[cid] = {"id": cid, "decks": n, "deck_win_rate": round(w / n * 100, 1),
                 "lift": round(st[0], 1) if st else None, "lift_low": round(st[1], 1) if st else None,
                 "lift_high": round(st[2], 1) if st else None, "z": round(st[3], 1) if st else None,
                 "avg_copies": None, "play_rate": None, "played_win_rate": None, "verdict": verdict(st)}

os.makedirs(OUT, exist_ok=True)
json.dump(list(rows.values()), open(os.path.join(OUT, "cards_balance.json"), "w"))
def table(d):
    out = []
    for k, (w, n) in d.items():
        lo, hi = wilson(w, n)
        out.append({"id": k, "win_rate": round(w / n * 100, 1), "low": round(lo * 100, 1), "high": round(hi * 100, 1), "decks": n})
    return out
json.dump(table(fac), open(os.path.join(OUT, "factions.json"), "w"))
json.dump(table(cmd), open(os.path.join(OUT, "commanders.json"), "w"))
json.dump(table(cel), open(os.path.join(OUT, "celestials.json"), "w"))
json.dump({"games": games, "first_player_win_rate": round(first_wins / games * 100, 1),
           "avg_turns": round(turns / games, 1)}, open(os.path.join(OUT, "summary.json"), "w"))
print(games, "games;", sum(1 for r in rows.values() if r["verdict"] in ("Too strong", "Too weak")), "cards flagged")
