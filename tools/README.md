# Локальные инструменты

Python 3.10+ нужен разработчику для валидации/упаковки, не пользователю будущего EXE.
verify_project.py — структурные проверки.
test_http.py — свой локальный HTTP fixture и интеграционные тесты Godot.
release_gate.py — намеренный запрет неподготовленного публичного выпуска.
package_source.py — воспроизводимый архив исходников и SHA-256.
run_checks.py — локальная последовательность проверок и отчёт.

Проверки и упаковка работают локально. GitHub Actions не использовать.

`resume.py status` — короткая сводка; `snapshot` — компактная капсула исходников; `plan --group code` — без ресурсов.
`resume_bridge.js` — явно вызываемое восстановление/сохранение через GitHub connector. Только `assets` скачивает выбранные ресурсы; веса моделей не входят в recovery. Читать RESUME.md.
Проверки recovery: `python3 -m unittest discover -s tests -p test_resume.py` и `node tests/test_resume_bridge.cjs` после snapshot.

