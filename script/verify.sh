#!/bin/zsh
# AI-Author: Codex (OpenAI gpt-5.6-sol)
set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"

cd "${project_root}"

/usr/bin/plutil -lint Resources/Info.plist
[[ -s Resources/AppIcon.icns ]]
swift test
swift build --product LinguaBar

rg -q 'AudioHardwareCreateProcessTap' Sources/LinguaBar/Services/CoreAudioProcessTap.swift
rg -qi 'google meet' Sources/LinguaBar/Models/AudioSource.swift
rg -q 'TranslationSession.Configuration' Sources/LinguaBar/Views/ContentView.swift

print "Native Core Audio capture, Meet-first selection, tests, and app build passed."
