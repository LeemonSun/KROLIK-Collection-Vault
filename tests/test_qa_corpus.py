from __future__ import annotations

import copy

import pytest

from tools.fetch_pinned_qa_corpus import (
    CorpusError,
    FORMAT_VERSION,
    SCHEMA,
    git_blob_sha1,
    raw_fixture_url,
    validate_manifest,
    verify_fixture_bytes,
)


def _manifest(data: bytes = b"fixture-bytes") -> dict:
    return {
        "schema": SCHEMA,
        "format_version": FORMAT_VERSION,
        "source": {
            "repository": "Example/Fixtures",
            "commit": "1" * 40,
        },
        "fixtures": [
            {
                "id": "sample",
                "path": "art/sample.png",
                "git_blob_sha1": git_blob_sha1(data),
                "size_bytes": len(data),
            }
        ],
    }


def test_git_blob_sha1_matches_git_object_format() -> None:
    # Published Git object example: SHA-1 is over b"blob <len>\0" + payload,
    # not the raw payload alone.
    data = b"hello\n"
    assert git_blob_sha1(data) == "ce013625030ba8dba906f756967f9e9ca394464a"


def test_manifest_normalizes_and_builds_exact_commit_url() -> None:
    document = validate_manifest(_manifest())
    fixture = document["fixtures"][0]
    assert document["source"]["commit"] == "1" * 40
    assert fixture["path"] == "art/sample.png"
    assert raw_fixture_url(
        document["source"]["repository"],
        document["source"]["commit"],
        fixture["path"],
    ) == (
        "https://raw.githubusercontent.com/Example/Fixtures/"
        + "1" * 40
        + "/art/sample.png"
    )


def test_verify_fixture_bytes_accepts_exact_git_blob() -> None:
    data = b"fixture-bytes"
    fixture = validate_manifest(_manifest(data))["fixtures"][0]
    assert verify_fixture_bytes(data, fixture) == fixture["git_blob_sha1"]


@pytest.mark.parametrize(
    ("mutator", "message"),
    [
        (lambda d: d.update(schema="wrong"), "unsupported corpus schema"),
        (lambda d: d["source"].update(commit="main"), "source.commit"),
        (lambda d: d["fixtures"][0].update(git_blob_sha1="0" * 39), "git_blob_sha1"),
        (lambda d: d["fixtures"][0].update(size_bytes=0), "size_bytes"),
        (lambda d: d["fixtures"][0].update(path="../escape.png"), "unsafe fixture path"),
    ],
)
def test_manifest_rejects_invalid_integrity_contract(mutator, message: str) -> None:
    document = copy.deepcopy(_manifest())
    mutator(document)
    with pytest.raises(CorpusError, match=message):
        validate_manifest(document)


def test_manifest_rejects_duplicate_fixture_ids_and_paths() -> None:
    document = _manifest()
    duplicate = copy.deepcopy(document["fixtures"][0])
    duplicate["git_blob_sha1"] = "2" * 40
    document["fixtures"].append(duplicate)
    with pytest.raises(CorpusError, match="duplicate fixture id"):
        validate_manifest(document)

    document = _manifest()
    duplicate = copy.deepcopy(document["fixtures"][0])
    duplicate["id"] = "sample2"
    document["fixtures"].append(duplicate)
    with pytest.raises(CorpusError, match="duplicate fixture path"):
        validate_manifest(document)


def test_fixture_size_mismatch_is_rejected_before_hash() -> None:
    data = b"fixture-bytes"
    fixture = validate_manifest(_manifest(data))["fixtures"][0]
    fixture["size_bytes"] += 1
    with pytest.raises(CorpusError, match="size mismatch"):
        verify_fixture_bytes(data, fixture)


def test_fixture_blob_mismatch_is_rejected() -> None:
    data = b"fixture-bytes"
    fixture = validate_manifest(_manifest(data))["fixtures"][0]
    fixture["git_blob_sha1"] = "2" * 40
    with pytest.raises(CorpusError, match="Git blob SHA-1 mismatch"):
        verify_fixture_bytes(data, fixture)
