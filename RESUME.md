# Быстрый вход: Companion

GitHub: `LeemonSun/KROLIK-Collection-Vault`, main, только хранилище. Работа/сборка/проверки локально.

1. `python3 tools/resume.py status` — читать конкретные файлы задачи, не весь архив.
2. Если среда сбросилась, получить `tools/resume_bridge.js` через GitHub, прочитать, выполнить `companionResume({action:"bootstrap"})`. Восстанавливает проверенную капсулу кода; ассеты загружать только по необходимости.
3. Перед паузой обновить `recovery/session.json` и вызвать bridge `checkpoint`. Не оставлять большие незаписанные куски. GitHub не используется для Actions/CI/сборки.

Текущее: **0.4.0-functional-preview**, исполнитель обычных команд запуска приложения/папки в Windows (`native/desktop_bridge.ps1`), проверка результата отдельно от LLM. Естественные команды RU/EN/zh-Hans, opt-in история 100 сообщений/256 КиБ, удаление истории/заметок, retrieval ручных заметок, guard неподтверждённых действий, /apply-template + /tokenize для реального бюджета контекста, адаптивные 60/24-30 FPS, исправление двойного tint шейдера, page Нагрузка.

Все 12 локальных проверок PASS; PowerShell 21 PASS; functional 42 PASS. Пакет 0.4.0 выдан вложением: `libfile_b3abab6a0df08191ab4367c17a7080dc`. Native X11 exported-pack 50 PASS, content/helper 8 PASS, delta 4 PASS: см. session.json. Не повторять предыдущие потерянные результаты real-model тестов: веса сейчас не проверялись. Native Windows ещё не запускался.

Ограничения: girl cutout + процедурный idle, 0 body clips; нет ASR/custom voice/screen vision/page reading. Qwen1.7B прежняя, модель скачивается отдельно при первой настройке. Один винно-серебристый стиль. Пользователь обсуждает лимон-маскот; концепт принят как направление, assets не заменять без подготовки.

Карта: `src/app.gd`, `src/tools/desktop_actions.gd`, `native/desktop_bridge.ps1`; память `src/core/conversation_memory.gd`; диагностика `src/tools/diagnostics.gd`; чат `src/ui/chat_view.gd`; запуск/границы `src/desktop/companion_window.gd`; ИИ `src/providers/llama_http_provider.gd`.

Sandbox-ссылки у пользователя НЕ работают. Финальный ZIP прикреплять через native Library; предыдущий 0.3.3: `libfile_918be8a7635c8191bdb7c7c258f84a8c`. Исходники не дублировать туда, GitHub хранит код.
