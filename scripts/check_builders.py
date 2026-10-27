#!/usr/bin/env python3
"""Rough check that no SwiftUI result-builder block has more than 10 direct children.

Linux can't compile the SwiftUI code, and `Commands`/`Scene` builders stop at 10 items, so this
counts statements directly inside `{ ... }` blocks of SwiftUI files: a child is a line at the
block's depth that doesn't start with `.`, `//`, `}`, `)` or a control keyword's continuation.
Usage: check_builders.py [files...] (default: Sources/SpiderSolitaire/*.swift).
Blocks opened on a func/init/type line are skipped (imperative code), so a @ViewBuilder func is not checked. Exit 1 on > 10."""
import glob, re, sys

LIMIT = 10
SKIP = re.compile(r'^\s*(\.|//|\}|\)|\]|case |default:|else|#|@|let |var |guard |return |switch |func |init|private |static |struct |enum |final |extension |import |if let \w+ = self|weak |///)')

def check(path):
    bad = []
    lines = open(path, encoding='utf-8').read().split('\n')
    stack = []  # (line number, child count, is builder-ish)
    pending_decl = False  # a func/init signature that continues onto the next lines
    for n, raw in enumerate(lines, 1):
        line = re.sub(r'"(?:\\.|[^"\\])*"', '""', raw.split('//')[0] if '"' not in raw else raw)
        stripped = line.strip()
        if stack and stripped and not SKIP.match(stripped) and stack[-1][3] == 0:
            stack[-1][1] += 1
        if re.search(r'\b(func|init)\b', stripped) and '{' not in stripped:
            pending_decl = True
        for ch in line:
            if ch == '{':
                # Function, initializer and type bodies are imperative or declarations, not builders.
                opener = not (pending_decl or re.search(r'\b(func|init|class|struct|enum|extension|protocol|switch)\b', stripped))
                pending_decl = False
                stack.append([n, 0, opener, 0])
            elif ch == '}':
                if stack:
                    start, count, builderish, _ = stack.pop()
                    if builderish and count > LIMIT:
                        bad.append((start, count))
        # mark multi-line expressions: children counted only at line starts of the block
    return bad

files = sys.argv[1:] or sorted(glob.glob('Sources/SpiderSolitaire/*.swift'))
failed = False
for f in files:
    for start, count in check(f):
        print(f"{f}:{start}: block with {count} direct children (limit {LIMIT})")
        failed = True
sys.exit(1 if failed else 0)
