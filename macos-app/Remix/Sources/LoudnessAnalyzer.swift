import Foundation
import AVFoundation
import Accelerate

struct LoudnessResult {
    let integratedLUFS: Float
    let peakLinear: Float
}

enum LoudnessAnalyzer {
    static func analyze(buffer: AVAudioPCMBuffer) -> LoudnessResult? {
        guard let floatData = buffer.floatChannelData else { return nil }
        let sampleRate = Float(buffer.format.sampleRate)
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, channelCount > 0, sampleRate > 0 else { return nil }

        var peak: Float = 0
        for ch in 0..<channelCount {
            var maxAbs: Float = 0
            vDSP_maxmgv(floatData[ch], 1, &maxAbs, vDSP_Length(frameCount))
            if maxAbs > peak { peak = maxAbs }
        }

        let stage1 = highShelf(f0: 1681.974450955533, gainDB: 3.999843853973347, Q: 0.7071752369554196, fs: sampleRate)
        let stage2 = highPass(f0: 38.13547087602444, Q: 0.5003270373238773, fs: sampleRate)

        let blockSize = Int(0.4 * Double(sampleRate))
        let hopSize = Int(0.1 * Double(sampleRate))
        guard frameCount >= blockSize, hopSize > 0 else { return nil }

        var channelFiltered: [[Float]] = []
        channelFiltered.reserveCapacity(channelCount)
        for ch in 0..<channelCount {
            var data = Array(UnsafeBufferPointer(start: floatData[ch], count: frameCount))
            applyBiquad(data: &data, coeffs: stage1)
            applyBiquad(data: &data, coeffs: stage2)
            channelFiltered.append(data)
        }

        let numBlocks = (frameCount - blockSize) / hopSize + 1
        var blockLoudness: [Float] = []
        blockLoudness.reserveCapacity(numBlocks)

        for b in 0..<numBlocks {
            let start = b * hopSize
            var channelSum: Float = 0
            for ch in 0..<channelCount {
                var sumSq: Float = 0
                channelFiltered[ch].withUnsafeBufferPointer { ptr in
                    vDSP_svesq(ptr.baseAddress!.advanced(by: start), 1, &sumSq, vDSP_Length(blockSize))
                }
                channelSum += sumSq / Float(blockSize)
            }
            if channelSum > 0 {
                blockLoudness.append(-0.691 + 10 * log10f(channelSum))
            } else {
                blockLoudness.append(-Float.infinity)
            }
        }

        let absGated = blockLoudness.filter { $0 >= -70 }
        guard !absGated.isEmpty else { return nil }

        let absEnergies = absGated.map { pow(10, ($0 + 0.691) / 10) }
        let absMean = absEnergies.reduce(0, +) / Float(absEnergies.count)
        let relThresh = -0.691 + 10 * log10f(absMean) - 10

        let relGated = blockLoudness.filter { $0 >= -70 && $0 >= relThresh }
        guard !relGated.isEmpty else { return nil }

        let relEnergies = relGated.map { pow(10, ($0 + 0.691) / 10) }
        let relMean = relEnergies.reduce(0, +) / Float(relEnergies.count)
        let integrated = -0.691 + 10 * log10f(relMean)

        return LoudnessResult(integratedLUFS: integrated, peakLinear: peak)
    }

    private struct BiquadCoeffs {
        let b0, b1, b2, a1, a2: Float
    }

    private static func highShelf(f0: Float, gainDB: Float, Q: Float, fs: Float) -> BiquadCoeffs {
        let A = powf(10, gainDB / 40)
        let w0 = 2 * .pi * f0 / fs
        let cosW = cosf(w0)
        let sinW = sinf(w0)
        let alpha = sinW / (2 * Q)
        let sqrtA = sqrtf(A)

        let b0 =    A * ((A + 1) + (A - 1) * cosW + 2 * sqrtA * alpha)
        let b1 = -2 * A * ((A - 1) + (A + 1) * cosW)
        let b2 =    A * ((A + 1) + (A - 1) * cosW - 2 * sqrtA * alpha)
        let a0 =        (A + 1) - (A - 1) * cosW + 2 * sqrtA * alpha
        let a1 =    2 * ((A - 1) - (A + 1) * cosW)
        let a2 =        (A + 1) - (A - 1) * cosW - 2 * sqrtA * alpha

        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    private static func highPass(f0: Float, Q: Float, fs: Float) -> BiquadCoeffs {
        let w0 = 2 * .pi * f0 / fs
        let cosW = cosf(w0)
        let sinW = sinf(w0)
        let alpha = sinW / (2 * Q)

        let b0 =  (1 + cosW) / 2
        let b1 = -(1 + cosW)
        let b2 =  (1 + cosW) / 2
        let a0 =  1 + alpha
        let a1 = -2 * cosW
        let a2 =  1 - alpha

        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    private static func applyBiquad(data: inout [Float], coeffs: BiquadCoeffs) {
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0
        for i in 0..<data.count {
            let x0 = data[i]
            let y0 = coeffs.b0 * x0 + coeffs.b1 * x1 + coeffs.b2 * x2 - coeffs.a1 * y1 - coeffs.a2 * y2
            data[i] = y0
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
        }
    }
}
