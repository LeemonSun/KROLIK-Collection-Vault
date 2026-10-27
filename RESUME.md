# Сейчас: ночной проход после восстановления 0.6

Сразу читать recovery/NIGHT_PASS.md и recovery/session.json. Не читать весь чат и не восстанавливать код заново. Точная 0.6 найдена в Library: libfile_29cda571ac3c8191be6b25d254b7838c, full ZIP53MB, SHA в session. Source fixes возвращены после63d; новый checkpoint сохраняет их вместе с shard capsule schema2. Source distribution starter пока0.5 намеренно, будет обновлён атомарно с бинарным update; для запуска использовать готовый native ZIP.

GitHub LeemonSun/KROLIK-Collection-Vault main только хранилище, никаких Actions/CI. Код/ассеты внутри companion-foundation; downloaded weights/runtime только вне репозитория ai-fixtures. Окружение local transient может откатываться; новая капсула частями снимает600KB потолок. tools/resume_bridge.js bootstrap/checkpoint, assets runtime/test. Не терять неизвестные правки, проверять SHA.

Пользователь спит и разрешил большой проход несколькими закончеными блоками: исправления, голос, экран, общие действия внутри приложений, меньший лимон, consumer UI, реальные оптимизации. Не выдавать фикстуры за Windows проверку и не обещать готовый Steam1.0. После завершённого блока checkpoint и продолжать. Не запускать субагентов, прямого разрешения нет.

Текущая работа: baseline0.6 восстановлен. Кандидаты Qwen3.5-2B-Q4 и F16 mmproj + whisper-base-q5_1, downloads metadata/logs внеGit model-research. Скрипты bench_qwen35.py и download_night_models.py внеGit; параметры/хеши в NIGHT_PASS. Нужно дождаться bench/readactual replies до выбора модели. Старый Qwen3-1.7B пока не менять вслепую. Native Windows не доступен. ASR реализован и проверен реальным аудио; VLM пока только исследование и fixture, в приложение не подключён.

Карта: src/app.gd; src/runtime/local_runtime.gd; src/providers/llama_http_provider.gd; src/desktop/{companion_window,chat_window}.gd; src/ui/{main,chat_view}.gd; src/animation/leemon_rig.gd; native/desktop_bridge.ps1; core/{desktop_intent,response_guard,response_quality,self_knowledge}.gd. 11 procedural motion states,6parts, одна текстура. Публичный release gate закрыт.
