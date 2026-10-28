# Primary references checked28Oct2026

- https://huggingface.co/Qwen/Qwen3.5-2B/raw/main/README.md — official post-trained model card, intended use note; sampling parameter recommendations; explicit warning that2Bthinking can loop. Recommendations were tested as a candidate, not accepted merely because upstream recommended them.
- https://github.com/ggml-org/llama.cpp/blob/b11901/tools/server/server-common.cpp — thinking kwargs override, reasoning budget forwarding, top-level schema.
- https://github.com/ggml-org/llama.cpp/blob/b11901/tools/server/server-schema.cpp — timings and reasoning budget controls.
- https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/tree/e87f176479d0855a907a41277aca2f8ee7a09523 — dev-only candidateQ4_K_M,2740937888bytes, SHA25600fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4; card declaresApache2.0. No new weights/runtime shipped or license notices removed. Not a legal clearance or universal quality claim.

Actual receipts: reports/benchmark017-ab.json, benchmark017-4b.json, benchmark017-vendor.json, real_test_composer_real017.txt. No user documents or real desktop images used.
