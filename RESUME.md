# Leemon 0.10 — сохранено и выдано

Начать с `python3 tools/resume.py status` и recovery/session.json. Следом docs/WINDOW_READING.md; для действий — docs/GOAL_PROPOSALS.md. Не перечитывать весь чат и не собирать фундамент заново. GitHub LeemonSun/KROLIK-Collection-Vault/main — только хранилище, без Actions/remote builds. Субагенты не разрешены без прямого запроса.

Текущая сборка: 0.10. ZIP и отчёт сохранены, точные IDs/SHA в session.json, ссылки в README. Модели прежние 0.8/0.9, AI/ сохранять. START_WINDOWS.cmd исторический, не выдавать его как установщик.

Новый модуль: явное чтение выбранного окна → ограниченный UIA текст → существующая 2B модель → JSON answer/sources/insufficient → ответ и дословные выдержки. Без автопилота/фонового браузера. Пароли/поля Edit/ComboBox/offscreen и их поддеревья исключены, TextPattern только у листов. Максимум240узлов,48фрагментов,8KB; модель получает18фрагментов/2400байт. Вопрос и ответ ephemeral: исключены из истории и model turns. Raw text удаляется из receipt и HTTP при всех исходах; IPC очищается и после crash. Любая смена target/отмена/пауза чистит контекст. Не утверждать, что проверка sourceID доказывает истинность ответа.

Код: src/core/window_reader.gd, App.window_read_*, ApplicationAccess.read_content/read_ready, native/accessibility_bridge.ps1. Чат: кнопка листа с лупой и reveal_latest к началу ответа. tests/test_window_reader.gd:42unit; optional COMPANION_READ_FIXTURE:5реальныхmodelкейсов. Последний реальныйлог58checks — до добавления одного unitcase, это не58программ.

0.9 действия сохранены: одно предложение, согласие пользователя15сек, свежая проверка HWND/PID/start/title/runtimeID/name/capability; select/expand проверяются после эффекта. Invoke только по явной просьбе и буквальному имени кнопки; ввод только verbatim из goal. Не ослаблять после случая модели Delete на шутку. Обычная беседа не имеет liveконтекста окна.

0.8 база сохранена: один Лимон210×232,6частей одного мастера,16процедурных состояний,один графит/янтарь. Qwen3.5-2BQ4 общий текст/разовое зрение, paired projector по запросу, один тяжёлый worker,ограниченные CPUпотоки,lazyload/idleunload. Whisper20сек в черновик,TXT/DOCXновыми файлами,заметки/таймеры/мировые часы.

Итоговые проверки:20sourcegroups,42readerunit,5realmodelcases,140layout,105nativeX11из итоговогоPCK,15exportedcontent+реальный helperIPC,16accesshelper,11syntheticreadtree. Windows/UIA/mic/voice/EXE на реальном ПК НЕ проверены. Real read generation2.7–5.5с CPU2threads не включает startup/WindowsUIA; planner0.9по-прежнему17–28с в старом fixture.

Локальные зависимости внеGit: devtools/Godot_v4.7.2-stable_linux.x86_64,devtools/pwsh/pwsh,devtools/xvfb,devtools/llama11901/llama-b11901;read-fixture/model.gguf иfixture.json/installed.json;recovered-09/Companion_Preview/Companion.exe (template);preview-windows-v0.10.0. Сборка tools/build_preview.py; принят0.9и0.10templateSHA. Не коммитить веса/ключи/пользовательские снимки.

При откатеworkspace к0.1: скачать tools/resume_bridge.js из GitHubmain; bootstrap в НОВУЮ соседнюю папку, assets runtime, test-ассеты только по необходимости; сохранить старую папку и заменить canonical. Резерв0.1этого прохода: companion-foundation-stale-01. Не восстанавливать все гигабайтные offlineparts:0.10лёгкий ZIP достаточен для template.0.8bundle4parts остаётся вLibrary спровереннымиSHA(session).

Дальше: настоящая Windows-приёмка, больше неизвестных/враждебных окон,семантическая точность и latency; затем ограниченные последовательности с проверкой каждого шага. Собственный голос/SteamCloud/тысячи клипов/Steam1.0/гарантия прав не готовы. Не делать новый модельныйзоопарк и не обещать любыеПК.
