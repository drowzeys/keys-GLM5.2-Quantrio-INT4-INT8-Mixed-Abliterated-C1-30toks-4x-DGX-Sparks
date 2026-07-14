#!/usr/bin/env python3
"""Verify GLM-5.2 Quantrio abliterated weights are the real late-only ablit, not stock.

Default: size check on the 13 dirty shards (fast, enough to catch stock mix-ups).
Optional: --sha256 for full LFS digest match (slow, ~40 GiB read).

Also catches partial installs that cause **<100% refusal bypass**:
  • incomplete 124-shard tree
  • dirty shards hardlinked to a sibling stock tree
  • hub symlink missing / pointing at stock
  • real directory named glm52-int4-int8mix next to ablit (easy to serve by mistake)

Exit codes:
  0  PASS
  1  FAIL (sizes / missing / sha mismatch / partial install)
  2  usage / missing recipe table

Example:
  python3 scripts/verify_ablit_weights.py \\
    --dir /var/tmp/models/glm52-int4-int8mix-abliterated \\
    --hub /var/tmp/models/hub/glm52-int4-int8mix
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path


def recipe_path() -> Path:
    return Path(__file__).resolve().parent.parent / "recipe" / "DIRTY_SHARDS.json"


def load_recipe(path: Path) -> dict:
    if not path.is_file():
        print(f"FAIL: missing recipe table {path}", file=sys.stderr)
        sys.exit(2)
    return json.loads(path.read_text())


def sha256_file(path: Path, chunk: int = 64 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--dir",
        type=Path,
        default=Path("/var/tmp/models/glm52-int4-int8mix-abliterated"),
        help="Abliterated checkpoint directory",
    )
    ap.add_argument(
        "--recipe",
        type=Path,
        default=None,
        help="Path to recipe/DIRTY_SHARDS.json (default: repo recipe/)",
    )
    ap.add_argument(
        "--sha256",
        action="store_true",
        help="Also verify full SHA256 of each dirty shard (slow)",
    )
    ap.add_argument(
        "--require-index",
        action="store_true",
        default=True,
        help="Require model.safetensors.index.json + config.json (default on)",
    )
    ap.add_argument(
        "--hub",
        type=Path,
        default=None,
        help="Optional: hub symlink path to check (e.g. /var/tmp/models/hub/glm52-int4-int8mix)",
    )
    ap.add_argument(
        "--strict-sibling",
        action="store_true",
        help="FAIL if sibling stock dir glm52-int4-int8mix exists (default: WARN only)",
    )
    args = ap.parse_args()
    recipe = load_recipe(args.recipe or recipe_path())
    root: Path = args.dir.expanduser().resolve()
    dirty = recipe["dirty_shards"]
    n_total = int(recipe.get("n_model_shards_total") or 124)
    fails: list[str] = []
    warns: list[str] = []

    if not root.is_dir():
        print(f"FAIL: not a directory: {root}")
        return 1

    for must in ("config.json", "model.safetensors.index.json"):
        if args.require_index and not (root / must).is_file():
            fails.append(f"missing {must}")

    print(f"verify ablit tree: {root}")
    print(f"recipe: {recipe.get('repo')} · {recipe.get('recipe')}")
    print(f"dirty shards expected: {len(dirty)} / {n_total} model shards")
    print()

    # Full tree completeness — partial trees → partial / zero bypass
    model_shards = sorted(root.glob("model-*-of-*.safetensors"))
    n_shards = len(model_shards)
    if n_shards != n_total:
        fails.append(
            f"incomplete tree: found {n_shards} model-*-of-*.safetensors, need {n_total}"
        )
        print(f"  FAIL  shard count: {n_shards} != {n_total} (partial download/fanout)")
    else:
        print(f"  OK    full tree: {n_shards} model shards")

    # Sibling stock tree is the #1 “I served the wrong path” footgun
    sibling_stock = root.parent / "glm52-int4-int8mix"
    if sibling_stock.is_dir() and sibling_stock.resolve() != root.resolve():
        msg = (
            f"sibling stock tree exists: {sibling_stock} — "
            "do NOT serve this path; launcher must use hub/glm52-int4-int8mix → abliterated"
        )
        if args.strict_sibling:
            fails.append(msg)
            print(f"  FAIL  {msg}")
        else:
            warns.append(msg)
            print(f"  WARN  {msg}")

    dirty_ok = 0
    dirty_stockish = 0
    for entry in dirty:
        name = entry["name"]
        want_size = int(entry["size"])
        want_sha = entry.get("sha256")
        path = root / name
        if not path.is_file():
            fails.append(f"MISSING {name}")
            print(f"  FAIL  {name}: MISSING")
            continue
        st = path.stat()
        got = st.st_size
        # Stock QuantTrio files for these names are typically +32 bytes.
        stockish = got == want_size + 32
        if got != want_size:
            msg = f"size {got} != {want_size}"
            if stockish:
                dirty_stockish += 1
                msg += " (matches STOCK QuantTrio size +32 — not abliterated)"
            fails.append(f"{name}: {msg}")
            print(f"  FAIL  {name}: {msg}")
            continue

        # Hardlink to sibling stock = silent partial ablit (same inode as stock copy)
        if sibling_stock.is_dir():
            stock_peer = sibling_stock / name
            if stock_peer.is_file():
                try:
                    if os.path.samefile(path, stock_peer):
                        fails.append(
                            f"{name}: hardlinked to stock sibling {stock_peer} "
                            "(overlay never applied — partial/zero bypass)"
                        )
                        print(
                            f"  FAIL  {name}: hardlinked to stock "
                            f"(inode {st.st_ino}) — re-copy dirty shard from HF ablit"
                        )
                        continue
                except OSError:
                    pass

        if args.sha256 and want_sha:
            print(f"  hash  {name} ...", flush=True)
            got_sha = sha256_file(path)
            if got_sha != want_sha:
                fails.append(f"{name}: sha256 mismatch")
                print(f"  FAIL  {name}: sha256 {got_sha} != {want_sha}")
                continue
            print(f"  OK    {name}: size+sha256")
        else:
            print(f"  OK    {name}: size={got}")
        dirty_ok += 1

    if dirty_stockish and dirty_ok:
        fails.append(
            f"PARTIAL ABLIT: {dirty_ok}/{len(dirty)} dirty shards OK, "
            f"{dirty_stockish} still stock-sized — explains <100% bypass"
        )
        print(
            f"  FAIL  partial dirty set: {dirty_ok} ablit + {dirty_stockish} stock "
            f"(mixed tree)"
        )

    # Presence of a few stock-range shards (should exist; may match QuantTrio)
    sample_stockish = [
        "model-00001-of-00124.safetensors",
        "model-00050-of-00124.safetensors",
        "model-00124-of-00124.safetensors",
    ]
    for name in sample_stockish:
        if not (root / name).is_file():
            fails.append(f"MISSING early/late stock shard {name} (incomplete download)")
            print(f"  FAIL  {name}: MISSING (need full 124-shard tree)")

    if args.hub:
        hub = args.hub.expanduser()
        if not hub.exists():
            fails.append(f"hub path missing: {hub}")
            print(f"  FAIL  hub {hub}: missing")
        else:
            if hub.is_dir() and not hub.is_symlink():
                # Real directory under hub/ named glm52-int4-int8mix is often stock
                fails.append(
                    f"hub {hub} is a real directory, not a symlink to abliterated — "
                    "re-run: bash scripts/install_hub_symlink.sh"
                )
                print(f"  FAIL  hub {hub}: not a symlink (likely stock tree)")
            target = hub.resolve()
            if target != root.resolve():
                try:
                    same = target.samefile(root)
                except OSError:
                    same = False
                if not same:
                    fails.append(
                        f"hub {hub} resolves to {target}, not ablit tree {root}"
                    )
                    print(f"  FAIL  hub {hub} -> {target} (want {root})")
                else:
                    print(f"  OK    hub {hub} -> {target}")
            else:
                print(f"  OK    hub {hub} -> {target}")
            # Name must be exact launcher name
            if hub.name != "glm52-int4-int8mix":
                fails.append(
                    f"hub basename is {hub.name!r}, launcher requires 'glm52-int4-int8mix'"
                )
                print(f"  FAIL  hub name {hub.name!r} != 'glm52-int4-int8mix'")

    print()
    if fails:
        print("FAIL — abliterated weights NOT verified")
        print("Common causes of full OR partial (<100%) refusal bypass:")
        print("  • downloaded QuantTrio stock instead of drowzeys/...-Abliterated")
        print("  • incomplete download / fanout (need all 124 shards + 13 dirty)")
        print("  • hardlink clone from stock without overlaying ALL 13 dirty shards")
        print("  • hub symlink missing, wrong name, or pointing at stock")
        print("  • multi-node: only some ranks have ablit (verify on EVERY rank)")
        print("  • probes with enable_thinking=true (false “still refuses”)")
        print("See INSTALL.md (thinking off + full fanout)")
        for f in fails:
            print(f"  - {f}")
        return 1

    for w in warns:
        print("WARN:", w)
    print("PASS — dirty shards match standing late ablit (L65–77 o_proj)")
    print(f"  dirty OK: {dirty_ok}/{len(dirty)} · tree shards: {n_shards}/{n_total}")
    print("Next: ensure hub symlink name is exactly 'glm52-int4-int8mix':")
    print("  bash scripts/install_hub_symlink.sh")
    print("  # launcher serves: /cache/huggingface/hub/glm52-int4-int8mix")
    print("If bypass is still <100% after PASS: INSTALL.md (thinking off + full fanout) + diagnose_install.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
