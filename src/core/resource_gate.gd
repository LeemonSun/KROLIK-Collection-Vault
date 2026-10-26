extends RefCounted
## Admission control for future heavy jobs, not an OS memory limiter.
var max_jobs = 1
var active = {}

func acquire(job_id, kind):
	if job_id.is_empty() or active.has(job_id):
		return false
	if kind not in ["chat", "vision", "asr", "tts", "ocr"]:
		return false
	if active.size() >= max_jobs:
		return false
	active[job_id] = kind
	return true

func release(job_id):
	active.erase(job_id)

func cancel_all():
	active.clear()

