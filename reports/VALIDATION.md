# Проверки фундамента

Дата: 27.10.2026. Linux x86_64, Godot 4.7.2 standard.

| Проверка | Результат |
| --- | --- |
| structure | PASS |
| core | PASS |
| http | PASS |
| local_runtime | PASS |
| search | PASS |
| persistence | PASS |
| functional | PASS |
| animation | PASS |
| self_knowledge | PASS |
| chat_layout | PASS |
| ui | PASS |
| release_gate_expected_block | PASS |

release_gate_expected_block = PASS означает, что неподготовленная сборка правильно заблокирована.

Не проверены на настоящей Windows: запуск EXE, native-прозрачность/перетаскивание, установщик модели, озвучка/снимок и китайские глифы. Общий визуальный интеллект и чтение страниц ещё не подключены. Исполнитель запуска приложений/папок проверяется отдельно; нативная Windows-приёмка ожидается.
UI smoke проходит страницы/языки без дисплея; ChatView отдельно проверяется на 4 размерах и 3 языках. Native X11 review и применение патча — отдельные reports/native_ui.txt и reports/patch_application.txt; это не Windows приёмка.
Включены рабочий концепт и прозрачный runtime-cutout Signal 01. Есть native-window прототип, перетаскивание и красный переход; настоящего рига/клипов нет. Текстовая модель скачивается явно по кнопке, не вложена в EXE.
HTML-просмотр: ссылки и JavaScript проверены отдельно; настоящий браузерный рендер не проверен (Chromium отсутствует).
Поиск: 25 проверок с подменой OS opener; реальный запуск браузера на Windows не проверен.
Каталог движений — план производства; тесты директора проверяют код на искусственных тестовых ресурсах, не художественное качество анимации.

## Итог 0.4.0

- Functional: 42 PASS. Обычные команды RU/EN/中文, guard ложных действий, память/retrieval/удаление, exact-hash migration с сохранением unknown файлов и active PCK.
- Реальный перезапуск двух независимых процессов: opt-in история восстановлена и удалена, изолированный синтетический профиль.
- HTTP: 27 PASS + context 8 PASS. Авторизованные /apply-template и /tokenize, полные пары истории удаляются до generation, overflow не доходит до генерации, cancel без позднего ответа.
- PowerShell 7.6/Linux: 21 PASS. Actual JSON/nonce protocol, resolver и реальная память/CPU процесса. Windows COM/Shell window detection не исполнялись.
- Экспортированный PCK: 50 native X11/llvmpipe PASS; 8 PASS на наличие exact helper/manifest и настоящую связку Godot→PowerShell→JSON→Godot. Запросы/результаты убраны, BOM присутствует для Windows PowerShell 5.1.
- Shader motion=0 даёт побайтово одинаковый RGBA с отключённым материалом. Это проверяет tint, не художественное качество движений.
- Реальная delta 0.3.3→0.4.0: 4 сценария PASS (точный PCK, backup/profile, повтор, unknown base и corrupt reconstruction). Полная историческая цепочка source-bootstrap в этом проходе не повторялась: предыдущие packages сохранены, добавлен завершающий шаг.
- Полный чистый ZIP: 13 файлов, без внешних BAT/CMD/PS1. Профиль и установленная модель сохраняются в прежнем AppData.

Настоящая Windows и реальный Qwen dialogue regression в этом проходе НЕ проверены. Веса прежние; смена system prompt не является обучением модели. Нет новых body clips, custom voice, ASR, VLM или чтения страниц. CPU/RAM в тестовой Linux software-render среде нельзя переносить как требования Windows. Предупреждения X11 о VSync/speechd и принудительно вызванном missing-art fallback изучены; script/runtime errors отсутствуют.
