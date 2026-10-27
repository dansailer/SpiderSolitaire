#!/usr/bin/env python3
"""Rough check that no SwiftUI result-builder block has more than 10 direct children.

Linux can't compile the SwiftUI code, and `Commands`/`Scene` builders stop at 10 items, so this
counts statements directly inside `{ ... }` blocks of SwiftUI files: a child is a line at the
block's depth that doesn't start with `.`, `//`, `}`, `)` or a control keyword's continuation.
Usage: check_builders.py [files...] (default: the SwiftUI view files in Sources/SpiderSolitaire). Exit 1 on > 10."""
import glob, re, sys

LIMIT = 10
SKIP = re.compile(r'^\s*(\.|//|\}|\)|\]|case |default:|else|#|@|let |var |guard |return |switch |func |init|private |static |struct |enum |final |extension |import |if let \w+ = self|weak |///)')

def check(path):
    bad = []
    lines = open(path, encoding='utf-8').read().split('\n')
    stack = []  # (line number, child count, is builder-ish)
    for n, raw in enumerate(lines, 1):
        line = re.sub(r'"(?:\\.|[^"\\])*"', '""', raw.split('//')[0] if '"' not in raw else raw)
        stripped = line.strip()
        if stack and stripped and not SKIP.match(stripped) and stack[-1][3] == 0:
            stack[-1][1] += 1
        for ch in line:
            if ch == '{':
                stack.append([n, 0, True, 0])
            elif ch == '}':
                if stack:
                    start, count, _, _ = stack.pop()
                    if count > LIMIT:
                        bad.append((start, count))
        # mark multi-line expressions: children counted only at line starts of the block
    return bad

IMPERATIVE = {'GameModel.swift', 'MainMenu.swift', 'SoundPlayer.swift', 'ClassicCardImages.swift'}
files = sys.argv[1:] or [f for f in sorted(glob.glob('Sources/SpiderSolitaire/*.swift')) if f.split('/')[-1] not in IMPERATIVE]
failed = False
for f in files:
    for start, count in check(f):
        print(f"{f}:{start}: block with {count} direct children (limit {LIMIT})")
        failed = True
sys.exit(1 if failed else 0)
