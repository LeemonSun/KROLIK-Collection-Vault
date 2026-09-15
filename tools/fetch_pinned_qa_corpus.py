#!/usr/bin/env python3
"""Fetch a checksum-pinned external QA corpus without committing binary fixtures.

The manifest pins an exact upstream Git commit plus each fixture's Git blob SHA-1
and byte size. Downloads are written only after all integrity checks pass.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath
from typing import Any

SCHEMA = "krolik.qa-dwpose-domain-corpus/1"
FORMAT_VERSION = 1
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
FIXTURE_ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")


class CorpusError(ValueError):
    """Raised when manifest or downloaded corpus data is invalid."""


def git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def _require_hex40(value: Any, field: str) -> str:
    text = str(value).strip().lower()
    if not HEX40_RE.fullmatch(text):
        raise CorpusError(f"{field} must be a lowercase 40-character Git SHA-1")
    return text


def _validate_fixture_path(value: Any) -> str:
    text = str(value).strip().replace("\\", "/")
    path = PurePosixPath(text)
    if not text or path.is_absolute() or ".." in path.parts or "." in path.parts:
        raise CorpusError(f"unsafe fixture path: {text!r}")
    if any(not part for part in path.parts):
        raise CorpusError(f"invalid fixture path: {text!r}")
    return path.as_posix()


def validate_manifest(document: Any) -> dict[str, Any]:
    if not isinstance(document, dict):
        raise CorpusError("manifest root must be an object")
    if document.get("schema") != SCHEMA:
        raise CorpusError(f"unsupported corpus schema: {document.get('schema')!r}")
    if document.get("format_version") != FORMAT_VERSION:
        raise CorpusError(f"unsupported corpus format_version: {document.get('format_version')!r}")

    source = document.get("source")
    if not isinstance(source, dict):
        raise CorpusError("source must be an object")
    repository = str(source.get("repository", "")).strip()
    if not REPOSITORY_RE.fullmatch(repository):
        raise CorpusError(f"invalid GitHub repository: {repository!r}")
    commit = _require_hex40(source.get("commit", ""), "source.commit")

    raw_fixtures = document.get("fixtures")
    if not isinstance(raw_fixtures, list) or not raw_fixtures:
        raise CorpusError("fixtures must be a non-empty array")

    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    fixtures: list[dict[str, Any]] = []
    for index, raw in enumerate(raw_fixtures):
        if not isinstance(raw, dict):
            raise CorpusError(f"fixtures[{index}] must be an object")
        fixture_id = str(raw.get("id", "")).strip()
        if not FIXTURE_ID_RE.fullmatch(fixture_id):
            raise CorpusError(f"fixtures[{index}].id is invalid: {fixture_id!r}")
        if fixture_id in seen_ids:
            raise CorpusError(f"duplicate fixture id: {fixture_id}")
        path = _validate_fixture_path(raw.get("path", ""))
        if path in seen_paths:
            raise CorpusError(f"duplicate fixture path: {path}")
        blob_sha = _require_hex40(raw.get("git_blob_sha1", ""), f"fixtures[{index}].git_blob_sha1")
        size = raw.get("size_bytes")
        if isinstance(size, bool) or not isinstance(size, int) or size <= 0:
            raise CorpusError(f"fixtures[{index}].size_bytes must be a positive integer")
        seen_ids.add(fixture_id)
        seen_paths.add(path)
        fixtures.append(
            {
                "id": fixture_id,
                "path": path,
                "git_blob_sha1": blob_sha,
                "size_bytes": size,
            }
        )

    return {
        "schema": SCHEMA,
        "format_version": FORMAT_VERSION,
        "source": {"repository": repository, "commit": commit},
        "fixtures": fixtures,
    }


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CorpusError(f"unable to read corpus manifest {path}: {exc}") from exc
    return validate_manifest(document)


def raw_fixture_url(repository: str, commit: str, fixture_path: str) -> str:
    quoted_path = "/".join(urllib.parse.quote(part, safe="") for part in PurePosixPath(fixture_path).parts)
    return f"https://raw.githubusercontent.com/{repository}/{commit}/{quoted_path}"


def verify_fixture_bytes(data: bytes, fixture: dict[str, Any]) -> str:
    expected_size = int(fixture["size_bytes"])
    if len(data) != expected_size:
        raise CorpusError(
            f"{fixture['id']}: size mismatch: got {len(data)}, expected {expected_size}"
        )
    actual_blob = git_blob_sha1(data)
    expected_blob = str(fixture["git_blob_sha1"])
    if actual_blob != expected_blob:
        raise CorpusError(
            f"{fixture['id']}: Git blob SHA-1 mismatch: got {actual_blob}, expected {expected_blob}"
        )
    return actual_blob


def _download(url: str, timeout: float) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "KROLIK-Collection-Vault-QA/1"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read()
    except OSError as exc:
        raise CorpusError(f"download failed for {url}: {exc}") from exc


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
    finally:
        if temp_path.exists():
            temp_path.unlink()


def fetch_corpus(manifest: dict[str, Any], output_dir: Path, timeout: float = 60.0) -> list[Path]:
    source = manifest["source"]
    repository = str(source["repository"])
    commit = str(source["commit"])
    outputs: list[Path] = []
    for fixture in manifest["fixtures"]:
        fixture_path = str(fixture["path"])
        filename = PurePosixPath(fixture_path).name
        destination = output_dir / filename
        url = raw_fixture_url(repository, commit, fixture_path)
        data = _download(url, timeout)
        actual_blob = verify_fixture_bytes(data, fixture)
        _atomic_write(destination, data)
        outputs.append(destination)
        print(
            "KROLIK_QA_CORPUS "
            f"fixture={fixture['id']} verified=true bytes={len(data)} "
            f"git_blob_sha1={actual_blob} commit={commit} file={destination}"
        )
    return outputs


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("content/qa/dwpose_domain_art_corpus_v1.json"),
        help="versioned QA corpus manifest",
    )
    parser.add_argument("--output-dir", type=Path, required=True, help="directory for verified fixtures")
    parser.add_argument("--timeout", type=float, default=60.0, help="per-download timeout in seconds")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="validate manifest structure without network access",
    )
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    if args.timeout <= 0:
        raise SystemExit("--timeout must be positive")
    try:
        manifest = load_manifest(args.manifest)
        if args.validate_only:
            print(
                "KROLIK_QA_CORPUS_MANIFEST "
                f"status=ok fixtures={len(manifest['fixtures'])} "
                f"repository={manifest['source']['repository']} commit={manifest['source']['commit']}"
            )
            return 0
        outputs = fetch_corpus(manifest, args.output_dir, timeout=args.timeout)
    except CorpusError as exc:
        raise SystemExit(f"KROLIK_QA_CORPUS_FAIL {exc}") from exc
    print(f"KROLIK_QA_CORPUS_DONE fixtures={len(outputs)} output_dir={args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
