#!/usr/bin/env python3
"""Convert the vendored ircdocs/parser-tests YAML corpus to JSON.

The test bundle has no YAML reader, so the corpus is converted once at
vendoring time and the JSON is committed next to the YAML it came from.

Usage:

    pip install pyyaml
    python3 Tests/Corpora/IRCSpec/convert-parser-tests.py

Source: https://github.com/ircdocs/parser-tests (CC0 1.0, see
parser-tests/LICENSE).
"""

import json
import pathlib
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - developer tooling
    sys.exit("pyyaml is required: pip install pyyaml")

CORPUS = pathlib.Path(__file__).resolve().parent / "parser-tests"
NAMES = (
    "msg-split",
    "msg-join",
    "userhost-split",
    "mask-match",
    "validate-hostname",
)


def main() -> None:
    for name in NAMES:
        source = CORPUS / f"{name}.yaml"
        loaded = yaml.safe_load(source.read_text(encoding="utf-8"))
        destination = CORPUS / f"{name}.json"
        destination.write_text(
            json.dumps(loaded, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"{destination.name}: {len(loaded['tests'])} cases")


if __name__ == "__main__":
    main()
