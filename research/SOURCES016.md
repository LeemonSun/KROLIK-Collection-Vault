# Primary references for0.16

Pinned runtime source, inspected28Oct2026:
- https://github.com/ggml-org/llama.cpp/blob/b11901/tools/server/server-common.cpp — top-level json_schema/response_format handling and chat-session grammar forwarding.
- https://github.com/ggml-org/llama.cpp/blob/b11901/tools/server/server-schema.cpp — json_schema to constrained grammar.

No upstream code or weights copied into new source modules. Existing runtime/model notices remain. API behavior tested with the already pinned Linux runtime and hash-verified model; Windows remains unverified. The application independently validates every proposed action even when constrained generation is requested.
