// AI-Author: Codex (OpenAI gpt-5.6-sol)
// Adapted from kizuna-ai-lab/sokuji native/audio-host/mac/main.swift at
// 87c7f03ffad800fd81cb453bed881c87725c1336 (AGPL-3.0).
// Rendering diagnostics synchronized through upstream
// 821a641ecb510d591b3e8b542bfbf798c80f0f9c; capture scope remains unchanged.
import AppKit
import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

enum CoreAudioTapError: LocalizedError {
    case unsupported
    case processUnavailable
    case tapCreation(OSStatus)
    case aggregateCreation(OSStatus)
    case formatUnavailable
    case ioCreation(OSStatus)
    case start(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupported: return "系统音频捕获需要 macOS 14.2 或更高版本。"
        case .processUnavailable: return "所选会议应用已经退出，请刷新音频源。"
        case .tapCreation(let status): return "无法创建系统音频 Tap（\(status)）。"
        case .aggregateCreation(let status): return "无法创建音频聚合设备（\(status)）。"
        case .formatUnavailable: return "无法读取系统音频格式。"
        case .ioCreation(let status): return "无法建立系统音频回调（\(status)）。"
        case .start(let status): return "无法启动系统音频捕获（\(status)）。"
        }
    }
}

private func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

private func audioObjectIDs(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var address = globalAddress(selector)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
          size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return [] }
    var identifiers = [AudioObjectID](
        repeating: 0,
        count: Int(size) / MemoryLayout<AudioObjectID>.size
    )
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &identifiers) == noErr
    else { return [] }
    return identifiers
}

private func processID(of object: AudioObjectID) -> pid_t? {
    var address = globalAddress(kAudioProcessPropertyPID)
    var processID: pid_t = 0
    var size = UInt32(MemoryLayout<pid_t>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &processID) == noErr
    else { return nil }
    return processID
}

private func boolProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
    var address = globalAddress(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
        && value != 0
}

private func stringProperty(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector
) -> String? {
    var address = globalAddress(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    guard status == noErr, let value else { return nil }
    return value as String
}

// Adapted from Sokuji's Core Audio output device diagnostics (3f0542afdba5).
func defaultOutputDeviceDiagnostic() -> String? {
    var address = globalAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
          device != kAudioObjectUnknown,
          let name = stringProperty(device, kAudioObjectPropertyName), !name.isEmpty else { return nil }

    address = globalAddress(kAudioDevicePropertyTransportType)
    var transport: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return name }
    let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: transport >> $0) }
    let code = bytes.allSatisfy { (0x20...0x7E).contains($0) }
        ? String(decoding: bytes, as: UTF8.self) : String(transport)
    return "\(name)（\(code)）"
}

private func parentProcessID(of processID: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processID]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
    return info.kp_eproc.e_ppid
}

private func audioObjects(inProcessTree rootProcessID: pid_t) -> [AudioObjectID] {
    audioObjectIDs(kAudioHardwarePropertyProcessObjectList).sorted().filter { object in
        guard var current = processID(of: object) else { return false }
        for _ in 0..<8 {
            if current == rootProcessID { return true }
            if current <= 1 { return false }
            current = parentProcessID(of: current)
        }
        return false
    }
}

private func isRendering(_ objects: [AudioObjectID], excluding roots: Set<pid_t> = []) -> Bool {
    AudioRenderingActivity.isRendering(
        objects,
        excluding: roots,
        processID: processID(of:),
        parentProcessID: parentProcessID(of:),
        isRunningOutput: { boolProperty($0, kAudioProcessPropertyIsRunningOutput) }
    )
}

@available(macOS 14.2, *)
func makeTapDescription(
    processes: [AudioObjectID]?,
    identifier: UUID
) -> CATapDescription {
    let description = processes.map { CATapDescription(monoMixdownOfProcesses: $0) }
        ?? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    description.uuid = identifier
    description.name = "LinguaBar Meeting Audio"
    description.isPrivate = true
    return description
}

@available(macOS 14.2, *)
private func retargetTap(
    _ tapID: AudioObjectID,
    processes: [AudioObjectID],
    identifier: UUID
) -> OSStatus {
    var address = globalAddress(kAudioTapPropertyDescription)
    var boxed: CATapDescription? = makeTapDescription(
        processes: processes,
        identifier: identifier
    )
    return withUnsafeMutablePointer(to: &boxed) {
        AudioObjectSetPropertyData(
            tapID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<CATapDescription?>.size),
            $0
        )
    }
}

