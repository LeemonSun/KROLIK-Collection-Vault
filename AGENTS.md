# Project instructions

Start with RESUME.md and `python3 tools/resume.py status`.
Read recovery/session.json and only the source/docs relevant to the current task.
PROJECT_STATE.md and docs/HANDOFF.md are detailed references, not mandatory rereads.
If the workspace is missing/stale, use tools/resume_bridge.js bootstrap; restore assets only as needed.
Before pausing, update recovery/session.json and checkpoint the source capsule to GitHub.
Work locally. GitHub is storage only: do not configure or run Actions, remote builds, hosted tasks or deployment.
Preserve offline-first behavior, RU/EN/zh-Hans, and universal screen understanding.
Do not replace generic vision/context/planning with a required engine per game.
Never claim a placeholder, candidate model or contract is an implemented AI capability.
Do not remove upstream license notices or represent existing model weights as original training.
Model pruning is experimental and must be compared against a baseline across all three languages and general vision tasks.
For application changes run tools/verify_project.py and relevant Godot tests; inspect logs as well as exit codes. For tooling-only changes run the relevant tooling tests, without rebuilding the app.
Never commit API keys, user files, screen captures, model weights or unreviewed assets.
Use manifest status fields honestly. Public release gate must fail while required release evidence is missing.



Latest user decision: defer pixel art; continue the current character. v0.3 adds a private local Windows preview; it is not a cleared Steam release. Keep managed text inference, screenshot capture, visual reasoning and browser reading separate. Never commit downloaded model weights; local build archives may be stored as reviewed private preview artifacts under downloads/.

Current user decision (27 Oct): ONE polished visual style only; no theme switching or alternative palettes now. Fix startup access before continuing visual work. Main Window is now the character; never restore the offscreen 1px host.

Latest feedback: conversational correctness before decorative breadth. SelfKnowledge must describe actual app state, not invented memory/online facts. Keep ordinary tasks with the LLM. Preserve one visual style. Consolidate updates; do not send a new manual patch for every remark. Native files must be delivered as attachments because sandbox archive links failed.


Only Leemon is active. Do not restore retired characters or alternate appearances. One graphite/amber style, one shared master texture. Git history and mandatory license notices must remain intact. Local source retirement is recorded in recovery/retired_paths.json; validate dependencies before removing files.

Latest product decision (28 Oct): the primary goal is a general adaptive desktop agent: observe UI/screen, infer a free-form goal, make a bounded plan, use shared tools in existing applications, observe and verify results, adapt when interfaces change. A catalog of deterministic commands is support, not the product goal. Do not build a replacement Office/virtual user environment or train a separate model for each app. Adapt through context, observation and verified procedural memory; continuous weight training is not implemented. Preserve authority/verification gates. Next major work must prioritize this general loop over expanding manual shortcuts.

Future visual ideas are recorded in docs/VISUAL_IDEAS.md: optional original comic chibi helper alongside Lemon. Record only; active mascot remains Lemon. No retired assets restored.
