# API Notes & Spike Confirmations

This document records the exact confirmed API signatures and behavior discovered during the P0.2 spike (`Spikes/ApiCheck`) against Xcode 27.2 / macOS 26+ SDK and `argmax-oss-swift` v1.1.1.

---

## 1. CoreAudio & Process Tapping (§23, §25.6)

### 1.1 Process Tap Creation & Lifecycle
- `CATapDescription(monoMixdownOfProcesses: [AudioObjectID])`:
  - Defined in `CoreAudio/CATapDescription.h` (refined for Swift from `initMonoMixdownOfProcesses:`).
  - Configurable properties:
    - `desc.uuid = UUID()` (maps to `UUID` / `NSUUID`)
    - `desc.muteBehavior = .unmuted`
    - `desc.isPrivate = true` (Obj-C property `privateTap`)
- `AudioHardwareCreateProcessTap(_ inDescription: CATapDescription, _ outTapID: UnsafeMutablePointer<AudioObjectID>) -> OSStatus`:
  - Header: `CoreAudio/AudioHardwareTapping.h`
- `AudioHardwareDestroyProcessTap(_ inTapID: AudioObjectID) -> OSStatus`:
  - Header: `CoreAudio/AudioHardwareTapping.h`

### 1.2 Selectors & Property Addresses
- `kAudioTapPropertyFormat` (`'tfmt'`): Read stream format (`AudioStreamBasicDescription`) from `tapID`.
- `kAudioHardwarePropertyTranslatePIDToProcessObject` (`'id2p'`): Translate PID to process `AudioObjectID`.
- `kAudioProcessPropertyPID` (`'ppid'`): Read `pid_t` from process `AudioObjectID`.
- `kAudioProcessPropertyBundleID` (`'pbid'`): Read `CFString` bundle ID from process `AudioObjectID`.
- `kAudioProcessPropertyIsRunningOutput` (`'piro'`): Read `UInt32` boolean for active audio output.

### 1.3 Aggregate Device Creation & Tap I/O
- `AudioHardwareCreateAggregateDevice(_ inDescription: CFDictionary, _ outDeviceID: UnsafeMutablePointer<AudioObjectID>) -> OSStatus`
- Keys in aggregate description:
  - `kAudioAggregateDeviceNameKey` (`"name"`)
  - `kAudioAggregateDeviceUIDKey` (`"uid"`)
  - `kAudioAggregateDeviceMainSubDeviceKey` (`"master"`)
  - `kAudioAggregateDeviceIsPrivateKey` (`"private"`)
  - `kAudioAggregateDeviceTapListKey` (`"taps"`)
  - `kAudioAggregateDeviceSubDeviceListKey` (`"subdevices"`)
  - `kAudioSubTapDriftCompensationKey` (`"drift"`)
  - `kAudioSubTapUIDKey` (`"uid"`)
- `AudioDeviceCreateIOProcIDWithBlock(_ outIOProcID: UnsafeMutablePointer<AudioDeviceIOProcID?>, _ inDevice: AudioObjectID, _ inDispatchQueue: DispatchQueue?, _ inIOBlock: @escaping AudioDeviceIOBlock) -> OSStatus`:
  - 5-argument block signature:
    `typealias AudioDeviceIOBlock = (UnsafePointer<AudioTimeStamp>, UnsafePointer<AudioBufferList>, UnsafePointer<AudioTimeStamp>, UnsafeMutablePointer<AudioBufferList>, UnsafePointer<AudioTimeStamp>) -> Void`
- `AudioDeviceStart(_ inDevice: AudioObjectID, _ inProcID: AudioDeviceIOProcID?) -> OSStatus`
- `AudioDeviceStop(_ inDevice: AudioObjectID, _ inProcID: AudioDeviceIOProcID?) -> OSStatus`
- `AudioDeviceDestroyIOProcID(_ inDevice: AudioObjectID, _ inProcID: AudioDeviceIOProcID) -> OSStatus`
- `AudioHardwareDestroyAggregateDevice(_ inDeviceID: AudioObjectID) -> OSStatus`

