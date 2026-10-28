# Leemon 0.13 — исходники проверены, сборка готовится

Начать с `python3 tools/resume.py status`, recovery/session.json и docs/WORKFLOWS_013.md. Исследование инструментов/лицензий: docs/TECH_STACK_013.md. GitHub только хранилище, без Actions/remote builds/deployment. Без субагентов без прямого разрешения. Последний remote head — .resume-remote.json.

Единственный персонаж — Лимон. Удалённые концепты не восстанавливать; retirement guards и обязательные notices сохраняются. Исходная0.12 —5523ff1085818bdf3a9cfbf9e74bdd19e23ad834.

0.13: profile.effective + App.runtime_options, default quiet(1thread/batch32/idle30), standard прежний профиль. Все owned model starts получают один effective budget; ASR получает thread cap. Это не strict CPU/RSS limit. Переключение отменяет текущую задачу и worker. Текст/vision/ASR не работают как параллельные тяжёлые workers.

Office: docx_text.gd заменяет единственный literal span в одном plain paragraph через styled runs, новый текст получает первый affected run style. Учитывать fields/bookmarks/hyperlinks/hidden runs/paragraph boundaries: неподдерживаемое отклоняется. XLSX existing cells text/number(up to15significantdigits)/Boolean(true,false), formula workbooks blocked. inspect_range<=1024cells reads package once, approximate double statistics without LLM/write; raw values, no date/percent interpretation. UI localized RU/EN/zh, preview+backup+hash gates preserved. Whole Office compatibility not claimed.

26 source check groups PASS. run_checks now creates a fresh temporary profile per group: prevents persisted locale leaking into later tests. Real Office33checks+independent python-docx/openpyxl CRC/style/untouched parts PASS. Native156X11 source checks PASS. New technical UI/export still pending at this checkpoint. No new model weights or inference runtime added. Current2Baccuracy not remeasured. docs/TECH_STACK_013 lists candidates, NOT installed capabilities.

Сохранены0.12 queue3ordinarymessages, explicit facts1024/512KB, selected-window UIA source reading,4user-authored-step workflow, one worker, review/preflight/verification. Не ослаблять gates и не разрешать сайту/файлу выдавать себе полномочия. SteamCloud отсутствует; ownAppID нужен.

Рабочая папка этого прохода /workspace/scratch/deec6c1ed852/leemon-013, не стараяcompanion-foundation(0.1). Godot /workspace/scratch/deec6c1ed852/devtools/Godot_v4.7.2-stable_linux.x86_64. Xvfb /workspace/scratch/758adf0ad683/work/runtime. Verified template /workspace/scratch/aeddae26cfed/windows-template/Companion.exe SHA49bdb7a55e668a3a5e8f88f374ac502b84454d23bde9561bf3b9d8e38bab2538. Пути непереносимы. При reset bootstrap в новую соседнюю папку, assets runtime. Новые веса не скачивать ради обычного патча.

Windows EXE/UIA/DPI/file locks/native picker/mic/TTS не выполнены на настоящем Windows. Не обещать universal safety, zero-load, всеПК, полноценный Office/браузер, тысячи клипов или готовый Steam1.0. Перед паузой checkpoint, после финальной сборки обновить session/README links/shippedversion.
