# Ночной проход, 28.10.2026 МСК

Пользователь уходит спать; разрешил продолжать крупными закончеными блоками, сохранять после каждого. Не обещать работу без ограничения сессии или ложную готовность Steam 1.0. GitHub только хранилище. Не использовать агентов без прямого разрешения (его нет).

## Текущее

Восстановлены исходники из 63d05d0, затем вручную возвращены финальные правки 0.6 из переписки: первый чат/layout, размер install button, passive guard, bounded repeat retry (новый response_quality.gd), очистка очереди при startup fail. Точный уже сохранённый ZIP 0.6 найден и скачан: libfile_29cda571ac3c8191be6b25d254b7838c, 53446375 bytes, SHA256 73d4cdece67f22a613076252fdd22d29f0e77d323f0733c207bff15d4968d2f8. Не создавать дубль и не выдавать WIP 63d за финал. Путь night-restored, EXE/PCK извлечены preview-windows-v0.6.0. Шрифт/мастер и архивные картинки восстановлены.

Исходники ещё не запечатаны новым checkpoint. 0.6 в Library есть, последние source fixes после63d были потеряны в Git; сейчас возвращены. Базовые проверки запускаются (reports), повторные/native regressions ещё довести. Новая shard capsule schema2, обратная совместимость; 12 Python и Node bridge тесты PASS. Текущая нагрузка на проверки: Godot session81104. Asset bridge cell5 ещё может завершаться. Долгие процессы могут пропадать при смене сессии — сверять файлы/логи.

## План законченных блоков

1. Восстановление 0.6 + нормальное сохранение крупного исходного дерева; verify/test; checkpoint. Отметить точный уже выданный ZIP0.6, не перестраивать без необходимости.
2. Реальный локальный AI bench: baseline Qwen3-1.7B vs Qwen3.5-2B Q4_K_M, языки RU/EN/zh и smalltalk/action honesty. Включать лишь прошедшее. Общий text+vision worker по запросу, один heavy job; no blind pruning. whisper.cpp base-q5_1 отдельно, OS TTS. Модели/веса в Git не складывать.
3. Базовый голосовой ввод по нажатию, до20с, никаких always-on/wakeword; локальный whisper subprocess, закрытие/отмена/таймаут/очистка WAV/TXT, место/память/потоки, fixture audio. Микрофон реальной Windows здесь не доступен, это явно отличать.
4. Generic Windows UI Automation: snapshot accessible text + именованные элементы/ValuePattern/InvokePattern для выбранного внешнего окна, read-result before claim. Никакой модели->shell. Пароли/неизвестная цель/смена окна/неоднозначные кнопки не трогать. Запись черновика без Enter/Send. Наблюдение окон и скриншоты только прозрачно/с управлением пользователем, без записи экранов в историю.
5. Vision отдельно реальная VLM if CPU compatible; explicit one-shot screenshot, shrink512, no disk persistence. UIA/OCR != полное визуальное понимание. Протоколы/фикстуры не заменяют тест Windows.
6. Потребительский интерфейс: меньше лимон (пример210x232), быстрый размер, меньше девелоперских страниц, один графитово-янтарный стиль; качественные переходы/сочетания существующего рига, не тысячи вымышленных clips.
7. Финальная сборка/чистый ZIP, delta от последнего подтверждённого, native Library, source+distribution metadata атомарно. Полный честный отчёт, реальные ограничения/неизмеренные Windows performance.

## Кандидаты и загрузки (вне git)

