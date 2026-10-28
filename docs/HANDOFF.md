# Продолжение Leemon 0.12

Читайте RESUME.md, recovery/session.json и docs/WORKFLOWS_012.md. Одна тяжёлая задача, один персонаж — Лимон. GitHub только хранит checkpoint. История/обязательные licenses не изменяются. Удалённые пути защищены retirement-манифестом; не возвращать прежние концепты.

Ключевые файлы: src/app.gd, core/chat_queue.gd, tools/{text_patch,delimited_table,office_patch}.gd, ui/{file_edit_window,chat_view,leemon_surface}.gd, desktop/{companion_window,companion_behavior}.gd. Проверки: tools/run_checks.py; tests/test_queue_table.gd; tools/test_office.py; tools/test_native_ui.py. Source capsule/checkpoint — tools/resume_bridge.js. При новой среде source bootstrap, только нужные runtimeassets. Models не коммитить.