private func inputFormat(of aggregateID: AudioObjectID) -> AVAudioFormat? {
    var streamsAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(aggregateID, &streamsAddress, 0, nil, &size) == noErr,
          size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return nil }
    var streamIDs = [AudioObjectID](
        repeating: 0,
        count: Int(size) / MemoryLayout<AudioObjectID>.size
    )
    guard AudioObjectGetPropertyData(
        aggregateID,
        &streamsAddress,
        0,
        nil,
        &size,
        &streamIDs
    ) == noErr, let first = streamIDs.first else { return nil }

    var formatAddress = globalAddress(kAudioStreamPropertyVirtualFormat)
    var description = AudioStreamBasicDescription()
    var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioObjectGetPropertyData(
        first,
        &formatAddress,
        0,
        nil,
        &formatSize,
        &description
    ) == noErr, description.mSampleRate > 0 else { return nil }

    return AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: description.mSampleRate,
        channels: 1,
        interleaved: false
    )
}

final class CoreAudioProcessTap: @unchecked Sendable {
    typealias AudioHandler = (AVAudioPCMBuffer) -> Void
    typealias WarningHandler = (String) -> Void

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcessID: AudioDeviceIOProcID?
    private var retargetTimer: DispatchSourceTimer?
    private var targetProcessID: pid_t?
    private var currentProcessObjects: [AudioObjectID] = []
    private var tapUUID = UUID()
    private var sawNonZeroAudio = false
    private var warnedAboutPermission = false
    private var startedAt = Date()
    private var renderingSince: Date?

    static func availableSources() -> [AudioSource] {
        var sources: [AudioSource] = [.system]
        let ownProcessID = getpid()
        let applications = NSWorkspace.shared.runningApplications
        let chromeProcessID = applications.first {
            $0.bundleIdentifier == "com.google.Chrome"
        }?.processIdentifier

        // Enumerate user-facing applications rather than only current audio
        // objects. Meet and Chromium create audio helpers lazily, so an
        // audio-object-only list can miss them before a call starts playing.
        for application in applications {
            let processID = application.processIdentifier
            guard processID != ownProcessID,
                  application.activationPolicy == .regular,
                  let label = application.localizedName,
                  !label.isEmpty else { continue }

            let bundleIdentifier = application.bundleIdentifier
            guard AudioSource.isMeetingApp(
                label: label,
                bundleIdentifier: bundleIdentifier
            ) else { continue }

            // Chrome PWAs are tiny app_mode_loader processes re-parented to
            // launchd; their audio service remains in the main Chrome tree.
            // Keep the Meet label, but tap Chrome so meeting sound is included.
            let captureProcessID: pid_t
            if bundleIdentifier?.hasPrefix("com.google.Chrome.app.") == true,
               let chromeProcessID {
                captureProcessID = chromeProcessID
            } else {
                captureProcessID = processID
            }
            let tree = audioObjects(inProcessTree: captureProcessID)
            sources.append(AudioSource(
                id: "pid:\(processID)",
                label: label,
                bundleIdentifier: bundleIdentifier,
                isActive: isRendering(tree),
                target: .process(captureProcessID)
            ))
        }

        let unique = Dictionary(grouping: sources, by: \.id).compactMap(\.value.first)
        return AudioSource.menuCandidates(from: unique)
    }

