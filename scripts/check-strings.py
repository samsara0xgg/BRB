#!/usr/bin/env python3
"""Keeps the Chinese copy in step with the Swift sources: every L("...") key has a translation,
no translation is left over, and each one takes the same format arguments as its key."""
import glob
import os
import re
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)

def unescape(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)

def table(path):
    text = re.sub(r'/\*.*?\*/', '', open(path, encoding='utf-8').read(), flags=re.S)
    pairs = re.findall(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text)
    return {unescape(k): unescape(v) for k, v in pairs}

def args(s):
    return sorted(re.findall(r'%(?:\d+\$)?(?:ld|lu|d|@|f|\.\d+f)', s))

keys = {}
for path in sorted(glob.glob('*.swift')):
    for m in re.finditer(r'\bL\("((?:[^"\\]|\\.)*)"', open(path, encoding='utf-8').read()):
        keys.setdefault(unescape(m.group(1)), path)

problems = []
zh = table('Resources/zh-Hans.lproj/Localizable.strings')
en = table('Resources/en.lproj/Localizable.strings')
for key, path in keys.items():
    if key not in zh:
        problems.append(f'{path}: no Chinese for "{key}"')
    elif args(key) != args(zh[key]):
        problems.append(f'zh-Hans: "{key}" takes {args(key)}, the translation {args(zh[key])}')
for key in zh:
    if key not in keys:
        problems.append(f'zh-Hans: "{key}" is not used any more')
for key in en:
    if key not in keys:
        problems.append(f'en: "{key}" is not used any more')

for p in problems:
    print(p)
print(f'{len(keys)} strings, {len(problems)} problems')
sys.exit(1 if problems else 0)
