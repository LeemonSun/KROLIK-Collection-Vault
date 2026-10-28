# Leemon 0.12 — текущий checkpoint

Начать с `python3 tools/resume.py status` и recovery/session.json, затем docs/WORKFLOWS_012.md. GitHub LeemonSun/KROLIK-Collection-Vault/main — только хранилище; без Actions, remote builds или deployment. Без субагентов без прямого разрешения. Последний head — .resume-remote.json.

Единственный персонаж — Лимон. Не восстанавливать удалённые концепты. Неиспользуемые ресурсы/настройки/промпты/упоминания удалены; список путей и известных SHA в recovery/retired_paths.json. Bootstrap удаляет только совпадающие известные копии, локальные изменения сохраняет как конфликт. История Git и обязательные licenses/notices не переписываются.

0.12: очередь до3обычных сообщений, FIFO, одна активная inference, события прогресса без дополнительных LLM-запросов, отдельная очистка ожидания, stop/pause/error+revision. Окна/снимок/микрофон/tools/выбранный target в очередь не входят. UI показывает ожидание и прошедшие секунды.

Файлы: office_patch.gd наследует text_patch.gd. CSV/TSV строгий адресный edit; DOCX — уникальный текст в одном w:t; XLSX — существующая ячейка выбранного по порядку листа, запись как строка, книги с формулами отклоняются. Выбор файла пользователем<=1MiB; review+120s token+SHAbackup+temp/rename+posthash; restore после перезапуска. ZIP до256частей/8MiB expanded/2MiB part, без `.bin`/подписей/опасных путей. Python только в независимых dev-тестах, приложение использует встроенный Godot.

26 процедурных поз из одного мастера, не тысячи клипов. Видимые очередь/read-cell/прикреплённое подтверждение/прокрутка редактора/file-state жесты; settle после ходьбы,60FPSнакороткие переходы, ограниченный idle. RU/EN/zh-Hans.

Сохранены0.11 workflowдо4USER-AUTHORED шагов с отдельным подтверждением и verification, explicit facts1024/512KB, единый localworker/CPUclamp/RAMheadroom/idleunload. Не ослаблять target identity/capability/verbatim write/preflight gates. Invoke не доказывает бизнес-результат. Одноразовое UIA-чтение ephemeral, password/Edit/ComboBox/offscreen исключены. SteamCloud отсутствует.

0.8–0.11 AI/ совместимы. Обновление — закрыть Leemon, сохранить старые EXE/PCK, заменить оба файла вместе, сохранить AI/ и AppData. Исторические START_WINDOWS/APPLY_FIX не запускать. Новая сборка не включает повторно1.9GBмоделей. Точные новые artifact IDs/SHA — session; прежняя0.11 также там.

Проверки/ограничения — session и reports. Качество реальной2Bмодели в0.12 не переоценивалось; factual accuracy всё ещё ограничена. Windows EXE/UIA/DPI/file locks/native picker/mic/voice здесь не испытаны. Public release gate должен оставаться blocked.

Среда этого прохода: Godot /workspace/scratch/deec6c1ed852/devtools/Godot_v4.7.2-stable_linux.x86_64; Xvfb /workspace/scratch/758adf0ad683/work/runtime; templates /workspace/scratch/aeddae26cfed/windows-template/Companion.exe; preview-windows-v0.12.0. Эти пути не переносимы. При новой среде bootstrap в новую соседнюю папку, assets runtime; старые арты больше не нужны для verify. Веса/ключи/файлы пользователя/снимки никогда не в Git.

Дальше: реальнаяWindowsприёмка+железо; измеренная более сильная offlineмодель; расширение общих document/table/browser tools; bounded model-authored plans. Не объявлять текущие ограниченные операции полноценным Office/универсальным автономным помощником.
