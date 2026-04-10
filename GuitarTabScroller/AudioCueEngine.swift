import Foundation
import AVFoundation
import Accelerate

/// Listens to the mic and fires `onCueDetected` when the live audio matches a recorded template.
/// Approach: compute a normalized log-magnitude spectrum (32 bands) from a short window,
/// compare against the template via cosine similarity, gate on energy, and cool down after a hit.
final class AudioCueEngine {
    var onCueDetected: (() -> Void)?
    var onCueRecorded: (() -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let bus: AVAudioNodeBus = 0
    private let bufferSize: AVAudioFrameCount = 2048
    private let bandCount = 32

    private var template: [Float]?
    private var pendingRecord = false
    private var listening = false
    private var lastFireTime: CFTimeInterval = 0
    private let cooldown: CFTimeInterval = 0.8
    var threshold: Float = 0.88
    private var consecutiveMatches = 0
    private let requiredMatches = 2
    private var templateRMS: Float = 0

    // FFT
    private lazy var log2n: vDSP_Length = vDSP_Length(log2(Float(bufferSize)))
    private lazy var fftSetup: FFTSetup? = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

    init() {
        installTapIfNeeded()
    }

    deinit {
        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
    }

    private func installTapIfNeeded() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: bus)
        input.installTap(onBus: bus, bufferSize: bufferSize, format: format) { [weak self] buf, _ in
            self?.process(buffer: buf)
        }
    }

    func startListening() {
        guard !engine.isRunning else { listening = true; return }
        do {
            try engine.start()
            listening = true
        } catch {
            print("Audio engine failed: \(error)")
        }
    }

    func stopListening() {
        listening = false
        // Keep engine running if a recording is pending; otherwise stop
        if !pendingRecord && engine.isRunning {
            engine.stop()
        }
    }

    func recordCue() {
        pendingRecord = true
        if !engine.isRunning {
            do { try engine.start() } catch { print(error) }
        }
    }

    // MARK: - Processing
    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= Int(bufferSize) else { return }

        // RMS for level + energy gate
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(bufferSize))
        onLevel?(min(rms * 8, 1))

        // Compute spectrum features
        guard let features = spectralFeatures(channelData: channelData) else { return }

        if pendingRecord {
            // Require some energy so we don't capture silence
            if rms > 0.02 {
                template = features
                templateRMS = rms
                pendingRecord = false
                onCueRecorded?()
            }
            return
        }

        guard listening, let template else { return }
        // Loudness gate: must be at least 50% as loud as the recorded cue
        guard rms > max(0.02, templateRMS * 0.5) else {
            consecutiveMatches = 0
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastFireTime > cooldown else { return }

        let sim = cosineSimilarity(features, template)
        if sim >= threshold {
            consecutiveMatches += 1
            if consecutiveMatches >= requiredMatches {
                lastFireTime = now
                consecutiveMatches = 0
                onCueDetected?()
            }
        } else {
            consecutiveMatches = 0
        }
    }

    private func spectralFeatures(channelData: UnsafePointer<Float>) -> [Float]? {
        guard let fftSetup else { return nil }
        let n = Int(bufferSize)
        let halfN = n / 2

        // Hann window
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(channelData, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        realp.withUnsafeMutableBufferPointer { rPtr in
            imagp.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfN))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Log compress
        var one: Float = 1
        vDSP_vsadd(magnitudes, 1, &one, &magnitudes, 1, vDSP_Length(halfN))
        var count = Int32(halfN)
        vvlogf(&magnitudes, magnitudes, &count)

        // Bin into bandCount bands (linear)
        // Bin into bandCount bands (linear)
        var bands = [Float](repeating: 0, count: bandCount)
        let perBand = halfN / bandCount
        magnitudes.withUnsafeBufferPointer { magPtr in
            for b in 0..<bandCount {
                var sum: Float = 0
                vDSP_sve(magPtr.baseAddress! + b * perBand, 1, &sum, vDSP_Length(perBand))
                bands[b] = sum / Float(perBand)
            }
        }

        // L2 normalize
        var norm: Float = 0
        vDSP_svesq(bands, 1, &norm, vDSP_Length(bandCount))
        norm = sqrt(norm)
        if norm > 0 {
            var inv = 1 / norm
            vDSP_vsmul(bands, 1, &inv, &bands, 1, vDSP_Length(bandCount))
        }
        return bands
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot // both are L2-normalized
    }
}
