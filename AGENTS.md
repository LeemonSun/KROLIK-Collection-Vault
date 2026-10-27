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


Read characters/signal_01/README.md before modifying the character. Main display is full body without a frame, never a portrait window replacement. Pixel/hybrid direction remains an option, not approved final art. The animation catalog is planned; never count events or fixtures as completed clips. Reviewed internal AI concept references may be stored privately with provenance and release_approved=false. This is not commercial asset clearance. Keep browser handoff distinct from page reading and reasoning.

Latest user decision: defer pixel art; continue the current character. v0.3 adds a private local Windows preview; it is not a cleared Steam release. Keep managed text inference, screenshot capture, visual reasoning and browser reading separate. Never commit downloaded model weights; local build archives may be stored as reviewed private preview artifacts under downloads/.
