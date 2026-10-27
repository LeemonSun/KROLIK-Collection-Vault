# Быстрый вход: Leemon / Companion

GitHub: LeemonSun/KROLIK-Collection-Vault, main. Только хранилище; никакого Actions/CI/удалённой сборки.

Исходники: 0.5.0-leemon-preview. НЕ ВЫПУЩЕНО. Среда отключилась на финальной проверке. Последняя выданная версия — 0.4.0, Library ID libfile_b3abab6a0df08191ab4367c17a7080dc. Не выдавать её за лимона.

1. Если среда пуста/старая: получить актуальный tools/resume_bridge.js из GitHub, прочитать и вызвать bootstrap. Он восстановит капсулу и pending-overlay с проверкой Git SHA. Несовпавшие локальные правки не заменяются.
2. Overlay привязан к старому content_id капсулы; следующий обычный checkpoint автоматически отключит этот слой новым content_id. До этого source_changed после overlay ожидаем. Не накатывать старую капсулу поверх новых файлов вручную.
3. python3 tools/resume.py status, затем только файлы задачи. Runtime assets — Leemon master и Noto; девушка перенесена в reference. Веса не нужны для UI/командных проверок.
4. Финально проверить test_local_runtime.gd: старая проверка ожидала 8 потоков независимо от малоядерного хоста; теперь задан fixture 16 processors. Этот фикс после отключения не запускался.
5. Проверить последний exported PCK: ResourceLoader для импортированного PNG (FileAccess.exists сырого PNG внутри PCK неверен), короткий широкий layout, создание/отмена reminder из чата, перевод и очистку исходника.
6. Пересобрать ZIP и two-file update. Не публиковать 0.5 launcher до binary chunk/preview-manifest. Кандидат — packaging/START_WINDOWS_0.5.pending.cmd; скопировать в корневой START_WINDOWS.cmd перед make_preview_update, затем сохранить update и metadata.
7. Выдать native Library attachment. Sandbox ZIP у пользователя не открываются. Обновить session.json и checkpoint. Не оставлять большие незаписанные куски.

Реализовано: лимон, один графитово-жёлтый стиль, 6 shared-texture частей, 8 процедурных состояний; офлайн часы 597 зон/2039 aliases (IANA 2026e/CLDR + notices); сохраняемые reminders; explicit owned-local clipboard translation; adaptive AI threads для малоядерных CPU; EXE+PCK updater с SHA/backup/rollback.

Мастер: assets/characters/leemon_01/master_v1.png, 1199×1312. Не менять размеры без UV. Происхождение/промпт — characters/leemon_01. Мастер уже сохранён в GitHub. Leemon_Mascot.zip содержал concept sheet, не анимационные кадры.

До отключения: native 72 PASS, короткие переводы трёх языков, updater 8 сценариев, 144 render frames. Последние UI/CPU/source-retention изменения требуют финального прохода. Научная точность 1.7B слабая; не называть smoke гарантией интеллекта. Нет ASR/custom voice/3D/facial rig/VLM/page reading. Windows native не запускался.

Карта: src/animation/leemon_rig.gd; src/desktop/companion_window.gd; src/app.gd; src/tools/world_clock.gd; src/tools/clipboard_translation.gd; src/core/store.gd; src/ui/main.gd; tools/make_preview_update.py.
