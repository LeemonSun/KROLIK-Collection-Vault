#0.21 semantic comparison — interim manual review

No model IQ score, no universal safety claim. Fixed seed42/small synthetic sample. Modes do not train weights. CPU2context2048, cache0/checkpoints0. No Windows/gameFPS acceptance.

##2B direct,30cases

21ordinarygenerations+9UIArequests. ThreewriteUIArequests failedHTTP500 because fixture roundtrip converted JSONschema maxLength256to256.0; not a model semantic failure. Canonical integer-schema rerun needed before aggregate UIA score. The earlier020actualUIA9/9 is separate evidence, not replacement for failed harnesscases.

Main failures: all3liar responses wrong; EN/zhinvalid some/all entailment accepted; all3configplans miss required backup/duplicate stop or advise changing first/all instances. RUentailment main conclusion correct but truncated. All3arithmetic examples correct. Project renaming recalled in3languages. Typo/no-access responses mostly request text but contain broad tool-denial boilerplate. Do not equate short factual replies with a general agent.

##4B direct, interrupted control

Stopped at13completedcases due user's weakPC/backgroundgame priority. Same matched prompts/budgets/threads. At least the RUplan still omits backup and permits first replacement before ambiguity stop. RUliar begins “false” then concludes undefined: internally inconsistent. RUnegative entailment better. Larger model not adopted, no selector/default change, weights remain dev-only. Median pairedwalltime ratio recorded below is an indicative sharedLinuxhost observation, not a clean speedbenchmark. Process-group cancellation preventedfinalRSSreceipt; do not invent its RAM peak. File size is2.74GB, not totalRAM.

##2Bthinking128,12cases

All3arithmetic answers correct as already in directbaseline. All3liar answers retain wrong/contradictory truth assignment; EN leaks ongoing draft/“Wait” and truncates. RUnegative main conclusion correct but invented converse contradicts premise; regression. ENnegative main conclusion corrected but example/explanation loose; zhnegative correctly rejects entailment. All3plans stillfailbackup/ambiguity requirements. No robust general improvement; automatic deployment rejected. Peak1957015552B in this12caseworker, not exactpairedRAMcomparison to30casebaseline.

##Secondaryreader

36real2B generations (18frozen020+18new021). Both18acceptedstructurally; bothwronglyanswerRU/ENlocationquestionswithtimeinsteadofabstaining. Native excerpts exact, schema/literalguards not semantic truth. Old unstable sort happened to retain late source in this fixture; do not claim all late sources were previouslylost. New deterministicqueryrank helps dedicatedselectiontests, not demonstrated broadersemanticgain.

##Pending

Bounded512reasoning-token experiment completed9logic/plan cases on same2B. RUliar main conclusion improved but inventedname; RUnegative regressed to invalid entailment; ENliar/zhliar still wrong; all3plans fail duplicate-stop/backup requirements. Not adopted. No automatic extra thinking or model/time added to existing app.

Indicative4B/direct paired median walltime ratio: 2.06× over13completed cases.

## Categorical tool work

Initial index-binding and first compact interpreter pilots failed; raw reports retained, interrupted before all cases, no finalRSSreceipt. Final two-field compact interpreter completed12generations. Final-source revalidation accepts5/12, all5expectedverdicts;7rejected. Earlier running validator cached pre-fix Cyrillic-case/surface code, so original acceptancefields are historical, not final acceptance. This is not5/12broadNLaccuracy: final source gates changed after raw generation. Experimental model interpretation is OFF by default.

Production direct path parses only bounded flat categorical syntax and runs a unary-set decision procedure, with no model.12typedfixture arguments solved correctly in actualApp, including valid/invalid/inconsistent/transitive forms across RU/EN/zh; no neural inference. Independent exhaustive4096problems verified solver and countermodels;1536generated grammar cases verified parser→solver equivalence. These are formal/synthetic tests, NOT a globalIQ score or proof of natural-language understanding. Domains are nonempty; categorysets may be empty.6classes/8premises, no counts/relations/self-reference/causality. Interpretation always displayed; canonical generic nouns and selected Chinese nominal suffixes are assumptions, not a universal NLP parser.
