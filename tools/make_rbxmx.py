"""Packs the scripts in build/ into one .rbxmx per Studio location."""
import glob, os, sys, xml.etree.ElementTree as ET
BUILD, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
groups = {}
for path in sorted(glob.glob(BUILD + "/*.lua")):
    base = os.path.basename(path)[:-4]
    parts = base.split(".")
    where, name = ".".join(parts[:-1]), parts[-1]
    src = open(path).read()
    head = src[:300]
    cls = "ModuleScript" if "(ModuleScript)" in head else ("LocalScript" if "(LocalScript)" in head else "Script")
    groups.setdefault(where, []).append((name, cls, src))
ref = 0
for where, items in groups.items():
    out = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">']
    for name, cls, src in items:
        ref += 1
        assert "]]>" not in src
        out.append(f'\t<Item class="{cls}" referent="RBX{ref:04d}">\n\t\t<Properties>\n'
                   f'\t\t\t<string name="Name">{name}</string>\n'
                   f'\t\t\t<ProtectedString name="Source"><![CDATA[{src}]]></ProtectedString>\n'
                   f'\t\t</Properties>\n\t</Item>')
    out.append("</roblox>")
    fn = os.path.join(OUT, where.split(".")[-1] + ".rbxmx")
    open(fn, "w").write("\n".join(out))
    # read it back and compare
    tree = ET.parse(fn)
    back = {i.find("Properties/string[@name='Name']").text: (i.get("class"), i.find("Properties/ProtectedString").text)
            for i in tree.getroot()}
    for name, cls, src in items:
        assert back[name] == (cls, src), name
    print(fn, [(n, c) for n, c, _ in items])