---

## 2. Mic Input & Audio File I/O (§25.6, §25.7)

### 2.1 Microphone Tap & Input Device Selection
- `AVAudioEngine`:
  - `engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in ... }`
  - `when.hostTime`: `UInt64` host clock timestamp for precise time alignment.
- Selected device routing:
  - `AudioUnitSetProperty(engine.inputNode.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))`

### 2.2 Audio File Formats & Resampling
- Linear PCM Int16 `.caf`:
  - `AVFormatIDKey: kAudioFormatLinearPCM`
  - `AVSampleRateKey: 48000.0`
  - `AVNumberOfChannelsKey: 1`
  - `AVLinearPCMBitDepthKey: 16`
  - `AVLinearPCMIsFloatKey: false`
- Stereo AAC `.m4a`:
  - `AVFormatIDKey: kAudioFormatMPEG4AAC`
  - `AVSampleRateKey: 48000.0`
  - `AVNumberOfChannelsKey: 2`
  - `AVEncoderBitRateKey: 128000`
- `AVAudioConverter(from: inFormat, to: outFormat)` for sample rate conversions.

---

## 3. Realtime & Synchronization (§23, §25.1)

### 3.1 Synchronization.Atomic
- `import Synchronization`
- `Atomic<Int>`:
  - `.load(ordering: .relaxed)`
  - `.store(_:ordering: .relaxed)`
  - `.wrappingAdd(_:ordering: .relaxed)`

---

## 4. Transcription / WhisperKit (§23, §26.3)

- Package URL: `https://github.com/argmaxinc/argmax-oss-swift.git` (resolved at 1.1.1)
- Product: `WhisperKit`
- `WhisperKitConfig(model: String)`
- `WhisperKit(_ config: WhisperKitConfig) async throws`
- Transcribe:
  ```swift
  kit.transcribe(
      audioPath: String,
      audioInputOptions: AudioInputOptions?,
      decodeOptions: DecodingOptions?,
      callback: TranscriptionCallback?
  ) async throws -> [TranscriptionResult]
  ```
- `DecodingOptions`:
  - `chunkingStrategy: ChunkingStrategy?` (e.g. `.vad`)
  - `wordTimestamps: Bool`
  - `promptTokens: [Int]?`
- Incremental loading:
  - `AudioInputOptions(audioLoadingMode: .incremental)`
- Result segments:
  - `results.flatMap(\.segments)` yields `TranscriptionSegment` with `.start` (`Float`), `.end` (`Float`), `.text` (`String`).

---

## 5. Foundation Models / Apple Intelligence (§23, §27.4)

### 5.1 System Language Model & Availability
- `import FoundationModels`
- `SystemLanguageModel.default.availability`:
  - `.available`
  - `.unavailable(SystemLanguageModel.Availability.UnavailableReason)`:
    - `.deviceNotEligible`
    - `.appleIntelligenceNotEnabled`
    - `.modelNotReady`
- `SystemLanguageModel.default.contextSize`: `Int`
- `SystemLanguageModel.default.tokenCount(for: String) async throws -> Int`:
  - **Availability Note:** Introduced in macOS 26.4. On earlier macOS 26 versions, use fallback `ceil(chars / 3.0)`.

### 5.2 Structured Generation
- `@Generable` struct decoration with `@Guide(description: String)` fields.
- `LanguageModelSession(instructions: String?)`
- `session.respond(to: String, generating: T.self) async throws -> Response<T>` where `T: Generable`
- Response content: `response.content` (`T`)

### 5.3 Error Handling
- `LanguageModelSession.GenerationError`:
  - `.exceededContextWindowSize`
  - `.guardrailViolation`
  - `.refusal`
  - `.rateLimited`
  - `.assetsUnavailable`
  - `.unsupportedGuide`
  - `.unsupportedLanguageOrLocale`
  - `.decodingFailure`
  - `.concurrentRequests`
