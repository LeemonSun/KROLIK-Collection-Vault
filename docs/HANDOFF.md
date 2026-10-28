# Продолжение Leemon 0.13

Читайте RESUME.md, recovery/session.json, WORKFLOWS_013.md и TECH_STACK_013.md. Исходная 0.12 сохранена в истории; фундамент не перезапускать. Только Лимон. GitHub — хранилище, не CI. Модели и данные пользователя не коммитить.

Основные изменения: core/profile.gd effective; App.runtime_options/set_resource_mode; runtime/local_runtime.gd batch budget; whisper_transcriber thread cap; tools/docx_text.gd; office_patch.gd typed values/range summaries; ui/file_edit_window.gd pinned preview/range controls/type picker.

Проверки: technical013, technical_visual013, Office с независимым Python-чтением, run_checks с отдельными временными профилями. Итоги, ограничения и артефакты — в session. Python нужен только для разработки, не пользователю.
