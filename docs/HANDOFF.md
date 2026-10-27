# Продолжение 0.3

Прочитать AGENTS.md, PROJECT_STATE.md, README, docs/LOCAL_AI.md и characters/signal_01/README.md. Пиксели отложены, текущая героиня сохранена. GitHub — только хранение; нельзя Actions/CI/удалённую сборку.

В текущей версии есть native desktop-cutout/drag/red-transition, системная озвучка, ручной screenshot preview, managed local text worker и installer. Они ещё не испытаны на Windows. Готовые body clips = 0; каталог = 113 планируемых событий. Нельзя выдавать window FX за полноценную анимацию, текстовый Qwen за VLM или открытие поиска за чтение страниц.

Критично: сохранять offline-first, RU/EN/zh-Hans, лицензии/NOTICE, exact hashes и закрытый публичный gate. Вес модели не коммитить. Изображения/скриншоты пользователя не сохранять в репозиторий. Runtime скачивается только по явной кнопке; нет remote inference. Результат модели не управляет URL, shell или путями ресурсов.

Проверки tools/run_checks.py и отчёты. tests/test_local_runtime.gd без fixture проверяет unit; с COMPANION_RUNTIME_FIXTURE проверяет реальный локальный процесс на подготовленном разработчиком fixture. Артефакты сборки — локальный build_preview.py с проверенным шаблоном. Windows EXE можно проверить как main-pack на Linux, но это не запуск Windows executable. Перед передачей повторить релевантные проверки и сверить архив/хеши.

## 0.3.1

Прочитать docs/PRODUCT_DIRECTION.md. Старая схема 0.3.1: bootstrap с пустым host; она заменена в 0.3.2. Main Window Godot нельзя скрывать напрямую. Чат/настройки не должны возвращаться к старой большой боковой панели. ChatView использует runtime App lookup для предотвращения циклической preload зависимости; сохранять проверку 320×280 и длинного RU текста. Новые проверки: test_chat_layout.gd и test_desktop_visual.gd (нужен отдельный дисплей). Screenshot-артефакты теста внутренние, в git не включать.

Полный build создаёт EXE + отдельный PCK. make_patch.py делает одноразовый verified delta из точной 0.3. Патч корректирует старый launcher manifest, иначе тот откатит EXE. Новые downloads payloads/manifest должны соответствовать hash полного патча; не включать веса. Windows исполнение всё ещё требует пользовательской проверки.

## Актуально: 0.3.2

Главное окно = персонаж. DesktopCompanion — Node-контроллер root Window, не второе окно. Не выносить root за экран. Минимизация + taskbar/tray сохраняют доступ. Патч make_content_patch.py меняет только PCK, требует точный 0.3.1; полный ZIP работает отдельно. Launcher проверяет финальные EXE/PCK hashes и не применяет старый фикс повторно. Одна визуальная тема, без переключателей. Для X11 есть portable tools/test_native_ui.py.
