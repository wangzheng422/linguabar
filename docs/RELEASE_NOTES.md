# LinguaBar 0.2.3

- 修复上一段的实时翻译任务断开后，下一段可能只有英文转写、没有中文译文的问题。每次开始监听都会重新连接翻译任务。
- Fix missing Chinese captions in a subsequent listening session after the previous live translation task disconnects. LinguaBar reconnects live translation at each session start.

[下载 / Downloads](https://github.com/wangzheng422/linguabar/releases/tag/v0.2.3)

## LinguaBar 0.2.2

macOS 15+ · Apple Silicon (`arm64`)

- 实时翻译在连续转写期间持续更新。 Live translations now appear during continuous transcription.
- 复用实时翻译会话。归档落盘后释放全文内存。 Live translation sessions are reused, and saved archives release in-memory transcript payloads.
- 静音采集提示显示默认音频输出和连接类型。 Silent-capture diagnostics include the default output device and transport.

[下载 / Downloads](https://github.com/wangzheng422/linguabar/releases/tag/v0.2.2)

## LinguaBar 0.2.1

<!-- AI-Author: Codex (OpenAI model not exposed by runtime) -->

macOS 15+ · Apple Silicon (`arm64`) · v0.2.1 release / 0.2.1 正式版

## Downloads / 下载

- [Apple Silicon DMG](https://github.com/wangzheng422/linguabar/releases/download/v0.2.1/LinguaBar-0.2.1-macos-arm64.dmg)
- [ZIP app](https://github.com/wangzheng422/linguabar/releases/download/v0.2.1/LinguaBar-0.2.1-macos-arm64.zip)
- [Matching source archive](https://github.com/wangzheng422/linguabar/releases/download/v0.2.1/LinguaBar-0.2.1-source.tar.gz)
- [SHA256SUMS.txt](https://github.com/wangzheng422/linguabar/releases/download/v0.2.1/SHA256SUMS.txt)

- Details about this update and package verification are in the [v0.2.1 release notes](RELEASE_NOTES_0.2.1.md).
  更新内容与软件包验证详见 [v0.2.1 发布说明](RELEASE_NOTES_0.2.1.md)。

## Previous release / 上一版本

# LinguaBar 0.2.0

<!-- AI-Author: Codex (OpenAI model not exposed by runtime) -->

macOS 15+ · Apple Silicon (`arm64`) · v0.2.0 release / 0.2.0 正式版

## Downloads / 下载

- [Apple Silicon DMG](https://github.com/wangzheng422/linguabar/releases/download/v0.2.0/LinguaBar-0.2.0-macos-arm64.dmg)
- [ZIP app](https://github.com/wangzheng422/linguabar/releases/download/v0.2.0/LinguaBar-0.2.0-macos-arm64.zip)
- [Matching source archive](https://github.com/wangzheng422/linguabar/releases/download/v0.2.0/LinguaBar-0.2.0-source.tar.gz)
- [SHA256SUMS.txt](https://github.com/wangzheng422/linguabar/releases/download/v0.2.0/SHA256SUMS.txt)

## What's new / 更新内容

- **Clear and short screen retention.** Clear removes transcript text from the display. Old screen text also expires after ten minutes. Neither action deletes text collected for the complete session archive.
  **清空与短期屏幕保留。** 清空会移除屏幕上的字幕；旧字幕也会在十分钟后过期。这两种操作都不会删除本场归档已收集的文字。
- **A status-aware flat Dock icon.** The icon shows permission, listening, warning, and capture-failure states, then returns to its plain appearance when idle. Its marker reports capture state, not whether speech or translation is arriving.
  **状态 Dock 图标。** 扁平图标会显示权限请求、监听、警告和采集失败状态，空闲时恢复普通外观。标记仅代表采集状态，不代表一定收到语音或翻译结果。
- **Complete text archives.** Stopping a non-empty session saves the full original transcript under `Documents/LinguaBar/Original`. English and Korean sessions also get a full Chinese translation under `Documents/LinguaBar/Chinese`; Chinese input creates an Original file only. The original is written first, so a translation failure does not lose it. Full-session translation may differ from the live preview.
  **完整文字归档。** 停止非空场次后，完整原文会保存到 `Documents/LinguaBar/Original`。英文和韩文场次还会在 `Documents/LinguaBar/Chinese` 保存完整中文翻译；中文输入只生成 Original 文件。系统先写入原文，因此翻译失败不会丢失原文。全文翻译措辞可能与实时预览不同。
- **Safer, more useful filenames.** Names combine the session's local start time with a sanitized English keyword summary. Korean and Chinese sessions use optional, best-effort on-device translation to form an English summary; if translation is unavailable or yields no usable keywords, the summary falls back to `meeting-notes`. Numeric suffixes prevent collisions from overwriting existing files.
  **更安全实用的文件名。** 文件名由本地开始时间和经过清理的英文关键词摘要组成。韩文和中文场次会尽力使用可选的设备端翻译生成英文摘要；翻译不可用或没有可用关键词时回退为 `meeting-notes`。同名文件追加数字后缀，避免覆盖。
- **No saved audio.** LinguaBar stores session text, not audio recordings. Apple Speech may use Apple's servers depending on language and system support; recognition is not forced offline. Saved text can sync if the Documents folder is cloud-synced.
  **不保存录音。** LinguaBar 保存场次文字，不保存音频。Apple Speech 是否使用苹果服务器取决于语言和系统支持；应用不会强制离线识别。若文稿目录开启云同步，文字文件也可能同步。

## Distribution verification / 分发验证

The app and DMG were accepted by Apple notarization and stapled on 2026-09-28. Gatekeeper accepts the app as **Notarized Developer ID**. The ZIP contains the notarized, stapled app. Verify downloads against `SHA256SUMS.txt`.

App 与 DMG 已于 2026-09-28 通过 Apple 公证并附加票据。Gatekeeper 将该 App 识别为 **Notarized Developer ID**。ZIP 内含已公证并附加票据的 App。下载后请使用 `SHA256SUMS.txt` 校验文件。

## Known limitations / 已知限制

- Apple Silicon only; Intel is not included or validated.
- Chrome capture follows the Chrome process tree and can include audio from other tabs, not only Meet.
- Apple Speech is not forced offline; language downloads or macOS permission prompts may be required.
- Pause-based punctuation is approximate.
- Stop captions before changing the capture source or language.
- 仅支持 Apple Silicon；未包含或验证 Intel 版本。
- Chrome 采集按 Chrome 进程树进行，可能捕获其他标签页音频，不只限于 Meet。
- Apple Speech 不保证离线；可能需要下载语言资源或响应 macOS 权限提示。
- 按停顿补充标点属于近似处理。
- 更改采集来源或语言前，请先停止字幕。

## Previous release / 上一版本

### LinguaBar 0.1.0

Initial preview release. Native live captions for Google Meet, Chrome, Teams, and system audio; English and Korean transcription with Chinese translation; and Chinese transcription-only mode. It included adjustable split panes, font size, background opacity, persistent preferences, bounded history, and scroll following.

0.1.0 首个预览版：原生实时字幕支持 Google Meet、Chrome、Teams 和系统音频；英文及韩文转写并翻译成中文，中文仅转写；支持分栏、字号、背景透明度、偏好记忆、历史上限和滚动跟随。

The 0.1.0 app and DMG were Developer ID signed, accepted by Apple notarization, and stapled on 2026-09-05. Version 0.2.0 supersedes that preview release.

0.1.0 App 与 DMG 已完成 Developer ID 签名，并于 2026-09-05 通过 Apple 公证、附加公证票据。0.2.0 已取代该预览版。
