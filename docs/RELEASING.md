# Release guide / 发行指南

<!-- AI-Author: Codex (OpenAI model not exposed by runtime) -->

## Build locally / 本机构建

Run on an Apple Silicon Mac with macOS 15+, Xcode's macOS SDK, and an accessible Developer ID Application certificate/private key:

```sh
./script/release.sh
```

The script uses an optimized Swift Release build, signs with hardened runtime and a secure timestamp, and produces:

- `LinguaBar-0.1.0-macos-arm64.dmg` — app plus an Applications shortcut.
- `LinguaBar-0.1.0-macos-arm64.zip` — the same signed app.
- `LinguaBar-0.1.0-source.tar.gz` — corresponding source, resources, tests and build scripts.
- `SHA256SUMS.txt` — SHA-256 checksums.

默认输出到 `dist/releases/`，不会覆盖已有 DMG/ZIP，也不会停止正在运行的应用。版本号来自 `Resources/Info.plist`。再次制作可指定新的输出目录：

```sh
RELEASE_OUTPUT_DIR="$PWD/dist/releases-next" ./script/release.sh
```

## Signing and notarization / 签名与公证

The script selects the first visible Developer ID Application identity. If multiple teams are installed, explicitly choose one using `SIGNING_IDENTITY`. Local Xcode compilation, Developer ID signing, and Apple notarization are separate steps.

当前脚本正式签名 App 和 DMG；仅检测到签名证书不代表已完成公证。配置过 `notarytool` 的钥匙串 profile 后，可执行：

```sh
NOTARY_PROFILE="your-existing-profile" RELEASE_OUTPUT_DIR="$PWD/dist/notarized" ./script/release.sh
```

This submits the app ZIP to Apple, staples the app, packages both formats, then submits and staples the DMG. Failed submission or stapling stops the release. Never place passwords, API private keys or certificate exports in this repository.

最终检查：

```sh
(cd dist/releases && shasum -a 256 -c SHA256SUMS.txt)
codesign --verify --deep --strict /path/to/LinguaBar.app
spctl --assess --type execute --verbose=2 /path/to/LinguaBar.app
xcrun stapler validate /path/to/LinguaBar.app
```

For checksum verification, change into the release output directory and run `shasum -a 256 -c SHA256SUMS.txt`.

## Publish a release / 发布新版本

Review the generated source archive before publishing: the script copies explicit top-level directories, so review their contents for credentials, local settings, build outputs and internal notes. Publish only the final source and deliverables.

1. Review both READMEs and the screenshots.
2. Retain LICENSE, THIRD_PARTY_NOTICES.md and upstream.lock.
3. Update the download links in both READMEs and the project website for the new version.
4. Upload DMG, ZIP, matching source archive and SHA256SUMS together.
5. State the actual signing/notarization outcome in the release description.
6. Test installation from a browser-downloaded DMG on a separate Mac.

发布安装包时同时提供对应源码、上游许可和校验和。公证确认分发信任，不代表已验证所有 Mac 上的功能与权限流程。

## Project website / 项目网站

The single-page site lives in `docs/index.html`, with local assets in `docs/images/`. GitHub Pages publishes `main` → `/docs`. It is plain HTML, CSS and JavaScript: no build step, external analytics or API credentials.

网页提供中英文切换，直接链接 GitHub Release。更新版本时同步检查网页和两份 README 中的下载链接。
