# Leemon 0.14 — сохранено и выдано

Начать с `python3 tools/resume.py status`, recovery/session.json и docs/WORKFLOWS_014.md. Копилка — research/component_backlog.json (21 запись) и TECH_STACK_013.md. GitHub LeemonSun/KROLIK-Collection-Vault/main только хранилище, без Actions/CI/remote builds/deployment. Без субагентов без прямого разрешения. Текущий head — .resume-remote.json.

## Главное решение пользователя

Общий адаптивный агент — главный следующий этап, а не бесконечное добавление ручных команд. Контур: наблюдать UIA/экран → понять свободную цель → ограниченный план → shared tools в существующих приложениях → повторное наблюдение/проверка → адаптация либо остановка. Не обучать отдельную модель под каждую программу/версию и не создавать свою замену Office/виртуальную пользовательскую среду. Адаптация через контекст, наблюдение и память о проверенных успешных способах; постоянное обучение весов не реализовано. Сайты/файлы не назначают себе права. Текущие authority/preflight/verification gates сохранять; не ослаблять их вслепую ради автономности.

0.14 — инструменты этого контура, не готовый универсальный агент. CPU/память/ошибки неизвестного интерфейса нужно измерять, не обещать любой ПК/любую задачу/абсолютную безопасность.

## Что сделано

- calculator.gd: собственная ограниченная грамматика, не eval; +−*/^%, скобки, sqrt/abs/sin/cos/ln/log10, pi/e, пределы/ошибки. Double приблизительный, не CAS/финансовая точность. sin/cos радианы; % = /100.
- unit_converter.gd: явные единицы/размерности, affine temperatures, MBvsMiB, нет валютных курсов.
- windows_settings.gd: fixed ms-settings URI handoff. Не меняет значения и не проверяет появление окна; Windows acceptance pending.
- public_page.gd: explicit public HTTPS, async DNS, всеIP проверяются, выбранныйIP фиксируется, TLSOptions.client проверяет исходный hostname. GET, без browser cookies/auth/JS/forms/redirects. UTF8 HTML/plain identity, Content-Length/chunked, body<=256KiB/20s,12×300 excerpt cap. URL/текст ephemeral, без сохранения в model turns и без права выполнять команды. Публичные DNS/live websites здесь не проверены успешно; локальный realTLS fixture работает. Conservative special IP checks, IPv4 preferred. Proxy support не заявлен.
- Router/ToolPolicy/App + native chat statuses/stop. Новые tools не входят в chat queue, не запускают inference. Явный follow после синхронного reply +3-frame settle исправляет скрытый последний ответ. Не повторять технические подсказки в каждом простом ответе.

Сохранены0.13: profile.effective quiet(1thread/batch32/idle30) с ASRcap; DOCX across plain styled runs; typed existing XLSX; approximate range summaries<=1024; pinned review/backup/restore. 0.12 queue3ordinary; facts1024/512KB;4user-authored-step workflow; selected-window UIA/read; one heavy worker, lazyload/idleunload. Формулы/новые ячейки/полный Office и universal planning пока отсутствуют. Только Лимон, один стиль,26процедурных состояний, не тысячи клипов. Retired assets не восстанавливать, notices сохранять.

## Проверки и доставка

29 source groups PASS в отдельных временных профилях. ФинальныйPCK:9composition+112utilities+16fakeHTTPpolling+7realLocalTLS/independentPythonrequests+33Office/independentreadback+156generalNative+34OfficeNative+25utilitiesNative checks PASS. ZIPCRC PASS. Linux/X11,неWindows. Actual public DNS failed вGodot иPython; не заявлять успешное чтение реального сайта. Windows UIA/DPI/filelocks/nativepicker/mic/TTS, real2Bquality/throughput/resource benchmark ещё нужны. TLS fixture adapter только вtests; временные keys не сохранены и не входят в export.

ZIP0.14/report сохранены, IDs/SHA вsession/README. Report version1 учитывает уточнение про общего агента. AI/ иAppData сохранять,0.8–0.13модели совместимы; EXE/PCK заменять вместе. Новые веса/runtime не добавлены; нет pruning/fine-tuning. Полныйoffline1.9GB повторно не нужен. SteamCloud отсутствует, ownAppID нужен.

## Среда и продолжение

Рабочая папка: /workspace/scratch/deec6c1ed852/leemon-013 (имя папки историческое; версия0.14). Старая companion-foundation может быть0.1! Godot: /workspace/scratch/deec6c1ed852/devtools/Godot_v4.7.2-stable_linux.x86_64. Xvfb: /workspace/scratch/deec6c1ed852/devtools/xvfb014 (локально восстановлен из подписанного Ubuntu noble apt, без system install). Template: /workspace/scratch/aeddae26cfed/windows-template/Companion.exe SHA49bdb7a55e668a3a5e8f88f374ac502b84454d23bde9561bf3b9d8e38bab2538. Final output: preview-windows-v0.14.0; EXESHA55166cfe1374c1e8bd24741f56e5116d40b0ba8a72f0c27926431ba886fbb08c добавлен в build_preview allowlist. Пути непереносимы.

При сбросе: свежий tools/resume_bridge.js изGitHub → bootstrap в новую соседнюю папку → assets runtime. Не скачивать модели ради кода/экспорта; достаточно текущего lightZIP дляtemplate. Главный следующий проход — общий агент с bounded model-authored planning и наблюдением после каждого шага, используя имеющуюсяUIA/vision/tool основу. Параллельно Windows/live web/hardware acceptance. Художественныйредизайн позже. Перед паузой session+checkpoint.
