#!/usr/bin/env python3
"""Keeps the iPhone app's English and Chinese copy in step: both files have the same keys, each pair takes
the same format arguments, and every t("key") / tn("key") written out in the Swift sources exists."""
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

def plural_keys(path):
    return set(re.findall(r'<key>([A-Za-z0-9_]+)</key>\s*<dict>\s*<key>NSStringLocalizedFormatKey', open(path, encoding='utf-8').read()))

def args(s):
    return sorted(re.sub(r'\d+\$', '', a) for a in re.findall(r'%(?:\d+\$)?(?:ld|lu|d|@|f|\.\d+f)', s))

en = table('Resources/en.lproj/Localizable.strings')
zh = table('Resources/zh-Hans.lproj/Localizable.strings')
en_p = plural_keys('Resources/en.lproj/Localizable.stringsdict')
zh_p = plural_keys('Resources/zh-Hans.lproj/Localizable.stringsdict')

problems = []
for key in sorted(set(en) | set(zh)):
    if key not in zh:
        problems.append(f'zh-Hans: missing "{key}"')
    elif key not in en:
        problems.append(f'en: missing "{key}"')
    elif args(en[key]) != args(zh[key]):
        problems.append(f'"{key}" takes {args(en[key])} in English and {args(zh[key])} in Chinese')
if en_p != zh_p:
    problems.append(f'plural keys differ: {sorted(en_p ^ zh_p)}')

used = {}
for path in sorted(glob.glob('**/*.swift', recursive=True)):
    for m in re.finditer(r'(?<![A-Za-z0-9_.])(t|tn)\("((?:[^"\\]|\\.)*)"', open(path, encoding='utf-8').read()):
        used.setdefault((m.group(1), unescape(m.group(2))), path)
for (fn, key), path in used.items():
    if key.endswith('_'):  # a prefix, the rest is added at run time
        continue
    known = en_p if fn == 'tn' else set(en)
    if key not in known:
        problems.append(f'{path}: {fn}("{key}") has no string')

for p in problems:
    print(p)
print(f'{len(en)} strings, {len(en_p)} plurals, {len(used)} used in code, {len(problems)} problems')
sys.exit(1 if problems else 0)
