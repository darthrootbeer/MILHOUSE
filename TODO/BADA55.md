---
id: BADA55
status: done
deps: []
files: [scripts/milhouse.sh]
---
::context
Raw cursor-agent stream-json is unreadable when tailed; operators need a clean, human-readable run log.

::done-when
- .milhouse/out.txt is readable text (not raw JSON fragments)
- raw stream-json is preserved separately for debugging

::steps
1. Capture raw stream-json to a dedicated file
2. Filter stream-json down to final assistant text messages for out.txt
3. Keep non-JSON stderr lines visible in out.txt for errors

::avoid
- Don’t lose debugging data; keep raw stream
- Don’t break non-python environments (fallback behavior)

::notes
Prefer python3 for filtering, fall back gracefully if missing.
