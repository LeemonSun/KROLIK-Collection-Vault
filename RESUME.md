# Leemon 0.13 — сохранено и выдано

Начать с `python3 tools/resume.py status`, recovery/session.json и docs/WORKFLOWS_013.md. Выбор инструментов/лицензий: docs/TECH_STACK_013.md. Не перечитывать весь чат и не перезапускать фундамент. GitHub LeemonSun/KROLIK-Collection-Vault/main — только хранилище, без Actions/remote builds/deployment. Без субагентов без прямого разрешения. Текущий head — .resume-remote.json.

Единственный персонаж — Лимон. Retired concepts не восстанавливать; retirement guards и обязательные notices сохранять. Основа прохода 0.12: 5523ff1085818bdf3a9cfbf9e74bdd19e23ad834. Промежуточное сохранение 0.13: f47afc5d1b9f467587409ad8a78491f15a4edf27.

## Реализация

- profile.effective и App.runtime_options: default quiet (1 thread / batch32 / idle30), standard — прежний профиль. Все owned text/vision starts получают effective budget, ASR получает thread cap. Переключение отменяет задачу/очередь и останавливает worker. Не строгая CPU/RSS квота.
- docx_text.gd: единственный literal span в одном обычном абзаце через соседние styled runs. Новый текст получает первый affected run style. Неподдерживаемые fields/bookmarks/hyperlinks/hidden runs/paragraph boundaries/protection отклоняются.
- office_patch.gd: существующие ячейки XLSX — текст, число (до 15 значащих цифр), Boolean (true/false). Книги с формулами запрещены. inspect_range до 1024 ячеек: одно чтение пакета, приблизительная double-статистика без LLM/записи. Форматы дат/процентов не интерпретируются.
- file_edit_window.gd: закреплённый preview/result вне центральной прокрутки; range controls/type picker, RU/EN/zh. Preview/backup/fresh SHA/posthash/restore сохранены.
- run_checks создаёт отдельный временный профиль для каждой группы: устраняет перенос сохранённого языка и fixtures между проверками.

Сохранены queue3 ordinary messages, explicit facts 1024/512KB, selected-window UIA и чтение с выдержками, workflow до 4 user-authored steps, один heavy worker, lazy load и idle unload. Не ослаблять target identity/capability/verbatim write/preflight/approval gates. Invoke не доказывает бизнес-результат. Сайт/документ не может выдать себе разрешение на действие.

## Проверки и артефакты

26 source groups PASS. Финальный PCK: 9 composition + 44 technical + 33 real Office/independent python-docx/openpyxl readback + 156 general native + 34 technical native X11 checks; ZIP CRC PASS. Windows EXE/UIA/DPI/file locks/native picker/mic/TTS здесь не выполнялись. Реальная производительность и качество текущей 2B-модели не переизмерялись. Нет новых весов, runtime, pruning или обучения. TECH_STACK_013 — кандидаты, не установленный стек.

ZIP 0.13 и отчёт сохранены, IDs/SHA в session и README. AI/ и AppData сохранять; модели 0.8–0.12 совместимы. Для обновления заменять EXE и PCK вместе. Полный offline-пакет повторно не нужен. Steam Cloud отсутствует; нужен собственный AppID. Не обещать все ПК, абсолютную безопасность, полноценный Office/браузер, тысячи клипов или Steam 1.0.

## Среда и следующий шаг

Рабочая папка этого прохода: /workspace/scratch/deec6c1ed852/leemon-013. Старая companion-foundation может содержать 0.1! Godot: /workspace/scratch/deec6c1ed852/devtools/Godot_v4.7.2-stable_linux.x86_64. Xvfb: /workspace/scratch/758adf0ad683/work/runtime. Verified template: /workspace/scratch/aeddae26cfed/windows-template/Companion.exe SHA49bdb7a55e668a3a5e8f88f374ac502b84454d23bde9561bf3b9d8e38bab2538. Final package: preview-windows-v0.13.0. Эти пути непереносимы.

При сбросе: свежий tools/resume_bridge.js из GitHub, bootstrap в новую соседнюю папку, assets runtime. Не скачивать веса ради обычного патча. Следующий этап: настоящая Windows-приёмка и hardware measurements; общие browser/document tools, source evidence и bounded model-authored planning; сравнение лёгких моделей RU/EN/zh перед сменой. Художественный редизайн позже. Перед паузой обновить session и checkpoint.
