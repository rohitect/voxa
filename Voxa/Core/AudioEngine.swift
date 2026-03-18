import AVFoundation
import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isInput: Bool
}

@Observable
final class AudioEngine {
    private let engine = AVAudioEngine()
    private let bufferQueue = DispatchQueue(label: "com.voxa.audioBuffer")
    private var audioBuffer: [Float] = []
    private var isRecording = false
    private var maxDurationTimer: Timer?

    var onAudioLevel: ((Float) -> Void)?
    var availableInputDevices: [AudioDevice] = []
    var selectedDeviceID: AudioDeviceID?

    init() {
        refreshDevices()
    }

    private static let selectedDeviceUIDKey = "selectedInputDeviceUID"

    // MARK: - Device Selection

    func refreshDevices() {
        availableInputDevices = Self.getInputDevices()

        // Restore saved device, fall back to system default
        if let savedUID = UserDefaults.standard.string(forKey: Self.selectedDeviceUIDKey),
           let saved = availableInputDevices.first(where: { $0.uid == savedUID }) {
            selectedDeviceID = saved.id
        } else if selectedDeviceID == nil {
            selectedDeviceID = Self.getDefaultInputDeviceID()
        }
    }

    func selectDevice(_ deviceID: AudioDeviceID) {
        selectedDeviceID = deviceID
        setSystemInputDevice(deviceID)

        // Persist by UID (stable across restarts, unlike AudioDeviceID)
        if let device = availableInputDevices.first(where: { $0.id == deviceID }) {
            UserDefaults.standard.set(device.uid, forKey: Self.selectedDeviceUIDKey)
            print("[AudioEngine] Selected device: \(device.name)")
        }
    }

    private func setSystemInputDevice(_ deviceID: AudioDeviceID) {
        // Set the audio engine's input device via CoreAudio
        let audioUnit = engine.inputNode.audioUnit!
        var deviceID = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }

        // Apply selected device before starting
        if let deviceID = selectedDeviceID {
            setSystemInputDevice(deviceID)
        }

        // Reset the engine to pick up device change
        engine.reset()

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.audioSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("[AudioEngine] Failed to create target format")
            return
        }

        let format: AVAudioFormat
        let converter: AVAudioConverter?

        if nativeFormat.sampleRate == Constants.audioSampleRate && nativeFormat.channelCount == 1 {
            format = nativeFormat
            converter = nil
        } else {
            format = nativeFormat
            converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        }

        bufferQueue.sync {
            audioBuffer.removeAll()
        }

        inputNode.installTap(onBus: 0, bufferSize: Constants.audioBufferSize, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            let samples: [Float]

            if let converter {
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * Constants.audioSampleRate / nativeFormat.sampleRate
                )
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: frameCount
                ) else { return }

                var error: NSError?
                var hasData = true
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if hasData {
                        hasData = false
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    outStatus.pointee = .noDataNow
                    return nil
                }

                if let error {
                    print("[AudioEngine] Conversion error: \(error)")
                    return
                }

                guard let channelData = convertedBuffer.floatChannelData else { return }
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
            } else {
                guard let channelData = buffer.floatChannelData else { return }
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
            }

            let rms = Self.calculateRMS(samples)

            DispatchQueue.main.async {
                self.onAudioLevel?(rms)
            }

            self.bufferQueue.async {
                self.audioBuffer.append(contentsOf: samples)
            }
        }

        do {
            try engine.start()
            isRecording = true
            let deviceName = availableInputDevices.first { $0.id == selectedDeviceID }?.name ?? "default"
            print("[AudioEngine] Recording started (\(deviceName), native: \(nativeFormat.sampleRate)Hz \(nativeFormat.channelCount)ch)")

            maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Constants.maxRecordingDuration, repeats: false) { [weak self] _ in
                print("[AudioEngine] Max recording duration reached (\(Constants.maxRecordingDuration)s)")
                self?.stopRecording()
            }
        } catch {
            print("[AudioEngine] Failed to start: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        let sampleCount: Int = bufferQueue.sync { audioBuffer.count }
        let duration = Double(sampleCount) / Constants.audioSampleRate
        print("[AudioEngine] Recording stopped — captured \(sampleCount) samples (\(String(format: "%.1f", duration))s)")
    }

    func getBufferAndClear() -> [Float] {
        bufferQueue.sync {
            let buffer = audioBuffer
            audioBuffer.removeAll()
            return buffer
        }
    }

    // MARK: - Helpers

    private static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    // MARK: - CoreAudio Device Enumeration

    private static func getDefaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    private static func getInputDevices() -> [AudioDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { id -> AudioDevice? in
            // Check if device has input streams
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else {
                return nil
            }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr else {
                return nil
            }

            // Get device UID (stable identifier)
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uid) == noErr else {
                return nil
            }

            return AudioDevice(id: id, uid: uid as String, name: name as String, isInput: true)
        }
    }
}
