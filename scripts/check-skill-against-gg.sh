#!/usr/bin/env bash
# Check that every gg command the skills name is a command gg actually has.
#
# This replaces the property the skill used to get from living inside the gg
# binary: "it ships with the CLI, so it cannot disagree with it." Co-location
# only ever guaranteed the two shipped together — never that they agreed. This
# checks the thing that was actually wanted, and catches a renamed command or
# flag, which co-location never did.
#
# With no arguments it checks the reference skill on its own first — that run
# also reports the gg commands the skill never mentions — and then the other
# skills, which only need to name real commands. With paths, it checks those
# markdown or workflow files instead: the recipes repository and the website
# run it over the commands they print.
#
# Needs `gg` on the PATH. CI installs the latest release.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -gt 0 ]; then
  exec python3 scripts/check_skill_against_gg.py "$@"
fi

python3 scripts/check_skill_against_gg.py
others=()
for f in plugin/skills/*/SKILL.md; do
  [ "$f" = plugin/skills/gagarin/SKILL.md ] || others+=("$f")
done
python3 scripts/check_skill_against_gg.py "${others[@]}"
