# Leemon0.24 — RU/EN constraints and paged observed controls

User priority: Russian and English practical requests first; new languages and Chinese improvements deferred. Existing locales retained. This is an observation/coordination change, not retrained weights or a demonstrated real-model IQ gain.

## Changes

- Own conservative intent_constraints parser. Leading negation/unknown negative conditions still reject desktop delegation. Positive RU/EN request plus ONE trailing «не закрывай окно/приложение» or “do not/don't close the window/app” (comma or и/and) is allowed, retained in the original goal and enforced by the proposal/validation effect filter against close/exit/quit/закрыть/выход captions and common X symbols. This is not full semantic constraint understanding; misleading captions and other side effects remain possible. Literal field payloads retain their existing data boundary. The incidental Chinese 特别 false positive is avoided by recognizing negative action prefixes, not the isolated character 别.
- Explicit original-index tie breakers in UI and app ranking. HasKeyboardFocus included as bounded observation and prioritizes captured controls. No new app brand aliases/coordinates.
- UI proposal contexts cover all eligible CAPTURED controls in pages of<=24controls/2200serialized control bytes. Globally unique aliases and page-bound action enums. Coverage counters distinguish observed/eligible/prepared, planned pages and requested controls/pages. This does not expand native200visited/90records/depth8/2500ms observation: absent controls cannot be recovered by paging.
- ui_observation_scan is a separate read-only controller. A model can respond none on an irrelevant page, ask for ambiguity, or propose one bound candidate. All pages of the same snapshot are considered before a sole candidate is offered for ordinary review. Several proposed candidates stop for clarification; no hidden click or “goal done” claim. Full-snapshot TTL and existing preflight apply. At most12page requests per scan and12model-selection calls in the shared agent's4step/240sec budget. A budget/TTL failure does not execute collected partial candidates. More pages can increase latency; no speed-up or game-FPS claim.
- Draft composition retains its existing first bounded-page contract and unverified semantic limits. It is labelled in the prompt and counters; not claimed as full paged authoring. Literal direct selection can locate a unique target in later prepared pages.
- Action-only selection reserves64 output tokens instead of256 (literal writes keep256; draft composition retains its own budget). Same one worker, CPU/idle policy/cache settings. No new model/download, no continuous screen watcher.
- Diagnostics retains only numeric observation counts and a whitelisted launch settings summary (threads, context, batch, parallelism, CPU/GPU-layer settings, cache/checkpoints, priority, idle timeout). No API token, executable/model path, user text or control caption. Last attempted launch is not proof of a running worker. Quiet effective settings remain1thread/batch32/30sec idle; base profile2threads is overridden by profile.effective.

## Evidence and limits

New observation tests exercise RU/EN constraint routing/filtering, equal-score order, every captured candidate represented in a page, cross-page binding, last-page review and fresh preflight, ambiguity/no effects, earlier-page winner followed by none, cancellation,12call cap and launch-summary redaction. These are injected model/UIA fixtures, not proof of real model understanding. Actual Windows/apps/DPI/game resource use and real2B language/selection quality not measured here. No visual-only action fallback, full cross-app/modal planning or Krolik Control capability parity.

Independent review input: user-supplied «Leemon0.23 независимый разбор и план развития», read29Oct2026. Confirmed negation/name-key defects in Godot. Quiet-mode contradiction was not confirmed: effective profile already overrides the base. Model/license suggestions in that review were not adopted without separate primary-source validation. Chinese name-key repair deferred per user's language priority.

## Final local validation

51fresh source groups PASS,69new cases PASS. Final PCK14groups PASS (draft016 external fixture as in tools/test_packed_regressions.py);nativeX11 20newRUEN+156general+35motion PASS, previewZIPCRC PASS. No actual Windows/model semantic/FPS result.
