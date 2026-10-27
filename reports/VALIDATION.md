# Проверки приложения

Дата: 27.10.2026. Linux x86_64, Godot 4.7.2 standard.

| Проверка | Результат |
| --- | --- |
| structure | PASS |
| core | PASS |
| http | PASS |
| local_runtime | PASS |
| search | PASS |
| persistence | PASS |
| leemon_tools | PASS |
| functional | PASS |
| animation | PASS |
| self_knowledge | PASS |
| chat_layout | PASS |
| ui | PASS |
| release_gate_expected_block | PASS |

release_gate_expected_block = PASS означает, что неподготовленная сборка правильно заблокирована.

Leemon 0.5: один мастер, шесть частей 2D-рига и восемь процедурных состояний. Это не рисованные клипы, 3D или facial rig.
Офлайн-часы, сохраняемые напоминания и явный перевод буфера проверяются в leemon_tools; тесты провайдера используют подмену и не доказывают качество нейросети.
Native X11 review, фактический Godot → PowerShell roundtrip и двухфайловое обновление проверяются отдельно: native_ui.txt, exported_content.txt, desktop_bridge.txt, preview_update.txt.
Настоящая Windows здесь не запускалась: EXE, прозрачность, перемещение, системный голос, установщик модели и блокировки файлов требуют отдельной приёмки.
Модель Qwen3-1.7B не заменена. Короткие переводы ранее проверены на настоящем CPU worker; научная точность ограничена. Веса загружаются отдельно, не входят в ZIP.
ASR, собственный голос, понимание экрана и самостоятельное чтение веб-страниц пока отсутствуют. Каталог движений — план производства, а не готовые анимации.
