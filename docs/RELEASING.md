# Release guide / 发行指南

<!-- AI-Author: Codex (OpenAI model not exposed by runtime) -->

## Build locally / 本机构建

Run on an Apple Silicon Mac with macOS 15+, Xcode's macOS SDK, and an accessible Developer ID Application certificate and private key:

在 Apple Silicon Mac 上运行，系统需为 macOS 15+，并安装 Xcode macOS SDK，同时可使用 Developer ID Application 证书和私钥：

```sh
./script/release.sh
```

The script builds the optimized Swift Release app, signs with hardened runtime and a secure timestamp, and creates:

- `LinguaBar-<version>-macos-arm64.dmg` — app plus an Applications shortcut / 应用及 Applications 快捷方式。
- `LinguaBar-<version>-macos-arm64.zip` — the same signed app / 同一份已签名应用。
- `LinguaBar-<version>-source.tar.gz` — matching source, resources, tests, and build scripts / 对应源码、资源、测试和构建脚本。
- `SHA256SUMS.txt` — SHA-256 checksums for those three files / 上述三个文件的 SHA-256 校验和。

The version comes from `Resources/Info.plist`. By default, files go to `dist/releases/`; existing DMG and ZIP files are not overwritten, and the running app is not stopped. To use another output directory:

版本号来自 `Resources/Info.plist`。默认输出到 `dist/releases/`；不会覆盖已有 DMG 或 ZIP，也不会停止正在运行的应用。可指定其他输出目录：

```sh
RELEASE_OUTPUT_DIR="$PWD/dist/releases-next" ./script/release.sh
```

## Signing and notarization / 签名与公证

The script selects the first visible Developer ID Application identity. If multiple teams are installed, choose one explicitly with `SIGNING_IDENTITY`. Local compilation, Developer ID signing, and Apple notarization are separate steps.

脚本默认选择第一个可见的 Developer ID Application 身份。如果安装了多个团队的证书，可通过 `SIGNING_IDENTITY` 明确指定。本机构建、Developer ID 签名和 Apple 公证是不同步骤。

Without `NOTARY_PROFILE`, the script creates a signed-only build. To submit the app and DMG to Apple, configure a `notarytool` keychain profile, then run:

未设置 `NOTARY_PROFILE` 时，脚本只生成签名版本。若要向 Apple 提交 App 和 DMG 进行公证，请先配置 `notarytool` 钥匙串 profile，再运行：

```sh
NOTARY_PROFILE="YOUR_NOTARYTOOL_KEYCHAIN_PROFILE" RELEASE_OUTPUT_DIR="$PWD/dist/notarized" ./script/release.sh
```

Replace the profile placeholder with the name of a profile already stored in your keychain. With the profile configured, the script submits the app ZIP, staples the accepted ticket to the app, builds the ZIP and DMG from that app, then submits and staples the DMG. Failed submission or stapling stops the release. Keep account passwords, API private keys, and certificate exports out of the repository.

将 profile 占位符替换为钥匙串中已保存的 profile 名称。配置后，脚本会提交 App ZIP、将获批票据附加到 App，再从该 App 制作 ZIP 和 DMG，之后提交并附加 DMG 票据。提交或附加失败时发行流程会停止。请勿将账户密码、API 私钥或证书导出文件放入仓库。

Verify the checksums from the output directory:

在输出目录中校验文件：

```sh
release_dir="${RELEASE_OUTPUT_DIR:-$PWD/dist/releases}"
(
  cd "$release_dir"
  shasum -a 256 -c SHA256SUMS.txt
)
```

Then verify the app and disk image at their actual paths:

然后使用实际路径检查 App 和磁盘映像：

```sh
codesign --verify --deep --strict "/path/to/LinguaBar.app"
spctl --assess --type execute --verbose=2 "/path/to/LinguaBar.app"
xcrun stapler validate "/path/to/LinguaBar.app"
xcrun stapler validate "$release_dir/LinguaBar-<version>-macos-arm64.dmg"
```

Replace `/path/to/LinguaBar.app` and `<version>` with the app and version produced by the build. Run stapler validation only for an artifact that was notarized and stapled.

将 `/path/to/LinguaBar.app` 和 `<version>` 替换为构建生成的 App 路径与版本号。仅对已完成公证并附加票据的产物运行 stapler 验证。

## Prepare a public GitHub release / 准备 GitHub 公开发行版

Use the existing public repository and create a release for the matching version tag. Before attaching artifacts:

在现有公开仓库中为对应版本标签创建 Release。上传产物前：

1. Review both READMEs and the screenshots. / 检查中英文 README 和截图。
2. Inspect the generated source archive. The build script uses an explicit allowlist: `Sources`, `Tests`, `Resources`, `script`, `docs`, `Package.swift`, both READMEs, `LICENSE`, `THIRD_PARTY_NOTICES.md`, and `upstream.lock`. / 检查源码包。构建脚本只打包明确列出的目录和文件：`Sources`、`Tests`、`Resources`、`script`、`docs`、`Package.swift`、两个 README、`LICENSE`、`THIRD_PARTY_NOTICES.md` 和 `upstream.lock`。
3. Attach the DMG, ZIP, matching source archive, and `SHA256SUMS.txt` to the same release. / 在同一 Release 中附上 DMG、ZIP、对应源码包和 `SHA256SUMS.txt`。
4. State the actual signing and notarization outcome in the release description. / 在 Release 说明中写明实际签名和公证结果。
5. Download the published DMG on a separate Mac and verify installation and first launch. / 在另一台 Mac 上下载 DMG，并验证安装和首次启动。

## Xcode Cloud

No Xcode Cloud workflow is configured for this Swift package. This release process uses local Xcode tools; the release script supports Developer ID signing and optional notarization.

此 Swift package 尚未配置 Xcode Cloud 工作流。本发行流程使用本机 Xcode 工具；发行脚本支持 Developer ID 签名和可选公证。
