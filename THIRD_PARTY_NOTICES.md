<!-- AI-Author: Codex (OpenAI model not exposed by runtime) -->
# Third-party notices / 第三方来源声明

LinguaBar's `Sources/LinguaBar/Services/CoreAudioProcessTap.swift` derives from Sokuji's `native/audio-host/mac/main.swift`.

- Project: https://github.com/kizuna-ai-lab/sokuji
- Original derivation: `87c7f03ffad800fd81cb453bed881c87725c1336`
- Reviewed upstream revision: `821a641ecb510d591b3e8b542bfbf798c80f0f9c` (macOS audio-host fixes synchronized).
- License: GNU Affero General Public License, version 3; see [LICENSE](LICENSE).
- Original copyright and authorship remain with the respective Sokuji contributors. LinguaBar contributions are recorded in source comments.

Changes include a SwiftUI/AppKit interface, Apple Speech and Translation integration, meeting application selection, process-tree capture adaptation, persistent preferences, subtitle history, and display controls.

The rendering-activity diagnostic in `CoreAudioProcessTap.swift` and `AudioRenderingActivity.swift` incorporates upstream fixes `186be6f1e9cbca7ff9aa1fc3c287884885e4704c` and `419208fd2e208adaf3dfefa6b085334094aaa6f3`: exclude the app's own live process tree from the silent-capture permission hint. This does not exclude audio from the actual capture tap. Sokuji's Electron IPC/CLI, TTS, and other inference engines are not imported into LinguaBar.

LinguaBar 的采集代码由上述 Sokuji 文件改写；保留原作者权益和 AGPL v3 许可。发布二进制时请同时提供对应源码。Apple 系统框架由系统提供，不随源码包重新分发。
