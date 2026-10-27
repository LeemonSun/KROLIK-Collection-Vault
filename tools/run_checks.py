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
        "# Проверки фундамента", "",
        "Дата: 27.10.2026. Linux x86_64, Godot 4.7.2 standard.", "",
        "| Проверка | Результат |", "| --- | --- |",
        *[f"| {name} | {'PASS' if ok else 'FAIL'} |" for name, ok in outcomes],
        "", "release_gate_expected_block = PASS означает, что неподготовленная сборка правильно заблокирована.",
        "", "Не проверены на настоящей Windows: запуск EXE, native-прозрачность/перетаскивание, установщик модели, озвучка/снимок и китайские глифы. Общий визуальный интеллект и автоматизация ещё не подключены.",
        "UI smoke проходит страницы/языки без дисплея; ChatView отдельно проверяется на 4 размерах и 3 языках. Native X11 review и применение патча — отдельные reports/native_ui.txt и reports/patch_application.txt; это не Windows приёмка.",
        "Включены рабочий концепт и прозрачный runtime-cutout Signal 01. Есть native-window прототип, перетаскивание и красный переход; настоящего рига/клипов нет. Текстовая модель скачивается явно по кнопке, не вложена в EXE.",
        "HTML-просмотр: ссылки и JavaScript проверены отдельно; настоящий браузерный рендер не проверен (Chromium отсутствует).",
        "Поиск: 25 проверок с подменой OS opener; реальный запуск браузера на Windows не проверен.",
        "Каталог движений — план производства; тесты директора проверяют код на искусственных тестовых ресурсах, не художественное качество анимации.",
    ]
    (reports / "VALIDATION.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0 if all(ok for _, ok in outcomes) else 1

if __name__ == "__main__":
    sys.exit(main())

