#!/bin/zsh
# AI-Author: Codex (OpenAI model not exposed by runtime)
set -euo pipefail

project_root="${0:A:h:h}"
cd "${project_root}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 "Invalid version"; exit 1; }
release_root="${RELEASE_OUTPUT_DIR:-${project_root}/dist/releases}"
/bin/mkdir -p "${release_root}"
release_root="${release_root:A}"
name="LinguaBar-${version}-macos-arm64"
for extension in dmg zip; do
  [[ ! -e "${release_root}/${name}.${extension}" ]] || {
    print -u2 "Existing release: ${name}.${extension}; choose a new RELEASE_OUTPUT_DIR."
    exit 1
  }
done
identity="${SIGNING_IDENTITY:-}"
if [[ -z "${identity}" ]]; then
  identity="$(security find-identity -v -p codesigning | /usr/bin/awk '/"Developer ID Application:/ { print $2; exit }')"
fi
[[ -n "${identity}" ]] || {
  print -u2 "No Developer ID Application identity visible. Run with access to the login keychain or set SIGNING_IDENTITY."
  exit 1
}
staging="$(/usr/bin/mktemp -d "${release_root}/.staging.XXXXXX")"
app="${staging}/LinguaBar.app"
swift test
swift build -c release --arch arm64 --product LinguaBar
bin_dir="$(swift build -c release --arch arm64 --show-bin-path)"
/bin/mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"
/bin/cp "${bin_dir}/LinguaBar" "${app}/Contents/MacOS/LinguaBar"
/bin/cp Resources/Info.plist "${app}/Contents/Info.plist"
/bin/cp Resources/AppIcon.icns LICENSE THIRD_PARTY_NOTICES.md "${app}/Contents/Resources/"
/usr/bin/codesign --force --options runtime --timestamp --sign "${identity}" "${app}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${app}"

# Notarize the app first so the final ZIP and DMG contain its stapled ticket.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  /usr/bin/ditto -c -k --keepParent "${app}" "${staging}/notary-upload.zip"
  xcrun notarytool submit "${staging}/notary-upload.zip" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${app}"
  xcrun stapler validate "${app}"
fi
/usr/bin/ditto -c -k --keepParent "${app}" "${release_root}/${name}.zip"

dmg_stage="${staging}/image"
/bin/mkdir -p "${dmg_stage}"
/usr/bin/ditto "${app}" "${dmg_stage}/LinguaBar.app"
/bin/ln -s /Applications "${dmg_stage}/Applications"
/bin/cp LICENSE THIRD_PARTY_NOTICES.md "${dmg_stage}/"
/usr/bin/hdiutil create -volname "LinguaBar ${version}" -srcfolder "${dmg_stage}" -format UDZO "${release_root}/${name}.dmg"
/usr/bin/codesign --timestamp --sign "${identity}" "${release_root}/${name}.dmg"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "${release_root}/${name}.dmg" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${release_root}/${name}.dmg"
  xcrun stapler validate "${release_root}/${name}.dmg"
fi
/usr/bin/hdiutil verify "${release_root}/${name}.dmg"

# Explicit source allowlist excludes local histories, credentials and Git metadata.
source_stage="${staging}/linguabar-${version}"
/bin/mkdir -p "${source_stage}"
for item in Sources Tests Resources script docs Package.swift README.md README.zh-CN.md LICENSE THIRD_PARTY_NOTICES.md upstream.lock; do
  /usr/bin/ditto "${project_root}/${item}" "${source_stage}/${item}"
done
/usr/bin/tar -czf "${release_root}/LinguaBar-${version}-source.tar.gz" -C "${staging}" "linguabar-${version}"
(
  cd "${release_root}"
  /usr/bin/shasum -a 256 "${name}.dmg" "${name}.zip" "LinguaBar-${version}-source.tar.gz" > SHA256SUMS.txt
)
print "Release: ${release_root}"
print "Signed app retained at: ${app}"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  print "Developer ID signed; notarized and stapled."
else
  print "Developer ID signed. Not notarized: NOTARY_PROFILE was not supplied."
fi
