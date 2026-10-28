#!/usr/bin/env python3
"""Run local checks and retain exact logs plus a human-readable validation report."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    # A fresh profile per group prevents persisted locale/fixtures from leaking
    # into later checks, and never touches the developer's real app data.
    env = dict(os.environ)
    engine = str(Path(args.godot).resolve())
    commands = [
        ("adaptive015",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_adaptive015.gd","--","--test-mode"]),
        ("copy_knowledge015",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_copy_knowledge015.gd","--","--test-mode"]),
        ("structure", [sys.executable, str(ROOT / "tools/verify_project.py")]),
        ("core", [engine, "--headless", "--path", str(ROOT), "--script",
                  "res://tests/test_core.gd", "--", "--test-mode"]),
        ("http", [sys.executable, str(ROOT / "tools/test_http.py"), engine]),
        ("local_runtime", [engine, "--headless", "--path", str(ROOT), "--script",
                          "res://tests/test_local_runtime.gd", "--", "--test-mode"]),
        ("search", [engine, "--headless", "--path", str(ROOT), "--script",
                    "res://tests/test_search.gd", "--", "--test-mode"]),
        ("persistence",[sys.executable,str(ROOT/"tools/test_persistence.py"),engine]),
        ("vision",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_vision.gd","--","--test-mode"]),
        ("bundle",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_bundle.gd","--","--test-mode"]),
        ("window_reader",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_window_reader.gd","--","--test-mode"]),
        ("file_memory",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_file_memory.gd","--","--test-mode"]),
        ("queue_table",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_queue_table.gd","--","--test-mode"]),
        ("utilities014",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_utilities014.gd","--","--test-mode"]),
        ("public_tls014",[sys.executable,str(ROOT/"tools/test_public_tls.py"),engine]),
        ("public_transport014",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_public_transport014.gd","--","--test-mode"]),
        ("technical013",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_technical013.gd","--","--test-mode"]),
        ("office",[sys.executable,str(ROOT/"tools/test_office.py"),engine]),
        ("workflow",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_workflow.gd","--","--test-mode"]),
        ("action_proposal",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_action_proposal.gd","--","--test-mode"]),
        ("access",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_access.gd","--","--test-mode"]),
        ("voice",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_voice.gd","--","--test-mode"]),
        ("desktop060",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_desktop060.gd","--","--test-mode"]),
        ("leemon_tools",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_leemon_tools.gd","--","--test-mode"]),
        ("functional", [engine,"--headless","--path",str(ROOT),"--script","res://tests/test_functional.gd","--","--test-mode"]),
        ("behavior",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_behavior.gd","--","--test-mode"]),
        ("animation", [engine, "--headless", "--path", str(ROOT), "--script",
                       "res://tests/test_animation.gd", "--", "--test-mode"]),
        ("self_knowledge", [engine, "--headless", "--path", str(ROOT), "--script",
                            "res://tests/test_self_knowledge.gd", "--", "--test-mode"]),
        ("chat_layout", [engine, "--headless", "--path", str(ROOT), "--script",
                         "res://tests/test_chat_layout.gd", "--", "--test-mode"]),
        ("ui", [engine, "--headless", "--path", str(ROOT), "--", "--ui-smoke", "--test-mode"]),
        ("release_gate_expected_block", [sys.executable, str(ROOT / "tools/release_gate.py"), "--expect-blocked"]),
    ]
    outcomes = []
    for name, command in commands:
        with tempfile.TemporaryDirectory(prefix="leemon-check-"+name+"-") as profile:
            group_env = dict(env, XDG_DATA_HOME=profile, XDG_CONFIG_HOME=profile)
            result = subprocess.run(command, cwd=ROOT, env=group_env, capture_output=True, text=True, timeout=90)
        log = result.stdout + result.stderr
        (reports / f"{name}.txt").write_text(log, encoding="utf-8")
        # Godot can report runtime errors and still exit zero.
        ok = result.returncode == 0 and "SCRIPT ERROR:" not in log and "\nERROR:" not in log
        outcomes.append((name, ok))
        print(f"{name}: {'PASS' if ok else 'FAIL'}", flush=True)
        if not ok:
            print(log, flush=True)
    lines = [
        "# Проверки приложения", "",
        "Дата: 28.10.2026. Linux x86_64, Godot 4.7.2 standard.", "",
        "| Проверка | Результат |", "| --- | --- |",
        *[f"| {name} | {'PASS' if ok else 'FAIL'} |" for name, ok in outcomes],
        "", "release_gate_expected_block = PASS означает, что неподготовленная сборка правильно заблокирована.",
        "", "Leemon 0.15: один мастер, шесть частей 2D-рига и26процедурных состояний. Это не рисованные клипы, 3D или facial rig.",
        "Офлайн-часы, сохраняемые напоминания и явный перевод буфера проверяются в leemon_tools; тесты провайдера используют подмену и не доказывают качество нейросети.",
        "Native X11 review, фактический Godot → PowerShell roundtrip и двухфайловое обновление проверяются отдельно: native_ui.txt, exported_content.txt, desktop_bridge.txt, preview_update.txt.",
        "Настоящая Windows здесь не запускалась: EXE, прозрачность, перемещение, системный голос, установщик модели и блокировки файлов требуют отдельной приёмки.",
        "Qwen3.5-2B Q4: прежние text/vision fixtures проверены отдельно; качество нового adaptive loop настоящей моделью не измерено; научная точность ограничена. Полный offline-пакет использует AI/ рядом с EXE, лёгкий пакет предлагает явную установку.",
        "ASR реализован через локальный Whisper. Разовый анализ экрана реализован; real fixture в vision_real.txt. Общие Windows UIA-действия и явное чтение доступного текста выбранного окна с выдержками реализованы, но Windows приёмка впереди. Собственный голос отсутствует; explicit public HTTPS excerpts reader имеет ограничения, см. WORKFLOWS_014.md. Каталог движений — план производства, а не готовые клипы.",
    ]
    (reports / "VALIDATION.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0 if all(ok for _, ok in outcomes) else 1

if __name__ == "__main__":
    sys.exit(main())

