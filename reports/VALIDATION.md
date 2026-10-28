# Проверки приложения

Дата: 28.10.2026. Linux x86_64, Godot 4.7.2 standard.

| Проверка | Результат |
| --- | --- |
| structure | PASS |
| core | PASS |
| http | PASS |
| local_runtime | PASS |
| search | PASS |
| persistence | PASS |
| vision | PASS |
| bundle | PASS |
| window_reader | PASS |
| file_memory | PASS |
| workflow | PASS |
| action_proposal | PASS |
| access | PASS |
| voice | PASS |
| desktop060 | PASS |
| leemon_tools | PASS |
| functional | PASS |
| behavior | PASS |
| animation | PASS |
| self_knowledge | PASS |
| chat_layout | PASS |
| ui | PASS |
| release_gate_expected_block | PASS |

release_gate_expected_block = PASS означает, что неподготовленная сборка правильно заблокирована.

Leemon 0.11: один мастер, шесть частей 2D-рига и26процедурных состояний. Это не рисованные клипы, 3D или facial rig.
Офлайн-часы, сохраняемые напоминания и явный перевод буфера проверяются в leemon_tools; тесты провайдера используют подмену и не доказывают качество нейросети.
Native X11 review, фактический Godot → PowerShell roundtrip и двухфайловое обновление проверяются отдельно: native_ui.txt, exported_content.txt, desktop_bridge.txt, preview_update.txt.
Настоящая Windows здесь не запускалась: EXE, прозрачность, перемещение, системный голос, установщик модели и блокировки файлов требуют отдельной приёмки.
Qwen3.5-2B Q4 заменяет старую модель. Реальные text/vision fixtures проверены отдельно; научная точность ограничена. Полный offline-пакет использует AI/ рядом с EXE, лёгкий пакет предлагает явную установку.
ASR реализован через локальный Whisper. Разовый анализ экрана реализован; real fixture в vision_real.txt. Общие Windows UIA-действия и явное чтение доступного текста выбранного окна с выдержками реализованы, но Windows приёмка впереди. Собственный голос и самостоятельное чтение веб-страниц отсутствуют. Каталог движений — план производства, а не готовые клипы.

Final0.11:23source groups PASS;31workflow,61behavior,29file/memory,140layout,143nativepack,18exportedhelper twice,27conversation checks PASS. Real factual accuracy remains limited; see docs/WORKFLOWS_011.md. SteamCloud not connected.
