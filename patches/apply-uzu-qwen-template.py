#!/usr/bin/env python3
"""Patch a trymirai/uzu checkout so Qwen 3.5+ can render a Yuzu tool turn.

The Swift package links a prebuilt uzu.xcframework. Editing these sources does
nothing until that framework is rebuilt from the patched tree.

Usage:
  python3 patches/apply-uzu-qwen-template.py /path/to/uzu
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

RAISE = """{%- if message.role == "system" %}
        {%- if not loop.first %}
            {{- raise_exception('System message must be at the beginning.') }}
        {%- endif %}"""

EMIT = """{%- if message.role == "system" %}
        {%- if not loop.first %}
            {%- set content = render_content(message.content, true, true)|trim %}
            {{- '<|im_start|>system\\n' + content + '<|im_end|>\\n' }}
        {%- endif %}"""

TEMPLATES = ("qwen3.5.json", "qwen3.6.json", "qwen3.8.json")
EFFORTS = ("high", "medium", "low", "xhigh")


def patch_template(path: Path) -> str:
    data = json.loads(path.read_text())
    template = data["jinja"]["template"]
    if RAISE not in template and EMIT not in template:
        return f"unrecognized template: {path}"
    template = template.replace(RAISE, EMIT)
    data["jinja"]["template"] = template
    mapping = data["rendering"]["system"]["context"]["enable_thinking"]["mapping"]
    for effort in EFFORTS:
        mapping.setdefault(effort, True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    return f"patched {path.name}"


def patch_duplicate_key(path: Path) -> str:
    text = path.read_text()
    old = """    if context.contains_key(&key) {
        return Err(Error::DuplicateContextKey {
            key,
        });
    }
    context.insert(key, value);"""
    new = """    if let Some(existing) = context.get(&key) {
        if existing == &value {
            return Ok(());
        }
        return Err(Error::DuplicateContextKey {
            key,
        });
    }
    context.insert(key, value);"""
    if new in text:
        return "duplicate key already allows equal values"
    if old not in text:
        return f"unrecognized insert_into_context: {path}"
    path.write_text(text.replace(old, new, 1))
    return "equal enable_thinking values no longer abort the render"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 2
    root = Path(sys.argv[1])
    rendering = root / "crates/legacy/hanashi/configs/rendering"
    renderer = root / "crates/legacy/hanashi/src/chat/hanashi/renderer/mod.rs"
    if not rendering.is_dir() or not renderer.is_file():
        print(f"not an uzu checkout: {root}")
        return 1
    for name in TEMPLATES:
        print(patch_template(rendering / name))
    print(patch_duplicate_key(renderer))
    print("Rebuild uzu.xcframework from this tree before R2 can see the change.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
