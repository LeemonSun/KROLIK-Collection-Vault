from __future__ import annotations

import pytest

from tools.validate_dwpose_domain_report import ExpectationError, evaluate_report, validate_expectations


def _expectations():
    return validate_expectations({
        "schema": "krolik.qa-dwpose-domain-expectations/1",
        "format_version": 1,
        "cases": {
            "accepted.png": {"minimum": "dwpose-onnx"},
            "hard.png": {"minimum": "review-fallback"},
        },
    })


def _report(accepted_backend="dwpose-onnx", hard_backend="heuristic", hard_review=True):
    return {"cases": [
        {"image": "accepted.png", "backend": accepted_backend, "runtime_ready": True, "rig_review_required": accepted_backend != "dwpose-onnx"},
        {"image": "hard.png", "backend": hard_backend, "runtime_ready": True, "rig_review_required": hard_review},
    ]}


def test_baseline_passes_and_fallback_may_improve_to_dwpose():
    assert evaluate_report(_report(), _expectations()) == []
    assert evaluate_report(_report(hard_backend="dwpose-onnx", hard_review=False), _expectations()) == []


def test_known_dwpose_case_cannot_regress_even_if_aggregate_could_still_pass():
    errors = evaluate_report(_report(accepted_backend="heuristic"), _expectations())
    assert any("accepted.png: backend regressed" in error for error in errors)


def test_fallback_must_remain_explicitly_review_required():
    errors = evaluate_report(_report(hard_review=False), _expectations())
    assert errors == ["hard.png: fallback is not explicitly review-required"]


def test_missing_extra_and_non_runtime_cases_are_rejected():
    report = {"cases": [
        {"image": "accepted.png", "backend": "dwpose-onnx", "runtime_ready": False},
        {"image": "extra.png", "backend": "dwpose-onnx", "runtime_ready": True},
    ]}
    errors = evaluate_report(report, _expectations())
    assert any("missing expected cases: hard.png" in error for error in errors)
    assert any("unexpected report cases: extra.png" in error for error in errors)
    assert any("accepted.png: runtime_ready=false" in error for error in errors)


def test_expectation_schema_and_minimum_are_strict():
    with pytest.raises(ExpectationError, match="schema"):
        validate_expectations({"schema": "wrong", "format_version": 1, "cases": {"a.png": {"minimum": "dwpose-onnx"}}})
    with pytest.raises(ExpectationError, match="invalid minimum"):
        validate_expectations({"schema": "krolik.qa-dwpose-domain-expectations/1", "format_version": 1, "cases": {"a.png": {"minimum": "anything"}}})
