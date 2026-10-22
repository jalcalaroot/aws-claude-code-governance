#!/usr/bin/env python3
"""Write build/standalone.yaml: the upstream template without Lambda reserved concurrency.

Lambda refuses a reservation that leaves fewer than 10 unreserved executions.
A new account has a total limit of 10, so the sample's reservations (100, 100,
2 and 5) cannot be created and the stack rolls back. This removes exactly those
four settings (aborts if the count differs, e.g. after an upstream change).
The interceptors then share the account limit; raise the quota and deploy the
unmodified template when the account has headroom.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "upstream/cloudformation/standalone.yaml"
DST = ROOT / "build/standalone.yaml"

text = SRC.read_text()
pattern = re.compile(r"^[ ]+ReservedConcurrentExecutions: .*\n", re.MULTILINE)
found = pattern.findall(text)
if len(found) != 4:
    sys.exit(f"expected 4 ReservedConcurrentExecutions settings, found {len(found)}")
DST.parent.mkdir(parents=True, exist_ok=True)
DST.write_text(pattern.sub("", text))
print(f"wrote {DST} without {len(found)} reserved-concurrency settings")
