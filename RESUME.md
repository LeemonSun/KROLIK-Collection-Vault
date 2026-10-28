# Сейчас0.9: ночная0.8восстановлена, оконныецели добавлены

Начать сrecovery/session.json иdocs/GOAL_PROPOSALS.md. Не восстанавливатьпроектзаново:0.8точно восстановлена из3aa27,18проверок прошли; новый0.9блокпроверенrealmodelна3языках,упаковкавпроцессе. Последнийheadв.resume-remote.json.

# Leemon 0.8 — текущая точка

Не восстанавливать проект заново. Сразу читать recovery/session.json, python3 tools/resume.py status, затем только нужные модули. GitHub LeemonSun/KROLIK-Collection-Vault main — хранилище, никаких Actions/remote build. Последний checkpoint до0.8: bcc22b8; свежий head смотреть .resume-remote.json. tools/resume_bridge.js checkpoint поддерживает capsule shards; сохранять после крупных блоков. Никаких субагентов без прямого разрешения.

0.8 реализовано: Qwen3.5-2B Q4 (1.28GB), optional F16projector668MB, Whisperbaseq5_1+runtime69MB. Одновременно один тяжёлый inference. Голос только понажатию<=20с, текст вчерновик. Экран понажатию640edgeJPEG вRAM; imageбезистории/диска; projectorworkerвыгружаетсяпослеответа. ОбщиеUIAоперациивыбранного HWND+PID+startticks через typedPowerShell, безmodel->shell. Passwordsblocked, writeValuePatternonly, noEnter; riskybuttonsconfirm, stale/ambiguousfailclosed. Окнасписокдок24/controls90/depth8. Windows приёмка ещё НЕвыполнена.

Consumer: разговор карточками и copy, один графит/янтарь, компактный210x232маскот, размеры75/100/125/150%,16процедурныхсостояний+180mscrossfade+мipmap. Основныхстраниц6,служебныеопциональны. TXT/DOCX вDocuments/Leemon, безперезаписисуществующихфайлов. One-typo leadingverb correction, не меняет payload/отрицание/опасныеиописательныеглаголы.

НовыйготовыйlightZIP внеrepo Companion_Preview_Windows_v0.8.0.zip. Полный offlineZIP Leemon_0.8.0_Offline_Windows.zip собранисохранён4частямивLibrary,IDsвsession; AI рядомсEXE,text/voice/vision. ПроверкиSHAв1низкоприоритетномпотоке, cachedfingerprint, безкопированиявAppData. ПрофильAppData по-прежнему Companion Foundation; legacy local-ai-v1 не удалён. root START_WINDOWS.cmd исторический0.5, НЕвыдаватьего зановый0.8. Дляпользователя nativeZIPизLibrary; источникпакетаиidentityзаписатьвsessionпослеуспешнойзагрузки.

Картинапроверок: reports/VALIDATION.md (18групп), voice_real.txt24, vision_real.txt20, bundle_real.txt11, native_ui.txt94, access_bridge.txt16, desktop_bridge.txt24. Читатьвыход/ошибки, не доверятьexit0. Actualtext/translation0.8 fixtureвпроцессе real08.txt снаружиrepo. Linux/X11неозначаетWindowsпроверку. Голосcustom, browserreading, arbitrarygoalplanner, SteamCloud пока отсутствуют. НеобещатьSteam1.0/«всеПК»/юридическуюгарантию.

Сборка: tools/build_preview.py сtemplate preview-windows-v0.6.0/Companion.exe иGodotdevtools; tools/build_offline_bundle.py. Моделиai-fixtures/offline-stage строго внеGit. Нативнаязагрузка черезLibraryhelperпапка library-next, использоватьтекущиеhelperвэтомпроходе. ПослеартефактовпроверитьSHAидоставку, обновитьотчёт/sessionиcheckpoint.

Последнийрезультат:0.8полностьюупакован,smallZIP/report/previewи4offlinepartsсохранены. РеальноеWindowsтестированиенеисполнено. READMEактуален,START_WINDOWS.cmdисторическийнеперепутать.