model-research/*.json — точные upstream metadata, не токены.
ai-fixtures — только transient weights/runtime. download_night_models.py -> model-research/download.log, session34516.
- unsloth/Qwen3.5-2B-GGUF, revision f6d5376be1edb4d416d56da11e5397a961aca8ae, Apache2: Q4_K_M 1280835840 / aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223; mmproj-F16 668227264 / 7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7.
- Official Qwen3.5-0.8B and2B model cards Apache2 with native image+text. ggml-org0.8Q8 text-only available, no mmproj there; 2B ggml-org official not found, do not invent URL.
- whisper.cpp ggml-base-q5_1 59707625 / 422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898, HF ggerganov/whisper.cpp revision5359861c739e955e79d9a303bcbc70fb988958b1 MIT.
- llama b11901 Linux CPU archive22496063 / 7c15e703cf4589e90371b51de0ed6ff1107df63b5f86e8d3c396019388be1fa8. Carefully restore validated relative .so symlinks.
- whisper stable v1.9.5 has no assets; matching nightly b5454 has binaries, metadata query in progress. Do not assume filenames.

## Pitfalls

Final0.6 native chat bug: creating ChatView at width0 temporarily yields huge minimum height2275, offset_bottom1815. Set view.size to native size BEFORE add_child; _fit_view resets anchors/offsets after ready, size changes and opening. Native first-open test must enclose editor/send, not merely assert submit works. Inline install button needs nonzero width144 (will still clip long label, improve at consumer pass).
WindowStyle Hidden must precede -File in PowerShell invocation (0.6 appended after File, fix next pass). Tool-window AltTab mode only when StatusIndicator exists; no fake 1px/offscreen root.
Native mouse_passthrough_polygon clips pixels on Windows; static envelope across11clips avoids SetWindowRgn12Hz and crop/jitter. 0.6 has11 authored procedural states,6parts, not frame/facial/3D animation.
Xvfb fixed98 stale locks occurred. Harness now picks a free TCP display. Logs still need inspection; exit0 alone insufficient.
Library helpers current under library-night; already downloaded archive, preserve returned identity. Refresh helpers only per new run, not each retry.

## Блок голоса (продолжение)

Исходники SpeechInput/WhisperTranscriber/MicrophoneRecorder/VoiceAudio и mic.svg уже добавлены. App привязан к voice_input, inline install row и mic button; запись20сек, распознавание<=90сек, CPU1job<=2threads/halfcores, текст вставляется в исходный composer безотправки. ОсновнойLLM выгружается передзаписью. Остановка и отмена очищаютWAV/TXT; stdout/stderr через nonblockingpipes, не влог. Реальная транскрипцияJFK черезGodot PASS23checks (reports/voice_real.txt), headless16checks PASS. 14 старых групп PASS после импортаSVG; свежиеvoice добавлены вrun_checks (теперь15). Native mic/setup assertions прогоняются. Windows физическийmic не доступен.

ASRconfig и обеMITnotice готовы. b5454win ZIP8928640 SHA6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb. RuntimeRoot Release/, installerнаследуетсяотLocalRuntime и теперь поддерживает archive_prefix. Взятытолькоwhisper-cli/whisper/ggml/base/CPUvariants; нетпостороннихservers/SDL/parakeet/tests. VC++runtimeобщаясистемнаязависимость какуllama.

Моделиоценка: Qwen3.5-2BQ4 text RAMpeak~2000MiB P50~1.83сек в12syntheticcasesCPU2; естьнеточностифактов. 4BQ4~4827MiB P50~5сек; физикакорректнее, ноsimpleanswersперегружены. Translation failures4B в первомbenchнельзяприписыватьнезнаниюязыка: systemстрогопорусски, асамиtranslationtestsEN/zh; нуженправильныйотдельныйprompt каквClipboardTranslator. Все12ответоввmodel-research/qwen35-bench.json/qwen4-bench.json внеGit. Нельзяназыватькачествоисправленным.

Qwen4веса2.74GBскачаныиверифицированы00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4 (unsloth/Qwen3.5-4B-GGUF e87f176479d0855a907a41277aca2f8ee7a09523). 2BF16mmprojнельзяподключатьк4B (другойhidden/outputprojection). Дефолт2Bвыглядитразумнеепопамяти; выбиратьпослеVLMпроверки. NativevisionещёНЕподключён.

Следующийблок: реальный2B+mmprojVLMbenchнаsyntheticUI, выбратькомпактнуюоднуtext+visionмодель; explicit screenshotJPEGbuffer512edge->ownedlocalHTTP, безсохранениякадров; mmprojтольконаexplicitrequest, выгрузкапосле. GenericWindowsUIAследом: избранноеокно/pinned HWND+PID+processStart, scopedinspection иexactnamedcontrols/ValuePattern/Invoke, непроизвольныйshell. Непечататьизmodelвслепуювлюбоеокно. ПоддержатьDOCXновыедокументыиумныйразборошибокпослереальныхмодулей, непутатьtext+visionсASR.
