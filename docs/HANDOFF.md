# Продолжение Leemon 0.14

Читайте RESUME.md, recovery/session.json, WORKFLOWS_014.md и component_backlog.json. Пользователь подтвердил основной приоритет: общий адаптивный агент, который видит интерфейс/экран, понимает свободную цель, планирует, использует инструменты в существующих приложениях и проверяет/адаптирует шаги. Инструменты не заменяют этот контур. Отдельная модель на приложение и новая виртуальная пользовательская среда не нужны.

0.14: calculator, unit_converter, windows_settings (только открытие), public_page (bounded HTTPS excerpts), utility_intent + Router/Policy/App; исправлен follow-to-latest для синхронных ответов. Архитектура/ограничения в WORKFLOWS_014. Источники стека в TECH_STACK_013. Модели прежние, новые кандидаты не установлены.

Проверки: run_checks29groups, utilities014, public_transport014, independent localTLS, Office и native215изPCK. Нужны настоящий Windows, publicweb/proxy и замеры модели. Сохранять authority gates, privacy и resource budget. GitHub только хранилище. Перед паузой обновить session и checkpoint.
