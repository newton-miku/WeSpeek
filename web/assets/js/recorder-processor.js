class RecorderProcessor extends AudioWorkletProcessor {
    constructor(options) {
        super();
        this.bufferSize = 2048;
        this.buffer = new Float32Array(this.bufferSize);
        this.bufferIndex = 0;
        this.targetSampleRate = options.processorOptions.targetSampleRate || 16000;
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
        const newLength = Math.floor(inputData.length / ratio);
        const pcmData = new Int16Array(newLength);
        let sumSq = 0;

        for (let i = 0; i < newLength; i++) {
            const offset = Math.floor(i * ratio);
            let s = Math.max(-1, Math.min(1, inputData[offset]));
            const val = s < 0 ? s * 0x8000 : s * 0x7FFF;
            pcmData[i] = val;
            
            // Calculate RMS on the fly
            // Use normalized float s for calculation
            sumSq += s * s;
        }

        const rms = Math.sqrt(sumSq / newLength);

        // Silence detection (Noise Gate)
        // Client uses 0.02 RMS. We use the same here.
        // This acts as a hard gate at the lowest level.
        if (rms > 0.02) { 
            this.port.postMessage(pcmData.buffer, [pcmData.buffer]);
        }
        
        this.bufferIndex = 0;
    }
}

registerProcessor('recorder-processor', RecorderProcessor);
