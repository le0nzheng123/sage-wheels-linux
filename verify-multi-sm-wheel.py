#!/usr/bin/env python3
"""Verify that a wheel contains CUDA cubins for every requested SM."""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import tempfile
import zipfile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("wheel", type=pathlib.Path)
    parser.add_argument("--sm-list", nargs="+", required=True)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as temp_dir:
        with zipfile.ZipFile(args.wheel) as archive:
            members = [name for name in archive.namelist() if name.endswith(".so")]
            if not members:
                raise SystemExit("No shared libraries found in wheel")
            archive.extractall(temp_dir, members)

        output = ""
        for member in members:
            result = subprocess.run(
                ["cuobjdump", "--list-elf", str(pathlib.Path(temp_dir, member))],
                check=True,
                text=True,
                capture_output=True,
            )
            output += result.stdout + result.stderr

    missing = [sm for sm in args.sm_list if f"sm_{sm}" not in output]
    if missing:
        print(output)
        raise SystemExit(f"Missing CUDA cubins for SM: {' '.join(missing)}")

    print(f"Confirmed CUDA cubins for SM: {' '.join(args.sm_list)}")


if __name__ == "__main__":
    main()
