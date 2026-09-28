# LinguaBar 0.2.1

macOS 15+ · Apple Silicon (`arm64`) · v0.2.1 release / 0.2.1 正式版

## Downloads / 下载

- [Apple Silicon DMG](https://github.com/wangzheng422/linguabar/releases/download/v0.2.1/LinguaBar-0.2.1-macos-arm64.dmg)
- [ZIP app](https://github.com/wangzheng422/linguabar/releases/download/v0.2.1/LinguaBar-0.2.1-macos-arm64.zip)
- [Matching source archive](https://github.com/wangzheng422/linguabar/releases/download/v0.2.1/LinguaBar-0.2.1-source.tar.gz)
- [SHA256SUMS.txt](https://github.com/wangzheng422/linguabar/releases/download/v0.2.1/SHA256SUMS.txt)

## Update / 更新

- **More precise system-audio permission hint.** The output-activity check for this hint excludes LinguaBar's own live process tree. The capture tap's process selection and captured audio scope are unchanged. An output stream alone does not prove that sound is audible.
  **更准确的系统音频权限提示。** 判断是否显示此提示时会排除 LinguaBar 自身的实时进程树。采集 Tap 的进程选择和音频范围保持不变。检测到输出流本身并不能证明实际有可听声音。
- The v0.2.0 feature set is retained.
  保留 v0.2.0 的功能集。

## Distribution verification / 分发验证

The v0.2.1 app and DMG were accepted by Apple notarization and stapled on 2026-09-28. Gatekeeper accepts the app as **Notarized Developer ID**. The ZIP contains the notarized, stapled app. Verify downloads against `SHA256SUMS.txt`.

0.2.1 App 与 DMG 已于 2026-09-28 通过 Apple 公证并附加票据；Gatekeeper 将该 App 识别为 **Notarized Developer ID**。ZIP 内含已公证并附加票据的 App。下载后请使用 `SHA256SUMS.txt` 校验文件。
