#!/usr/bin/env python3
# Adds the corlinks_zombies items + pictures to ox_inventory. Safe to run more than once.
import os, shutil, sys
here = os.path.dirname(os.path.abspath(__file__))
ox = sys.argv[1]
items_lua = os.path.join(ox, 'data', 'items.lua')
s = open(items_lua, encoding='utf-8').read()
if "['zdm_medkit']" in s:
    print('items already installed')
else:
    shutil.copy(items_lua, items_lua + '.bak_zombies')
    block = open(os.path.join(here, 'items_block.txt'), encoding='utf-8').read()
    i = s.rstrip().rfind('}')
    s = s[:i].rstrip() + '\n\n' + block + s[i:]
    open(items_lua, 'w', encoding='utf-8').write(s)
    print('items added (backup: items.lua.bak_zombies)')
img = os.path.join(ox, 'web', 'images')
for f in os.listdir(os.path.join(here, 'images')):
    shutil.copy(os.path.join(here, 'images', f), os.path.join(img, f))
print('pictures copied')
