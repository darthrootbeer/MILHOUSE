---
id: C0FFEE
status: done
deps: []
files: [install.sh]
---
::context
Need a clean, repeatable Milhouse install into any repo, with optional installs of required/recommended external tools.

::done-when
- install.sh installs scripts/milhouse.sh into a target directory
- install.sh ensures .milhouse/ is in the target .gitignore
- install.sh can optionally install gum (brew/apt/dnf) and cursor-agent (npm)

::steps
1. Create root install.sh that copies scripts/milhouse.sh into target
2. Add safe, opt-in dependency installation flags/env vars
3. Keep non-interactive behavior safe (no surprise installs)

::avoid
- Don’t require pip installs (Milhouse is bash-first)
- Don’t auto-install tools when non-interactive unless explicitly opted-in

::notes
Use --yes for interactive auto-install; otherwise print clear manual commands.
