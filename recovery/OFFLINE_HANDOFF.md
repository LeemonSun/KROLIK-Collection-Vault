# Отключение среды 27.10.2026

Ошибка: 409 environment_offline / Environment is not connected. exec-server и файлы недоступны. Внешний GitHub работал, поэтому уже написанные изменения сохранены как исходники; никакой код на GitHub не выполнялся.

Капсула dfdd8c0 — последняя перед отключением. Новые исходники восстанавливаются pending-overlay, привязанным к её content_id. Следующая обычная капсула после проверки заменит временный слой.

Windows 0.5 собрана, но не прикреплена. Финальный run имел одну старую проверку числа потоков; fixture исправлен в исходнике на явные 16 processors и не перепроверен. Не сообщать, что 0.5 уже доступна. Последняя выданная preview — 0.4.

Не генерировать лимона заново. Мастер и происхождение сохранены. render_leemon_motion.gd воспроизводит настоящее движение; ffmpeg может снова собрать GIF из 144 PNG.

Короткие real-model переводы прошли: The sun is bright. → Солнце яркое.; 今天是星期一。 → Today is Monday.; The moon is bright. → 月亮很亮。. Научный ответ содержал неточную фразу о более прозрачном свете: общий factual quality gate не считать пройденным.

Корневой START_WINDOWS.cmd и downloads/preview-manifest оставлены на 0.4, чтобы source ZIP не ссылался на недоступный binary chunk 0.5. Новый launcher — отдельный кандидат.

Linux inference fixture: official llama-b11901-bin-ubuntu-x64.tar.gz SHA256 7c15e703cf4589e90371b51de0ed6ff1107df63b5f86e8d3c396019388be1fa8. Restore validated relative .so symlinks when extracting; regular-files-only extraction caused missing libllama-common.so.0. Model URL/SHA are in config/local_worker.json. Do not fetch weights for UI-only work.
