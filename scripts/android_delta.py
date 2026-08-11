#!/usr/bin/env python3
"""Generate a small arm64-v8a APK delta for CountDownTodo.

The generated CDTDELTA1 file is intentionally simple and streamable:
unchanged 64 KiB blocks are copied from the installed APK, while changed
blocks are embedded in the patch. Applying the patch produces the exact target
APK bytes, including its existing Android signature.

Usage:
  python3 scripts/android_delta.py old.apk new.apk update.patch \
    --from-version 5.6.17 --to-version 5.6.18
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path


MAGIC = b"CDTDELTA"
FORMAT_VERSION = 1
CHUNK_SIZE = 64 * 1024
MAX_DATA_OPERATION_SIZE = 16 * 1024 * 1024
COPY = 0
DATA = 1


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def read_chunks(path: Path) -> list[bytes]:
    chunks: list[bytes] = []
    with path.open("rb") as source:
        while chunk := source.read(CHUNK_SIZE):
            chunks.append(chunk)
    return chunks


def merge_operations(operations: list[tuple[int, int, bytes | int]]) -> list[tuple[int, int, bytes | int]]:
    merged: list[tuple[int, int, bytes | int]] = []
    for operation in operations:
        op_type, length, value = operation
        if not merged:
            merged.append(operation)
            continue

        previous_type, previous_length, previous_value = merged[-1]
        if op_type == DATA and previous_type == DATA:
            assert isinstance(previous_value, bytes)
            assert isinstance(value, bytes)
            if previous_length + length <= MAX_DATA_OPERATION_SIZE:
                merged[-1] = (DATA, previous_length + length, previous_value + value)
            else:
                merged.append(operation)
        elif op_type == COPY and previous_type == COPY:
            assert isinstance(previous_value, int)
            assert isinstance(value, int)
            if previous_value + previous_length == value:
                merged[-1] = (COPY, previous_length + length, previous_value)
            else:
                merged.append(operation)
        else:
            merged.append(operation)
    return merged


def build_operations(old_chunks: list[bytes], new_chunks: list[bytes]) -> list[tuple[int, int, bytes | int]]:
    old_offsets: dict[bytes, list[tuple[int, int]]] = {}
    offset = 0
    for chunk in old_chunks:
        old_offsets.setdefault(hashlib.blake2b(chunk, digest_size=16).digest(), []).append(
            (offset, len(chunk))
        )
        offset += len(chunk)

    operations: list[tuple[int, int, bytes | int]] = []
    for chunk in new_chunks:
        digest = hashlib.blake2b(chunk, digest_size=16).digest()
        match = None
        for candidate_offset, candidate_length in old_offsets.get(digest, []):
            if candidate_length == len(chunk):
                match = candidate_offset
                break
        if match is None:
            operations.append((DATA, len(chunk), chunk))
        else:
            operations.append((COPY, len(chunk), match))
    return merge_operations(operations)


def write_patch(path: Path, old_size: int, new_size: int, operations: list[tuple[int, int, bytes | int]]) -> None:
    with path.open("wb") as target:
        target.write(MAGIC)
        target.write(struct.pack("<IQQII", FORMAT_VERSION, old_size, new_size, CHUNK_SIZE, len(operations)))
        for op_type, length, value in operations:
            target.write(struct.pack("<BQI", op_type, value if op_type == COPY else 0, length))
            if op_type == DATA:
                assert isinstance(value, bytes)
                target.write(value)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("old_apk", type=Path)
    parser.add_argument("new_apk", type=Path)
    parser.add_argument("patch", type=Path)
    parser.add_argument("--from-version", required=True)
    parser.add_argument("--to-version", required=True)
    args = parser.parse_args()

    if not args.old_apk.is_file():
        parser.error(f"old APK does not exist: {args.old_apk}")
    if not args.new_apk.is_file():
        parser.error(f"new APK does not exist: {args.new_apk}")

    old_chunks = read_chunks(args.old_apk)
    new_chunks = read_chunks(args.new_apk)
    operations = build_operations(old_chunks, new_chunks)
    args.patch.parent.mkdir(parents=True, exist_ok=True)
    write_patch(args.patch, args.old_apk.stat().st_size, args.new_apk.stat().st_size, operations)

    metadata = {
        "from_version": args.from_version,
        "from_sha256": sha256(args.old_apk),
        "to_version": args.to_version,
        "to_sha256": sha256(args.new_apk),
        "patch_size": args.patch.stat().st_size,
        "patch_url": "REPLACE_WITH_RELEASE_URL",
        "operation_count": len(operations),
        "full_apk_size": args.new_apk.stat().st_size,
        "recommended": args.patch.stat().st_size < args.new_apk.stat().st_size,
    }
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
