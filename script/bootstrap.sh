#!/bin/zsh
# AI-Author: Codex (OpenAI gpt-5.6-sol)
set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"

command -v swift >/dev/null 2>&1 || {
  print -u2 "Swift toolchain is required. Install Xcode or Command Line Tools."
  exit 1
}

xcode-select -p >/dev/null
cd "${project_root}"
swift package resolve
print "Native Swift workspace is ready; there are no third-party runtime dependencies."