    func start(
        source: AudioSource,
        onAudio: @escaping AudioHandler,
        onWarning: @escaping WarningHandler
    ) throws {
        guard #available(macOS 14.2, *) else { throw CoreAudioTapError.unsupported }
        stop()

        switch source.target {
        case .system:
            targetProcessID = nil
            currentProcessObjects = []
        case .process(let processID):
            guard kill(processID, 0) == 0 || errno != ESRCH else {
                throw CoreAudioTapError.processUnavailable
            }
            targetProcessID = processID
            currentProcessObjects = audioObjects(inProcessTree: processID)
        case .unavailable:
            throw CoreAudioTapError.processUnavailable
        }

        tapUUID = UUID()
        let description = makeTapDescription(
            processes: targetProcessID == nil ? nil : currentProcessObjects,
            identifier: tapUUID
        )
        var newTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr else { throw CoreAudioTapError.tapCreation(tapStatus) }
        tapID = newTapID

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LinguaBar Meeting Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]
        var newAggregateID: AudioObjectID = 0
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &newAggregateID
        )
        guard aggregateStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
            throw CoreAudioTapError.aggregateCreation(aggregateStatus)
        }
        aggregateID = newAggregateID

        guard let monoFormat = inputFormat(of: aggregateID) else {
            stop()
            throw CoreAudioTapError.formatUnavailable
        }

        var newIOProcessID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newIOProcessID,
            aggregateID,
            nil
        ) { [weak self] _, inputData, _, _, _ in
            guard let self else { return }
            let buffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inputData)
            )
            guard let sourceBuffer = buffers.first,
                  let rawData = sourceBuffer.mData else { return }
            let sampleCount = Int(sourceBuffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else { return }
            let input = rawData.assumingMemoryBound(to: Float.self)
            let inputChannels = max(1, Int(sourceBuffer.mNumberChannels))
            let frameCount = sampleCount / inputChannels
            guard frameCount > 0,
                  let pcm = AVAudioPCMBuffer(
                    pcmFormat: monoFormat,
                    frameCapacity: AVAudioFrameCount(frameCount)
                  ), let output = pcm.floatChannelData?[0] else { return }

            var foundSignal = false
            if inputChannels == 1 {
                for frame in 0..<frameCount {
                    output[frame] = input[frame]
                    foundSignal = foundSignal || input[frame] != 0
                }
            } else {
                for frame in 0..<frameCount {
                    var mixed: Float = 0
                    for channel in 0..<inputChannels {
                        mixed += input[(frame * inputChannels) + channel]
                    }
                    output[frame] = mixed / Float(inputChannels)
                    foundSignal = foundSignal || output[frame] != 0
                }
            }
            pcm.frameLength = AVAudioFrameCount(frameCount)
            if foundSignal { self.sawNonZeroAudio = true }
            onAudio(pcm)
        }
        guard ioStatus == noErr, let newIOProcessID else {
            stop()
            throw CoreAudioTapError.ioCreation(ioStatus)
        }
        ioProcessID = newIOProcessID

        let startStatus = AudioDeviceStart(aggregateID, newIOProcessID)
        guard startStatus == noErr else {
            stop()
            throw CoreAudioTapError.start(startStatus)
        }

        sawNonZeroAudio = false
        warnedAboutPermission = false
        startedAt = Date()
        renderingSince = nil
        startRetargetAndPermissionMonitor(onWarning: onWarning)
    }

    func stop() {
        retargetTimer?.cancel()
        retargetTimer = nil
        if aggregateID != 0, let ioProcessID {
            AudioDeviceStop(aggregateID, ioProcessID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcessID)
        }
        ioProcessID = nil
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = 0
        tapID = 0
        targetProcessID = nil
        currentProcessObjects = []
    }

    private func startRetargetAndPermissionMonitor(onWarning: @escaping WarningHandler) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.monitor(onWarning: onWarning) }
        timer.resume()
        retargetTimer = timer
    }

    private func monitor(onWarning: WarningHandler) {
        guard tapID != 0 else { return }
        if let targetProcessID {
            guard kill(targetProcessID, 0) == 0 || errno != ESRCH else {
                onWarning("会议应用已经退出，请选择系统音频或刷新音频源。")
                return
            }
            let latest = audioObjects(inProcessTree: targetProcessID)
            if latest != currentProcessObjects,
               retargetTap(tapID, processes: latest, identifier: tapUUID) == noErr {
                currentProcessObjects = latest
            }
        }

        let rendering: Bool
        if targetProcessID == nil {
            rendering = isRendering(
                audioObjectIDs(kAudioHardwarePropertyProcessObjectList), excluding: [getpid()]
            )
        } else {
            rendering = !currentProcessObjects.isEmpty
                && isRendering(currentProcessObjects, excluding: [getpid()])
        }
        if rendering {
            if renderingSince == nil { renderingSince = Date() }
        } else {
            renderingSince = nil
        }

        let renderingLongEnough = renderingSince.map {
            Date().timeIntervalSince($0) > 2
        } ?? false
        if !warnedAboutPermission,
           !sawNonZeroAudio,
           Date().timeIntervalSince(startedAt) > 3,
           renderingLongEnough {
            warnedAboutPermission = true
            let output = defaultOutputDeviceDiagnostic().map { "当前默认输出：\($0)。" } ?? ""
            onWarning("检测到输出音频流，但采集持续静音（也可能尚未发声）。\(output)若确认有声音，请检查 LinguaBar 的系统音频录制权限。")
        }
    }

    deinit { stop() }
}
