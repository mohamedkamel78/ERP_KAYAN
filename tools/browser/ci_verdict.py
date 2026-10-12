#!/usr/bin/env python3
"""Turns the browser check's transcript into annotations a person can read.

GitHub keeps ten annotations per kind for each step, and the transcript of a
browser run is far longer than that. Logs and artifacts are not always
reachable from outside the runner, so the annotations are the record that
survives. This packs the verdict into a handful of them, in order of what
matters: what failed, what the server refused, how the sign-in went, and how
the log ended.

Usage: ci_verdict.py <transcript>
"""
import re
import sys

LIMIT = 2600      # characters per annotation, comfortably under GitHub's cap
MAX_PARTS = 4     # ten per step are allowed; leave room for the others


def escape(text: str) -> str:
    # Workflow-command escaping: the message must be one line.
    return text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def main() -> int:
    with open(sys.argv[1], encoding='utf-8', errors='replace') as handle:
        lines = [line.rstrip('\n') for line in handle]

    verdict = [l for l in lines if re.match(r'^(FAIL|DIED) ', l)]
    summary = [l for l in lines if 'checks passed' in l or 'itself broke' in l]
    passes = sum(1 for l in lines if l.startswith('PASS '))
    refused, seen = [], set()
    for line in lines:
        if line.startswith('HTTP ') and line not in seen:
            seen.add(line)
            refused.append(line)
    state = [l for l in lines if re.match(r'^(AUTH|STORAGE|CONSOLE) ', l)]
    tail = lines[-12:]

    sections = [
        ('verdict', [f'{passes} PASS lines in the transcript'] + summary + verdict),
        ('refused by the server', refused[:20] or ['nothing refused']),
        ('sign-in state', state[:12] or ['no sign-in state recorded']),
        ('end of the transcript', tail),
    ]

    messages = []
    for title, body in sections:
        current = f'[{title}]'
        for line in body:
            piece = line if len(line) < LIMIT else line[: LIMIT - 20] + ' ...(cut)'
            if len(current) + len(piece) + 1 > LIMIT:
                messages.append(current)
                current = '[' + title + ', continued]'
            current += '\n' + piece
        messages.append(current)

    messages = messages[:MAX_PARTS]
    for index, message in enumerate(messages, start=1):
        print(f'::error title=Browser check {index} of {len(messages)}::{escape(message)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
