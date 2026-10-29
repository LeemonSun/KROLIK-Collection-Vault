# Leemon0.23 — general application entry and observed UI effects

The product direction is a general adaptive agent in existing third-party applications, with no Microsoft preference or per-app model/coordinate recipe. This pass expands entry and common UI primitives; it does not achieve arbitrary GUI autonomy.

## Application observation and selection

Own PowerShell adapter observes StartMenu/CommonStartMenu shortcuts (max512 each, recursion only these roots), Desktop/CommonDesktop shortcuts and EXEs(max64 each), AppPaths registration(max256 each hive), and currently visible running portable apps. It does not recursively scan the drive or read user documents. Existing system helpers remain optional support.

Catalog deduplicates executable paths; rejects UNC/non-EXE/reparse paths and a bounded interpreter/installer name list. These are best-effort filters, not proof of software trust. Metadata comes from file ProductName/FileDescription; it is untrusted data.96records/24KB/8sec soft metadata budget, running apps first; IPC15sec deadline. Enumeration may time out, omit unregistered portable apps, or truncate. No permanent watcher or model load for catalog scan.

Own generic Cyrillic→Latin folding + bounded edit distance provides exact/fuzzy name selection, e.g. «кролик контрл»→Krolik Control. No special Krolik/VPN brand alias is added. Equal scores require further selection. Name matching is not a semantic security guarantee. Chinese translations/purpose-only requests use the existing small local model over observed aliases; it cannot supply paths or commands. Model semantic quality in this pass is NOT measured on actual weights. Injected test answers prove plumbing/authority, not intelligence. Ambiguity/missing model falls back to a30sec user choice.

Model sees bounded names/product/descriptions, not paths. Native launch accepts an opaque ID and observed filesize/mtime stamp, rebuilds the catalog and checks the file again. Existing visible matching process is reused. Changed executable triggers at most1fresh catalog rescan; missing/unverified windows do not start actions. Atomic replacement races/signature trust/process launch permissions are not fully solved.

Original goal then enters existing bounded UIA loop in that actual window. Explicit Russian/English/Chinese desktop delegation is routed before generic application/web handling; existing explicit selected-window and document commands retain priority. No separate domain model per application, no default Microsoft tool route for «включи мой впн».

## Generic common actions

Delegated navigation now includes relevant observed buttons without requiring the user to quote their exact caption. Each proposed effect still needs review, fresh target/descriptor validation and original tool guards. Extra lexical effect filter excludes unrequested delete/send/pay/install categories; it is incomplete and cannot infer every dangerous action. Captions are untrusted; no generated shell/code execution.

TogglePattern supports desired ON/OFF, not blind flipping. Only known binary prestates0/1 accepted. Already-correct state is idempotent; changed prestate rejected, unknown/indeterminate state stopped. At most1Toggle call, immediate provider state check and fresh Godot observation. A toggle ON is not proof of VPN connection, saved config or business goal.

For generic Invoke, a new bounded observation checks semantic UI-state change (ignores RuntimeID-only churn). Up to3reads with short waits; no repeated button press. A changed UI is recorded as `ui_changed_not_goal_verified`, not a completed goal or connected-network receipt. The shared loop can then plan another step, under existing4steps/240sec limits. No visible state change stops unverified. Identical recreated controls require stable scoped descriptors. After a native stale rejection, at most2fresh replans, each still reviewed, within existing budget. This does not handle arbitrary new top-level modal windows or cross-app task planning.

## Privacy and compute

Catalog/goal/control details remain transient/ephemeral, excluded from ordinary model dialogue/history. Only bounded catalog fields are sent to the local model, never cloud. Existing one2Bworker/quiet mode/idle unload retained. No new OCR/VLM server/dependency/model weights. Native inventory has actual cost; Windows/game FPS/RAM/CPU not measured here.

## What this does NOT establish

No actual Windows, v2rayTun, Krolik Control, PowerShell5.1 or hardware acceptance occurred. No guarantee that the model identifies an unknown client's purpose or chooses correct controls. No visual-only coordinate action fallback, full modal/cross-app loop, background browser DOM access, universal file editing, Windows configuration parity with Krolik Control, driver install, or Steam release clearance. Existing screen vision is separate and does not make unsupported UI actions implemented.

## Research and rights

Reviewed primary project docs and licenses29Oct2026:
- https://github.com/microsoft/UFO/blob/main/ufo/README.md — host/app selection, observed UIA plus visual context, shared GUI/API tools.
- https://github.com/microsoft/UFO/blob/main/LICENSE — MIT, preserve notices if code is adopted.
- https://github.com/microsoft/WindowsAgentArena — benchmark diverse third-party tasks and accessibility/vision modes.
- https://github.com/microsoft/WindowsAgentArena/blob/main/LICENSE — MIT.
- https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.togglepattern.toggle — state cycling; Toggle is not a set-value operation.
- https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.invokepattern.invoke — invocation need not mean task completion and providers may block.

No code, assets, branding or framework dependencies were copied from these projects. New adapters/planner changes are implemented in this repository; existing legal/upstream notices remain. MIT examples do not provide blanket clearance for all project art/models/distribution. No guarantee against all legal complaints.
