class RecorderProcessor extends AudioWorkletProcessor {
    constructor(options) {
        super();
        this.bufferSize = 2048;
        this.buffer = new Float32Array(this.bufferSize);
        this.bufferIndex = 0;
        this.targetSampleRate = options.processorOptions.targetSampleRate || 16000;
        this.outputFormat = options.processorOptions.outputFormat || 'pcm16';
    }

    process(inputs, outputs) {
        const input = inputs[0];
        if (!input || !input.length) return true;
        
        const channelData = input[0];
        if (!channelData) return true;

        // Fill buffer
        for (let i = 0; i < channelData.length; i++) {
            this.buffer[this.bufferIndex++] = channelData[i];
            
            // When buffer is full, process and flush
            if (this.bufferIndex >= this.bufferSize) {
                this.flush();
            }
        }

        return true;
    }

    flush() {
        const inputData = this.buffer;
        const currentSampleRate = sampleRate;
        const ratio = currentSampleRate / this.targetSampleRate;
        const outLength = Math.floor(inputData.length / ratio);
        let sumSq = 0;

        // Linear interpolation resampling to reduce aliasing
        if (this.outputFormat === 'pcmf32') {
            const f32 = new Float32Array(outLength);
            for (let i = 0; i < outLength; i++) {
                const pos = i * ratio;
                const idx = Math.floor(pos);
                const frac = pos - idx;
                const s0 = inputData[idx] || 0.0;
                const s1 = inputData[idx + 1] || s0;
                let s = s0 + (s1 - s0) * frac;
                if (s > 1.0) s = 1.0;
                if (s < -1.0) s = -1.0;
                f32[i] = s;
                sumSq += s * s;
            }
            const rms = Math.sqrt(sumSq / outLength);
            if (rms > 0.02) {
                this.gateHold = 10;
            }
            if (this.gateHold > 0) {
                this.gateHold--;
                this.port.postMessage(f32.buffer, [f32.buffer]);
            }
        } else {
            const pcmData = new Int16Array(outLength);
            for (let i = 0; i < outLength; i++) {
                const pos = i * ratio;
                const idx = Math.floor(pos);
                const frac = pos - idx;
                const s0 = inputData[idx] || 0.0;
                const s1 = inputData[idx + 1] || s0;
                let s = s0 + (s1 - s0) * frac;
                if (s > 1.0) s = 1.0;
                if (s < -1.0) s = -1.0;
                const val = s < 0 ? s * 0x8000 : s * 0x7FFF;
                pcmData[i] = val;
                sumSq += s * s;
            }
            const rms = Math.sqrt(sumSq / outLength);
            if (rms > 0.02) { 
                this.gateHold = 10;
            }
            if (this.gateHold > 0) {
                this.gateHold--;
                this.port.postMessage(pcmData.buffer, [pcmData.buffer]);
            }
        }

        this.bufferIndex = 0;
    }
}

registerProcessor('recorder-processor', RecorderProcessor);
