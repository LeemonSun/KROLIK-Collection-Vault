# Leemon 0.11 — сохранено и выдано

Начать с `python3 tools/resume.py status` и recovery/session.json. Далее docs/WORKFLOWS_011.md; Cloud — docs/STEAM_CLOUD_PLAN.md. Не перечитывать чат и не восстанавливать фундамент заново. GitHub LeemonSun/KROLIK-Collection-Vault/main только хранилище, без Actions/remote builds. Без субагентов без прямого разрешения. Последний head — .resume-remote.json.

Сборка0.11 ZIP (~54MB), отчёт и MP4 сохранены; точные IDs/SHA вsession,ссылкиREADME. AI/ сохранять,0.8/0.9/0.10модели совместимы. START_WINDOWS.cmd исторический. Полный0.8offline4parts остаётся вLibrary,не скачивать заново ради патча.

Новые модули:
- window_workflow.gd: до4USER-AUTHORED шагов через→/newline,не модельное разложение произвольной цели. Revision отменяет deferred следующий шаг. Approval30s+freshpreflight+verify каждого. Invokeбезбизнесverify стопаетцепь. Exactunique select/expand/write не будятLLM. Негативные инструкции блокируются,explicit writepayload остаётсяданными.
- leemon_rig.gd:26авторских процедурных поз,6частей одного мастера,180msblend,staticregion. SpeechBubble.noFocus/transient безtopmost(X11запрещаетоба),text<=190,autoClear. Behavior150msпоstate,никакогофоновогоэкрана. Разумное размещение возле окна,безслучайного автопатруля. Съёмка96кадров/9.6секMP4черезtest_motion_preview+ffmpeg,неWindowspc.
- text_patch.gd/file_edit_window.gd: выбранныйNativeFileDialogпуть,UTF8<=1MB,unique exactreplace,reviewtoken120s,SHAbackup+index,temp+rename,posthash,restoreпослерестарта,остановкаприchanged/pause/cancel.16MBbackupbudget.Никаких arbitrarypaths отLLM, binary/XLSX/elevation. Windows locks/reparse/TOCTOU не полностью закрыты.
- fact_memory.gd: explicit upsert/delete,1024/512KB,max4retrieval/960bytes,corruption preserve,3way mergeconflicts. CommandsRU/EN/ZH. НЕCloudподключение. Неinfinite transcript compression.
- local_runtime memory_headroom: modelbytes+800MiB,vision+1GiB,OSreserve512MiB..2GiB. Unknownaccountingневыдумывается. Softguard,нестрогийRSSlimit.Однатяжёлаязадача/ограниченныепотоки/lazyload/idleunload.
- DesktopActionsзакрываетresultfileдоуничтожения(важноWindows),Readyчиститтолькоnoncejobsстарше60s. Свежиечужиеjobsнеудалять. Exportfixtureнуженизолированный/tmpuserdata:sharedscratchстарыеrequestsдавалиfalsefailure;дваждынаодномновомtemp18checksPASS.

Диалог:6пар,current factual/persona mode,shortcontext,explicitrequestedlanguagewins.Locale onlydefault. Mildsampling0.55/.85/topk20/presence.25тольконеfactualownedchat.JSON/перевод/зрениеlegacy.4/.9/40.Проверкаофициальныхвысокихпараметровухудшалакейсы(logcandidatehigh). Genericfillertrimсохраняетdecimals/URLs/code.1retryзатемавторскийcasualfallback,невсеответызаготовки. Model2Bвсёещёошибается:sciencekeywordtestможетпропуститьневерныймеханизм(«фильтрациясинегоспектра»).Неговорить«IQсильноймодели»/универсальнаяточность.

Сохранено0.10:одноразовоеUIAчтениесисточниками,эпhemeralQ&Aбезhistory/modelturns;password/Edit/ComboBox/offscreenнечитаются;leafTextPatternonly,18fragments/2400bytesmodel. Old0.9gatesнеослаблять:targetHWND/PID/start/title/id/name/capability,verbatimwrite,invokeexplicitnamedclick,approval+freshpreflight.СлучайDeleteнашуткубылраньше,защищёнcapabilitygates.

Итог:23sourcegroups;31workflow;61behavior;29realfile/memory;140layout;143nativeX11изfinalPCK;18exportedhelperдважды;16accesshelper+11readsynthetic;27realconversation/11requests;18realtexttranslationmixed;ZIPCRC. WindowsEXE/UIA/NativePicker/mic/voiceнеиспытаны. Publicgateblockedкакположено.

DevpathsвнеGit:devtools/Godot_v4.7.2-stable_linux.x86_64,pwsh/pwsh,xvfb,llama11901/llama-b11901;qa-fixture-011/{model.gguf,fixture.json,installed.json,runtime symlink};recovered-010/Companion_Preview/Companion.exe(template);preview-windows-v0.11.0. build_previewпринимает0.11EXESHA49bdb7... истарыеpins. Веса/ключи/пользовательскиефайлы/снимкиникогданевGit.

Еслиworkspaceсновастарый0.1:fetchtools/resume_bridge.jsизGitHubmain;bootstrapвНОВУЮсоседнююпапку;assetsruntime+test(verifyтребуетархивныеSignalart);сохранитьстаруюпапку,потомswapcanonical.Старый0.1этогопроходаcompanion-foundation-stale-011.ЗабиратьтолькоактуальныйлёгкийZIPдляtemplate,ненужновсе1.9GBparts.

Дальше:реальнаяWindowsприёмкаипараметрыжелеза;измеренныйболееcильныйofflineинтеллект;standarddocument/tableadapters;safe model-generated boundedplans/guide->patch;consolidate developerdownloads. SteamCloud:собственныйAppID/accounts/binding/configи2PCтесты.Данныепоканекудауходят.НеобещатьлюбыеПК,абсолютнуюбезопасность,тысячиклипов,Steam1.0илиполнуюправовуюочистку.Лицензиисохранять,непереименовыватьчужиевесав«обученонами».
