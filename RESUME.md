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
