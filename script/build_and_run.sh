#!/bin/zsh
# AI-Author: Codex (OpenAI gpt-5.6-sol)
set -euo pipefail

mode="${1:-run}"
script_dir="${0:A:h}"
project_root="${script_dir:h}"
app_bundle="${project_root}/dist/LinguaBar.app"
app_binary="${app_bundle}/Contents/MacOS/LinguaBar"

cd "${project_root}"

if [[ "${mode}" == "--verify" || "${mode}" == "verify" ]]; then
  "${script_dir}/verify.sh"
else
  swift build --product LinguaBar
fi

bin_dir="$(swift build --show-bin-path)"
built_binary="${bin_dir}/LinguaBar"

[[ -x "${built_binary}" ]] || {
  print -u2 "Built executable not found: ${built_binary}"
  exit 1
}

/bin/mkdir -p "${app_bundle}/Contents/MacOS" "${app_bundle}/Contents/Resources"
/bin/cp "${built_binary}" "${app_binary}"
/bin/cp "${project_root}/Resources/Info.plist" "${app_bundle}/Contents/Info.plist"
/bin/cp "${project_root}/Resources/AppIcon.icns" "${app_bundle}/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --deep --sign - "${app_bundle}" >/dev/null

for previous_pid in $(pgrep -f "${app_binary}" 2>/dev/null || true); do
  kill "${previous_pid}" >/dev/null 2>&1 || true
done

launch_app() {
  /usr/bin/open -n "${app_bundle}"
}

case "${mode}" in
  run)
    launch_app
    ;;
  --debug|debug)
    lldb -- "${app_binary}"
    ;;
  --logs|logs|--telemetry|telemetry)
    launch_app
    /usr/bin/log stream --info --style compact --predicate 'process == "LinguaBar"'
    ;;
  --verify|verify)
    launch_app
    sleep 3
    pgrep -f "${app_binary}" >/dev/null
    print "LinguaBar native app is built, tested, signed, and running."
    ;;
  *)
    print -u2 "usage: $0 [run|--debug|--logs|--telemetry|--verify]"
    exit 2
    ;;
esac
