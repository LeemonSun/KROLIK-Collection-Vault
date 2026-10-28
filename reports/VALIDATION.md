# Проверки приложения

Дата: 28.10.2026. Linux x86_64, Godot 4.7.2 standard.

| Проверка | Результат |
| --- | --- |
| locomotion018 | PASS |
| diagnostics017 | PASS |
| capability017 | PASS |
| composer017 | PASS |
| reasoning016 | PASS |
| draft016 | PASS |
| adaptive015 | PASS |
| copy_knowledge015 | PASS |
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
| queue_table | PASS |
| utilities014 | PASS |
| public_tls014 | PASS |
| public_transport014 | PASS |
| technical013 | PASS |
| office | PASS |
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

Leemon 0.18: один мастер, шесть частей 2D-рига и26процедурных состояний. Это не рисованные клипы, 3D или facial rig.
Офлайн-часы, сохраняемые напоминания и явный перевод буфера проверяются в leemon_tools; тесты провайдера используют подмену и не доказывают качество нейросети.
Native X11 review, фактический Godot → PowerShell roundtrip и двухфайловое обновление проверяются отдельно: native_ui.txt, exported_content.txt, desktop_bridge.txt, preview_update.txt.
Настоящая Windows здесь не запускалась: EXE, прозрачность, перемещение, системный голос, установщик модели и блокировки файлов требуют отдельной приёмки.
Qwen3.5-2B Q4: прежние text/vision fixtures проверены отдельно; узкий adaptive/draft pilot выполнен, его ошибки и ограничения см. WORKFLOWS_017.md; научная точность ограничена. Полный offline-пакет использует AI/ рядом с EXE, лёгкий пакет предлагает явную установку.
ASR реализован через локальный Whisper. Разовый анализ экрана реализован; real fixture в vision_real.txt. Общие Windows UIA-действия и явное чтение доступного текста выбранного окна с выдержками реализованы, но Windows приёмка впереди. Собственный голос отсутствует; explicit public HTTPS excerpts reader имеет ограничения, см. WORKFLOWS_014.md. Каталог движений — план производства, а не готовые клипы.


Дополнение0.18: после основного37group прогона уточнено сохранение позы при envelope и
остановка входа из-за края в reduced motion. Релевантные проверки повторены:76motion/rig,
финальныйPCK smoke+76motion+32composer+12diagnostics+25adaptive+45copy PASS.
Финальный PCK вX11:35behavior+156general PASS; ZIPCRC PASS. Windows не запускалась.
Нагрузка/FPS не измерялись, общий интеллект модели этим проходом не изменён.
