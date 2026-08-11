#!/usr/bin/env python3
"""Generate a small arm64-v8a APK delta for CountDownTodo.

The generated CDTDELTA1 file is intentionally simple and streamable:
unchanged APK ZIP local-file spans are copied from the installed APK, while
changed bytes are embedded in the patch. Copying ZIP entries instead of fixed
offset blocks keeps reuse working when an earlier entry changes size and shifts
all later entries. Applying the patch produces the exact target APK bytes,
including its existing Android signature.

Usage:
  python3 scripts/android_delta.py old.apk new.apk update.patch \
    --from-version 5.6.17 --to-version 5.6.18
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from zipfile import BadZipFile, ZipFile, ZipInfo
from pathlib import Path


MAGIC = b"CDTDELTA"
FORMAT_VERSION = 1
CHUNK_SIZE = 64 * 1024
MAX_DATA_OPERATION_SIZE = 16 * 1024 * 1024
COPY = 0
DATA = 1
LOCAL_FILE_HEADER = struct.Struct("<IHHHHHIIIHH")
LOCAL_FILE_HEADER_SIGNATURE = 0x04034B50
DATA_DESCRIPTOR_SIGNATURE = 0x08074B50


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


def local_file_span(data: bytes, info: ZipInfo) -> tuple[int, int]:
    """Return the raw local-header and compressed-data span for a ZIP entry."""

    header_offset = info.header_offset
    if header_offset < 0 or header_offset + LOCAL_FILE_HEADER.size > len(data):
        raise ValueError(f"Invalid local header offset for {info.filename}")

    (
        signature,
        _version,
        flags,
        _method,
        _modified_time,
        _modified_date,
        _crc,
        _compressed_size,
        _uncompressed_size,
        filename_length,
        extra_length,
    ) = LOCAL_FILE_HEADER.unpack_from(data, header_offset)
    if signature != LOCAL_FILE_HEADER_SIGNATURE:
        raise ValueError(f"Invalid local header for {info.filename}")

    data_offset = (
        header_offset
        + LOCAL_FILE_HEADER.size
        + filename_length
        + extra_length
    )
    data_end = data_offset + info.compress_size
    if data_end > len(data):
        raise ValueError(f"Compressed data exceeds APK for {info.filename}")

    # Android APKs normally have flag 0 and no data descriptor. Handle the
    # descriptor form as well so the ZIP-aware path remains safe for other APKs.
    if flags & 0x08:
        if data_end + 4 > len(data):
            raise ValueError(f"Missing data descriptor for {info.filename}")
        descriptor_signature = struct.unpack_from("<I", data, data_end)[0]
        zip64 = info.file_size > 0xFFFFFFFF or info.compress_size > 0xFFFFFFFF
        descriptor_size = 24 if zip64 else 16
        if descriptor_signature != DATA_DESCRIPTOR_SIGNATURE:
            descriptor_size -= 4
        data_end += descriptor_size
        if data_end > len(data):
            raise ValueError(f"Data descriptor exceeds APK for {info.filename}")

    return header_offset, data_end


def build_zip_operations(
    old_apk: Path, new_apk: Path
) -> tuple[list[tuple[int, int, bytes | int]], int]:
    """Reuse unchanged raw ZIP entry spans even when their offsets changed."""

    old_data = old_apk.read_bytes()
    new_data = new_apk.read_bytes()
    with ZipFile(old_apk) as old_zip, ZipFile(new_apk) as new_zip:
        old_infos = {info.filename: info for info in old_zip.infolist()}
        new_infos = {info.filename: info for info in new_zip.infolist()}

        reusable_spans: list[tuple[int, int, int]] = []
        for name, new_info in new_infos.items():
            old_info = old_infos.get(name)
            if old_info is None:
                continue
            if (
                old_info.CRC != new_info.CRC
                or old_info.file_size != new_info.file_size
                or old_info.compress_size != new_info.compress_size
            ):
                continue

            old_start, old_end = local_file_span(old_data, old_info)
            new_start, new_end = local_file_span(new_data, new_info)
            if new_end - new_start != old_end - old_start:
                continue
            if old_data[old_start:old_end] == new_data[new_start:new_end]:
                reusable_spans.append((new_start, new_end, old_start))

    reusable_spans.sort()
    operations: list[tuple[int, int, bytes | int]] = []
    cursor = 0
    copied_bytes = 0
    for new_start, new_end, old_start in reusable_spans:
        if new_start < cursor:
            continue
        if new_start > cursor:
            operations.append((DATA, new_start - cursor, new_data[cursor:new_start]))
        length = new_end - new_start
        operations.append((COPY, length, old_start))
        copied_bytes += length
        cursor = new_end

    if cursor < len(new_data):
        operations.append((DATA, len(new_data) - cursor, new_data[cursor:]))

    return merge_operations(operations), copied_bytes


def operation_bytes(operations: list[tuple[int, int, bytes | int]]) -> tuple[int, int]:
    copied = 0
    embedded = 0
    for operation_type, length, _value in operations:
        if operation_type == COPY:
            copied += length
        else:
            embedded += length
    return copied, embedded


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

    algorithm = "apk-zip-local-spans"
    try:
        operations, copied_bytes = build_zip_operations(args.old_apk, args.new_apk)
    except (BadZipFile, OSError, ValueError) as error:
        print(f"⚠️ ZIP-aware diff unavailable, falling back to 64 KiB blocks: {error}")
        old_chunks = read_chunks(args.old_apk)
        new_chunks = read_chunks(args.new_apk)
        operations = build_operations(old_chunks, new_chunks)
        copied_bytes, _embedded_bytes = operation_bytes(operations)
        algorithm = "fixed-64k-blocks"

    args.patch.parent.mkdir(parents=True, exist_ok=True)
    write_patch(args.patch, args.old_apk.stat().st_size, args.new_apk.stat().st_size, operations)

    copied_bytes, embedded_bytes = operation_bytes(operations)
    patch_size = args.patch.stat().st_size

    metadata = {
        "from_version": args.from_version,
        "from_sha256": sha256(args.old_apk),
        "to_version": args.to_version,
        "to_sha256": sha256(args.new_apk),
        "patch_size": patch_size,
        "patch_url": "REPLACE_WITH_RELEASE_URL",
        "operation_count": len(operations),
        "full_apk_size": args.new_apk.stat().st_size,
        "copied_bytes": copied_bytes,
        "embedded_bytes": embedded_bytes,
        "algorithm": algorithm,
        "recommended": patch_size < args.new_apk.stat().st_size and copied_bytes > 0,
    }
    print(json.dumps(metadata, ensure_ascii=False, indent=2))

    if copied_bytes == 0 or patch_size >= args.new_apk.stat().st_size:
        raise SystemExit(
            "生成的差分包没有带来体积收益，已拒绝作为增量包发布；"
            "请检查基线 APK 或差分算法。"
        )


if __name__ == "__main__":
    main()
