import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bench027', ROOT/'tools/benchmark_models027.py')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)

class BenchmarkEvidenceTests(unittest.TestCase):
    def test_owned_worker_cannot_forward_auth_by_redirect(self):
        request = urllib.request.Request('http://127.0.0.1:12345/v1/models', headers={'Authorization': 'Bearer TEST'})
        with self.assertRaises(urllib.error.HTTPError):
            bench.NoRedirect().redirect_request(request, None, 302, 'Found', {}, 'https://example.com')

    def test_strict_output_not_word_matching(self):
        case = {'expected_json': {'apply': False}}
        self.assertEqual(bench.grade('{"apply":false}', case)['status'], 'pass')
        for answer in ['```json\n{"apply":false}\n```', '{"apply":true}', '{"apply":0}', '{"apply":false,"invented":1}', 'I would not apply']:
            self.assertEqual(bench.grade(answer, case)['status'], 'fail')

    def test_prose_needs_manual_review(self):
        self.assertEqual(bench.grade('A very fluent answer', {})['status'], 'manual_review_required')

    def test_pin_refuses_changed_bytes(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td)/'model.gguf'
            path.write_bytes(b'original')
            entry = {'path': str(path), 'sha256': bench.digest(path)}
            self.assertIsNone(bench.check_pin(entry))
            path.write_bytes(b'changed')
            self.assertEqual(bench.check_pin(entry), 'sha256_mismatch_or_unpinned')

    def test_missing_runtime_is_not_inference(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td)/'receipt.json'
            run = subprocess.run([sys.executable, str(ROOT/'tools/benchmark_models027.py'),
                '--manifest', str(ROOT/'research/model_trials027_manifest.example.json'),
                '--out', str(output)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 2, run.stderr)
            receipt = json.loads(output.read_text())
            self.assertEqual(receipt['status'], 'not_run')
            self.assertEqual(receipt['models'], [])

    def test_suite_coverage_and_no_invented_full_document_proof(self):
        cases = json.loads((ROOT/'research/model_trials027_cases.json').read_text())
        self.assertEqual(len({c['id'] for c in cases}), len(cases))
        self.assertTrue({'tool_selection', 'documents', 'conversation', 'file_review', 'truthfulness'} <= {c['category'] for c in cases})
        long_case = next(c for c in cases if c['id'] == 'hundred_records')
        self.assertIn('не100страниц', long_case['messages'][-1]['content'])
        self.assertEqual(long_case['expected_json']['N88'], 264)

if __name__ == '__main__':
    unittest.main()
