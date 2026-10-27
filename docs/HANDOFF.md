# Продолжение 0.3

Прочитать AGENTS.md, PROJECT_STATE.md, README, docs/LOCAL_AI.md и characters/signal_01/README.md. Пиксели отложены, текущая героиня сохранена. GitHub — только хранение; нельзя Actions/CI/удалённую сборку.

В текущей версии есть native desktop-cutout/drag/red-transition, системная озвучка, ручной screenshot preview, managed local text worker и installer. Они ещё не испытаны на Windows. Готовые body clips = 0; каталог = 113 планируемых событий. Нельзя выдавать window FX за полноценную анимацию, текстовый Qwen за VLM или открытие поиска за чтение страниц.

Критично: сохранять offline-first, RU/EN/zh-Hans, лицензии/NOTICE, exact hashes и закрытый публичный gate. Вес модели не коммитить. Изображения/скриншоты пользователя не сохранять в репозиторий. Runtime скачивается только по явной кнопке; нет remote inference. Результат модели не управляет URL, shell или путями ресурсов.

Проверки tools/run_checks.py и отчёты. tests/test_local_runtime.gd без fixture проверяет unit; с COMPANION_RUNTIME_FIXTURE проверяет реальный локальный процесс на подготовленном разработчиком fixture. Артефакты сборки — локальный build_preview.py с проверенным шаблоном. Windows EXE можно проверить как main-pack на Linux, но это не запуск Windows executable. Перед передачей повторить релевантные проверки и сверить архив/хеши.
