# Windows preview 0.3

Экспортирован реальный Windows x64 PE EXE с встроенным пакетом Godot. Godot/Python пользователю не нужны. ZIP: 53 725 043 байта. SHA-256: `e08b0b80095b8ec3feb312d841aeae99d73da596365a48527000b6dc1b542a39`.

Содержимое EXE проверено Linux-движком как main-pack: UI smoke 3 языка × 7 страниц, ресурсы доступны. На Windows PE не исполнялся: прозрачность, mouse passthrough, drag, системная озвучка, захват и installer нужно проверить на целевом ПК. Прозрачный desktop-cutout и красный переход — прототип, не готовый body rig.

Текстовый inference и lifecycle worker реально проверены на Linux. Runtime Windows получен из официального b11901 CPU release и проверен по опубликованному SHA-256; его MSVC DLL dependencies требуют Microsoft Visual C++ x64 runtime. Системный VC++ эта preview не устанавливает автоматически; ссылка есть в START_HERE.txt и README.

На GitHub для ограничения размера запроса данные ZIP/исходного OFL шрифта разделены на части; восстановление целостности проверено SHA-256. START_WINDOWS.cmd восстанавливает локальный пакет без сети и компиляции. Сам CMD/PowerShell здесь не исполнен.

Это частная preview, публичный Steam release gate остаётся закрытым.
