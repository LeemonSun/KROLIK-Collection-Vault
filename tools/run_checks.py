#!/usr/bin/env python3
"""Run local checks and retain exact logs plus a human-readable validation report."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    # Tests must not touch the developer's persistent app data.
    isolated = ROOT / ".godot/test-user"
    isolated.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["XDG_DATA_HOME"] = str(isolated.resolve())
    env["XDG_CONFIG_HOME"] = str(isolated.resolve())
    engine = str(Path(args.godot).resolve())
    commands = [
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
        ("action_proposal",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_action_proposal.gd","--","--test-mode"]),
        ("access",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_access.gd","--","--test-mode"]),
        ("voice",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_voice.gd","--","--test-mode"]),
        ("desktop060",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_desktop060.gd","--","--test-mode"]),
        ("leemon_tools",[engine,"--headless","--path",str(ROOT),"--script","res://tests/test_leemon_tools.gd","--","--test-mode"]),
        ("functional", [engine,"--headless","--path",str(ROOT),"--script","res://tests/test_functional.gd","--","--test-mode"]),
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
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=90)
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
        "", "Leemon 0.6: один мастер, шесть частей 2D-рига и шестнадцать процедурных состояний. Это не рисованные клипы, 3D или facial rig.",
        "Офлайн-часы, сохраняемые напоминания и явный перевод буфера проверяются в leemon_tools; тесты провайдера используют подмену и не доказывают качество нейросети.",
        "Native X11 review, фактический Godot → PowerShell roundtrip и двухфайловое обновление проверяются отдельно: native_ui.txt, exported_content.txt, desktop_bridge.txt, preview_update.txt.",
        "Настоящая Windows здесь не запускалась: EXE, прозрачность, перемещение, системный голос, установщик модели и блокировки файлов требуют отдельной приёмки.",
        "Qwen3.5-2B Q4 заменяет старую модель. Реальные text/vision fixtures проверены отдельно; научная точность ограничена. Полный offline-пакет использует AI/ рядом с EXE, лёгкий пакет предлагает явную установку.",
        "ASR реализован через локальный Whisper. Разовый анализ экрана реализован; real fixture в vision_real.txt. Общие Windows UIA-действия реализованы, но Windows приёмка впереди. Собственный голос и самостоятельное чтение веб-страниц отсутствуют. Каталог движений — план производства, а не готовые клипы.",
    ]
    (reports / "VALIDATION.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0 if all(ok for _, ok in outcomes) else 1

if __name__ == "__main__":
    sys.exit(main())

