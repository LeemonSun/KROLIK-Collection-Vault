# Сейчас: 0.6 WIP, исходники сохранены

Последний выданный ZIP — 0.5. Текущая работа по обратной связи пользователя: белый сломанный чат, мигание курсора, Alt-Tab, фон/обрезка текстуры, нагрузка, ложное «создан файл», цикл «нормально, как у тебя». Код нового большого прохода уже на месте, но 0.6 ещё не выдан.

Сначала python3 tools/resume.py status и recovery/session.json (pending_060). Не восстанавливать весь проект заново. Веса для UI не скачивать. GitHub только хранилище.

Закончить: новые native assertions для стабильной маски/прямого чата/анимации входа/трёх новых состояний; bounded repeat retry для ответов; контроль parse/runtime ошибок; сборка и проверка exported PCK; delta от 0.5 и native Library ZIP/GIF. Версию и launcher НЕ объявлять выданными до binary/attachment. Старый source starter пока 0.5 намеренно.

Новые файлы: src/tools/text_documents.gd, tests/test_desktop060.gd (27 PASS). Изменены chat_window/chat_view/bootstrap, companion_window/leemon_rig, app, self_knowledge/response_guard/desktop_intent, local_runtime, desktop_actions, native/desktop_bridge.ps1, profiles/locales. 13 прежних групп PASS. Native source76 PASS до последнего добавления11states. Native Windows/API здесь не исполнялись. Модель Qwen3-1.7B та же: не обещать решение интеллекта промптом.

## Справка предыдущей выданной 0.5

# Быстрый вход: Leemon / Companion 0.5

GitHub LeemonSun/KROLIK-Collection-Vault main — только хранилище, никаких Actions/CI/удалённых сборок.

**0.5.0-leemon-preview собран и выдан.** Full ZIP: libfile_aa492c7431c88191a105c25f22539735, 53434851 байт. GIF фактического рига: libfile_16144d9ee04c81919c334a2752d09a1c. Не выдавать прежнюю 0.4 за лимона. Факты/хеши — recovery/session.json; отчёт — reports/WORK_REPORT_0.5.md.

1. Запустить python3 tools/resume.py status. Если среда пуста — получить свежий tools/resume_bridge.js из GitHub, прочитать, вызвать bootstrap. Капсула/хеши восстанавливают код, неизвестные локальные правки сохраняются.
2. Для UI нужны только runtime assets: Leemon master и Noto; для всех structural tests — также архивные reference assets. bridge assets group runtime/test. Веса для UI не скачивать.
3. Прежний pending-overlay привязан к старому content_id и после нового checkpoint неактивен. Не накатывать старую капсулу поверх новой вручную.
4. Работать локально; новую задачу делать по карте ниже. Не тратить время на всю переписку/архивные отчёты. Сохранять большие куски checkpoint.
5. Для выдачи ZIP использовать native Library attachment: sandbox ZIP у пользователя не скачивался. Корневой START_WINDOWS.cmd и downloads manifest уже 0.5, binary update сохранён вместе. packaging/START_WINDOWS_0.5.pending.cmd — прежний кандидат, теперь идентичен корневому.

Текущая база: один графитово-янтарный стиль; лимон Leemon, очки/костюм/лист; shared master1199×1312, шесть частей рига, восемь процедурных состояний. Source/provenance — characters/leemon_01; texture — assets/characters/leemon_01/master_v1.png, не менять размеры без UV. Старую Signal сохранить как reference, не экспортировать.

Добавлены часы597зон/2039aliases, напоминания32/31день с сохранением/отменой, explicit clipboard translation only owned local worker с очисткой исходника; threads half logical CPU min1/max8. EXE+PCK updater проверяет оба до замены, backup и rollback; около1.3MB. Модель/профильAppData прежние.

Последняя проверка: 13 групп PASS; Leemon tools47; exported X11 UI76; exported content/actual PS roundtrip11; executor21; updater8сценариев. Native UI test теперь запускает PCK из его папки, без подмешивания исходников. Логи current: VALIDATION.md, native_ui.txt, exported_content.txt, desktop_bridge.txt, preview_update.txt. work_in_progress.txt и старые leemon_import/smoke — исторические сбои, не текущий результат.

Windows native не запускался: ждать обратной связи пользователя. Qwen3-1.7B прежний, короткие переводы проверялись на CPU, общая научная точность слабая. Не обещать исправление интеллекта системным промптом. Нет ASR/custom voice/VLM/page reader/Cloud; не тысячи художественных клипов. Модель1.86GB всё ещё отдельная установка. Public Steam release gate закрыт.

Карта: src/animation/leemon_rig.gd; src/desktop/companion_window.gd; src/app.gd; src/tools/world_clock.gd и clipboard_translation.gd; src/core/store.gd и desktop_intent.gd; src/ui/main.gd и chat_view.gd; tools/make_preview_update.py и test_preview_update.py.

Следующий проход: сначала фактические Windows ошибки; затем качество разговора/действий и художественное качество движения, не новые десятки пустых меню. Минимальные требования/выигрыш FPS ещё не измерены на слабом ПК.
