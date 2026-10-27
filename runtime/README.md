# Runtime 0.3

Управляемый CPU-worker и installer реализованы в src/runtime/local_runtime.gd. Пакеты скачиваются явно в user://local-ai-v1. Веса и бинарники worker не лежат в исходниках. Пины/размеры/SHA в config/local_worker.json; лицензии в legal/upstream. Детали: docs/LOCAL_AI.md.

Для Linux проверки используется отдельно подготовленный fixture. Windows пакеты проверены по хешам, но не запускались здесь. Сеть inference только loopback, со случайным портом и временным токеном; UI worker отключён. Модель не имеет shell/tools. Не превращать этот baseline в публичный релиз без реальной Windows приёмки и аудита.
