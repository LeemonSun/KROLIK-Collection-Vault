#!/usr/bin/env python3
"""Sequential local GGUF trials. No downloads, real PC actions or automatic adoption.

Supply a private manifest with runtime/path+sha256 and models/id,path,sha256,
source_revision,quantization. All outputs are synthetic; missing files are NOT runs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import secrets
import signal
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, 'Local worker redirects refused', headers, fp)

def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def check_pin(spec):
    path = Path(spec.get('path', ''))
    if not path.is_file():
        return 'missing_local_file'
    expected = spec.get('sha256', '')
    if len(expected) != 64 or digest(path) != expected:
        return 'sha256_mismatch_or_unpinned'
    return None

def grade(answer, spec):
    """Exact fixture correctness only; never treats fluent prose as verified quality."""
    if 'expected_json' not in spec:
        return {'status': 'manual_review_required'}
    try:
        value = json.loads(answer)
    except ValueError:
        return {'status': 'fail', 'reason': 'not_exact_json'}
    equal = json.dumps(value, sort_keys=True) == json.dumps(spec['expected_json'], sort_keys=True)
    return {'status': 'pass' if equal else 'fail'}

def rss(pid):
    if platform.system() == 'Linux':
        try:
            for line in Path(f'/proc/{pid}/status').read_text().splitlines():
                if line.startswith('VmRSS:'):
                    return int(line.split()[1])*1024
        except OSError:
            pass
    return None  # No fabricated Windows/app-total measurement.

def stop_owned(worker):
    if worker is not None and worker.poll() is None:
        worker.terminate()
        try:
            worker.wait(timeout=5)
        except subprocess.TimeoutExpired:
            worker.kill()
            worker.wait(timeout=5)

def run_trial(runtime, model, cases, args, save):
    record = {'id': model['id'], 'model_sha256': model.get('sha256'),
              'source_revision': model.get('source_revision'),
              'quantization': model.get('quantization'), 'cases': [],
              'status': 'preflight', 'scope': 'text synthetic inference; NOT real app execution, visual or100page acceptance'}
    error = check_pin(model)
    if not model.get('source_revision') or not model.get('quantization'):
        error = error or 'missing_provenance'
    if error:
        record.update(status='not_run', reason=error)
        return record
    save(record)
    token = secrets.token_hex(32)
    with socket.socket() as bound:
        bound.bind(('127.0.0.1', 0))
        port = bound.getsockname()[1]
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    def call(path, body=None, timeout=None):
        req = urllib.request.Request(f'http://127.0.0.1:{port}'+path,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Authorization': 'Bearer '+token, 'Content-Type': 'application/json'})
        with opener.open(req, timeout=timeout or args.timeout) as response:
            return json.load(response)
    worker = None
    done = threading.Event()
    samples = []
    monitor = None
    try:
        with tempfile.TemporaryDirectory(prefix='leemon-model027-') as temporary:
            with (Path(temporary)/'worker.log').open('w') as log:
                executable = Path(runtime['path']).resolve()
                command = [str(executable), '--model', str(Path(model['path']).resolve()),
                    '--host', '127.0.0.1', '--port', str(port), '--api-key', token,
                    '--alias', 'trial', '--ctx-size', str(args.context),
                    '--threads', str(args.threads), '--threads-batch', str(args.threads),
                    '--parallel', '1', '--n-gpu-layers', '0', '--batch-size', '32',
                    '--ubatch-size', '32', '--poll', '0', '--prio', '-1', '--no-ui',
                    '--jinja', '--reasoning', 'off', '--cache-ram', '0', '--ctx-checkpoints', '0']
                started = time.monotonic()
                worker = subprocess.Popen(command, stdout=log, stderr=log,
                    env=dict(os.environ, LD_LIBRARY_PATH=str(executable.parent)))
                def sample():
                    while not done.wait(.1):
                        value = rss(worker.pid)
                        if value is not None:
                            samples.append(value)
                monitor = threading.Thread(target=sample, daemon=True)
                monitor.start()
                while True:
                    if worker.poll() is not None:
                        raise RuntimeError('worker_start_failed: '+(Path(temporary)/'worker.log').read_text()[-800:])
                    try:
                        call('/v1/models', timeout=1)
                        break
                    except Exception:
                        if time.monotonic()-started > 90:
                            raise TimeoutError('startup_deadline')
                        time.sleep(.1)
                record.update(status='running', startup_ms=round((time.monotonic()-started)*1000))
                for seed in args.seeds:
                    for case in cases:
                        row = {'id': case['id'], 'category': case['category'], 'seed': seed,
                               'rubric': case['rubric']}
                        started = time.monotonic()
                        try:
                            kwargs = model.get('chat_template_kwargs', {})
                            rendered = call('/apply-template', {'messages': case['messages'],
                                'add_generation_prompt': True, 'chat_template_kwargs': kwargs})
                            count = len(call('/tokenize', {'content': rendered.get('prompt', rendered.get('content', '')),
                                'add_special': False})['tokens'])
                            budget = case.get('max_tokens', 192)
                            row['prompt_tokens'] = count
                            if count+budget+64 > args.context:
                                row.update(status='not_run', reason='context_budget_exceeded')
                            else:
                                result = call('/v1/chat/completions', {'model': 'trial',
                                    'messages': case['messages'], 'max_tokens': budget,
                                    'temperature': .1, 'top_p': .9, 'seed': seed,
                                    'cache_prompt': False, 'stream': False, 'chat_template_kwargs': kwargs})
                                choice = result['choices'][0]
                                answer = choice['message'].get('content') or ''
                                finish = choice.get('finish_reason')
                                row.update(status='generated', answer=answer, finish=finish,
                                    usage=result.get('usage'), timings=result.get('timings'),
                                    grading=grade(answer, case) if finish == 'stop' else
                                        {'status': 'fail', 'reason': 'incomplete_or_nonstop_response'})
                        except Exception as exc:
                            row.update(status='error', error=(type(exc).__name__+': '+str(exc))[:400].replace(token, 'REDACTED'))
                            # A timed-out HTTP request must not leave inference consuming CPU.
                            record['status'] = 'aborted_on_request_error'
                        row['wall_ms'] = round((time.monotonic()-started)*1000)
                        record['cases'].append(row)
                        save(record)
                        if record['status'] == 'aborted_on_request_error':
                            return record
                record['status'] = 'completed'
    except KeyboardInterrupt:
        record['status'] = 'interrupted'
        raise
    except Exception as exc:
        record.update(status='error', error=(type(exc).__name__+': '+str(exc))[:1000].replace(token, 'REDACTED'))
    finally:
        done.set()
        if monitor is not None:
            monitor.join(timeout=1)
        stop_owned(worker)
        record['sampled_worker_peak_rss_bytes'] = max(samples) if samples else None
        record['rss_scope'] = 'sampled Linux worker only; not app total/Windows, may miss peaks'
        save(record)
    return record

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--cases', type=Path, default=ROOT/'research/model_trials027_cases.json')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--threads', type=int, choices=[1, 2, 4], default=2)
    parser.add_argument('--context', type=int, choices=[2048, 4096, 8192], default=4096)
    parser.add_argument('--timeout', type=int, choices=[30, 60, 120], default=30)
    parser.add_argument('--seeds', nargs='+', type=int, default=[42, 43])
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    manifest = json.loads(args.manifest.read_text())
    cases = json.loads(args.cases.read_text())
    report = {'scope': 'development only, no production model changed', 'host': platform.platform(),
        'runner_sha256': digest(__file__), 'cases_sha256': digest(args.cases),
        'runtime_sha256': manifest['runtime'].get('sha256'), 'threads': args.threads,
        'context': args.context, 'timeout_seconds': args.timeout, 'seeds': args.seeds,
        'warmup': 'none; first case includes first-generation overhead', 'models': []}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    def save(record=None):
        if record is not None:
            report['models'] = [x for x in report['models'] if x['id'] != record['id']]+[record]
        temporary = args.out.with_suffix(args.out.suffix+'.tmp')
        temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
        temporary.replace(args.out)
    error = check_pin(manifest['runtime'])
    if error:
        report.update(status='not_run', reason='runtime_'+error)
        save()
        return 2
    if len({x['id'] for x in manifest['models']}) != len(manifest['models']):
        raise ValueError('Duplicate model IDs')
    for model in manifest['models']:
        save(run_trial(manifest['runtime'], model, cases, args, save))
    report['status'] = 'completed' if report['models'] and all(x['status'] == 'completed' for x in report['models']) else 'incomplete'
    save()
    return 0 if report['status'] == 'completed' else 2

if __name__ == '__main__':
    raise SystemExit(main())
