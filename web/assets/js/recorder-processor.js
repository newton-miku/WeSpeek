class RecorderProcessor extends AudioWorkletProcessor {
    constructor(options) {
        super();
        this.targetSampleRate = options.processorOptions.targetSampleRate || 16000;
        this.outputFormat = options.processorOptions.outputFormat || 'pcm16';
        this.remainder = new Float32Array(0);
        this.gateHold = 0;
    }

    process(inputs, outputs) {
        const input = inputs[0];
        if (!input || !input.length) return true;
        
        const channelData = input[0];
        if (!channelData || channelData.length === 0) return true;

        // Combine remainder from previous process call with new data
        const inputData = new Float32Array(this.remainder.length + channelData.length);
        if (this.remainder.length > 0) {
            inputData.set(this.remainder);
        }
        inputData.set(channelData, this.remainder.length);

        const currentSampleRate = sampleRate;
        const ratio = currentSampleRate / this.targetSampleRate;
        
        // Calculate how many output samples we can generate safely
        // We need input index ceil(i * ratio) + 1 to exist
        // i * ratio + 1 < inputData.length
        // i * ratio < inputData.length - 1
        // i < (inputData.length - 1) / ratio
        const outLength = Math.floor((inputData.length - 1) / ratio);
        
        if (outLength > 0) {
            this.processAndPost(inputData, outLength, ratio);
            
            // Calculate starting index for the next chunk
            // The last used index was floor((outLength - 1) * ratio) + 1 (for interpolation)
            // But actually we just need to keep data starting from where the NEXT output would start.
            // Next output index is outLength.
            // Next input position is outLength * ratio.
            // So we need input data starting from floor(outLength * ratio).
            const nextInputIdx = Math.floor(outLength * ratio);
            this.remainder = inputData.slice(nextInputIdx);
        } else {
            this.remainder = inputData;
        }

        return true;
    }

    processAndPost(inputData, outLength, ratio) {
        let sumSq = 0;

        if (this.outputFormat === 'pcmf32') {
            const f32 = new Float32Array(outLength);
            for (let i = 0; i < outLength; i++) {
                const pos = i * ratio;
                const idx = Math.floor(pos);
                const frac = pos - idx;
                const s0 = inputData[idx];
                const s1 = inputData[idx + 1]; // Safe because of outLength calculation
                let s = s0 + (s1 - s0) * frac;
                if (s > 1.0) s = 1.0;
                if (s < -1.0) s = -1.0;
                f32[i] = s;
                sumSq += s * s;
            }
            this.handleGateAndPost(f32, sumSq / outLength);
        } else {
            const pcmData = new Int16Array(outLength);
            for (let i = 0; i < outLength; i++) {
                const pos = i * ratio;
                const idx = Math.floor(pos);
                const frac = pos - idx;
                const s0 = inputData[idx];
                const s1 = inputData[idx + 1];
                let s = s0 + (s1 - s0) * frac;
                if (s > 1.0) s = 1.0;
                if (s < -1.0) s = -1.0;
                const val = s < 0 ? s * 0x8000 : s * 0x7FFF;
                pcmData[i] = val;
                sumSq += s * s;
            }
            this.handleGateAndPost(pcmData, sumSq / outLength);
        }
    }

    handleGateAndPost(data, meanSq) {
        const rms = Math.sqrt(meanSq);
        if (rms > 0.02) {
            this.gateHold = 10;
        }
        if (this.gateHold > 0) {
            this.gateHold--;
            this.port.postMessage(data.buffer, [data.buffer]);
        }
    }
}

registerProcessor('recorder-processor', RecorderProcessor);
