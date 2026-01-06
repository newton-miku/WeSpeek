class RecorderProcessor extends AudioWorkletProcessor {
    constructor(options) {
        super();
        this.targetSampleRate = options.processorOptions.targetSampleRate || 16000;
        this.outputFormat = options.processorOptions.outputFormat || 'pcm16';
        this.remainder = new Float32Array(0);
        this.gateHold = 0;
        this.nextPhase = 0;

        // Buffering for PCM
        this.bufferSize = 2048; 
        this.bufferIdx = 0;
        this.buffer = null;
        this.bufferSumSq = 0;

        // AGC State
        this.agcGain = 1.0;
        this.targetLevel = 0.15;
        this.maxGain = 6.0;
        this.enableAGC = options.processorOptions.enableAGC !== false;

        this.port.onmessage = (e) => {
            if (e.data) {
                if (e.data.type === 'setAgc') {
                    this.enableAGC = e.data.enabled;
                } else if (e.data.type === 'setParams') {
                    if (e.data.targetSampleRate) {
                        this.targetSampleRate = e.data.targetSampleRate;
                        // Reset resampling state on rate change to avoid glitches
                        this.remainder = new Float32Array(0);
                        this.nextPhase = 0;
                    }
                    if (e.data.outputFormat) {
                        this.outputFormat = e.data.outputFormat;
                        this.buffer = null;
                        this.bufferIdx = 0;
                        this.bufferSumSq = 0;
                    }
                }
            }
        };
    }

    process(inputs, outputs) {
        const input = inputs[0];
        if (!input || !input.length) return true;
        
        const channelData = input[0];
        if (!channelData || channelData.length === 0) return true;

        // Apply AGC if enabled
        if (this.enableAGC) {
            let sumSq = 0;
            for (let i = 0; i < channelData.length; i++) {
                sumSq += channelData[i] * channelData[i];
            }
            const rms = Math.sqrt(sumSq / channelData.length);
            
            let targetGain = this.agcGain;
            if (rms > 0.0001) {
                targetGain = this.targetLevel / rms;
            } else {
                targetGain = 1.0;
            }
            
            if (targetGain > this.maxGain) targetGain = this.maxGain;
            
            // Smoothing
            let alpha = 0.005;
            if (targetGain < this.agcGain) {
                alpha = 0.15; // Fast release
            } else {
                alpha = 0.002; // Slow attack
            }
            
            this.agcGain = this.agcGain * (1 - alpha) + targetGain * alpha;
            
            for (let i = 0; i < channelData.length; i++) {
                channelData[i] *= this.agcGain;
            }
        }

        // Combine remainder from previous process call with new data
        const inputData = new Float32Array(this.remainder.length + channelData.length);
        if (this.remainder.length > 0) {
            inputData.set(this.remainder);
        }
        inputData.set(channelData, this.remainder.length);

        const currentSampleRate = sampleRate;
        const ratio = currentSampleRate / this.targetSampleRate;
        
        // Strategy:
        // If ratio > 2.0, use Averaging (Boxcar) to avoid severe aliasing from decimation.
        // If ratio <= 2.0 (Upsampling or slight Downsampling), use Cubic Interpolation for quality.
        const useCubic = ratio <= 2.0;

        let outLength = 0;
        if (useCubic) {
             // Cubic needs p0(i-1), p1(i), p2(i+1), p3(i+2)
             // We need floor(pos) + 2 < inputData.length
             // floor(pos) <= inputData.length - 3
             // pos < inputData.length - 2
             // (outLength-1)*ratio + phase < inputData.length - 2
             outLength = Math.floor((inputData.length - 2 - this.nextPhase) / ratio) + 1;
        } else {
             // Averaging needs window end
             outLength = Math.floor((inputData.length - this.nextPhase) / ratio);
        }

        if (outLength > 0) {
            this.processAndPost(inputData, outLength, ratio, useCubic);
            
            // Update phase and remainder
            const nextInputPos = outLength * ratio + this.nextPhase;
            const consumed = Math.floor(nextInputPos);
            
            this.nextPhase = nextInputPos - consumed;
            
            // For Cubic, we need history (p0). 
            // So we shouldn't discard everything up to `consumed`.
            // We need to keep at least 1 sample BEFORE the new start.
            // Let's keep 2 samples before just to be safe and simple.
            // new remainder start index = consumed - 2
            
            let keepIdx = consumed - 2;
            if (keepIdx < 0) keepIdx = 0;

            // Adjust nextPhase to be relative to the new remainder start
            // phase was relative to inputData[0]
            // new remainder starts at inputData[keepIdx]
            // so new phase = (nextInputPos) - keepIdx
            // = (consumed + fractional) - keepIdx
            // = (consumed - keepIdx) + fractional
            this.nextPhase += (consumed - keepIdx);

            if (keepIdx < inputData.length) {
                this.remainder = inputData.slice(keepIdx);
            } else {
                this.remainder = new Float32Array(0);
                this.nextPhase = 0; 
            }
        } else {
            // Not enough data, keep everything
            // But we need to limit buffer growth if something is wrong?
            // Usually ok.
            this.remainder = inputData;
        }

        return true;
    }

    processAndPost(inputData, outLength, ratio, useCubic) {
        if (!this.buffer) {
             this.buffer = this.outputFormat === 'pcmf32' ? new Float32Array(this.bufferSize) : new Int16Array(this.bufferSize);
        }
        
        const isFloat = this.outputFormat === 'pcmf32';

        for (let i = 0; i < outLength; i++) {
            let s;
            if (useCubic) {
                const pos = i * ratio + this.nextPhase;
                const idx = Math.floor(pos);
                const frac = pos - idx;
                
                const p1 = inputData[idx];
                const p0 = idx > 0 ? inputData[idx - 1] : p1;
                const p2 = idx + 1 < inputData.length ? inputData[idx + 1] : p1;
                const p3 = idx + 2 < inputData.length ? inputData[idx + 2] : p2;

                const t = frac;
                const t2 = t * t;
                const t3 = t * t2;
                
                s = 0.5 * ( (2 * p1) + 
                            (-p0 + p2) * t + 
                            (2*p0 - 5*p1 + 4*p2 - p3) * t2 + 
                            (-p0 + 3*p1 - 3*p2 + p3) * t3 );
            } else {
                const startOffset = i * ratio + this.nextPhase;
                const endOffset = (i + 1) * ratio + this.nextPhase;
                let startIdx = Math.floor(startOffset);
                let endIdx = Math.ceil(endOffset);
                if (endIdx > inputData.length) endIdx = inputData.length;
                
                let sum = 0;
                let count = 0;
                for (let j = startIdx; j < endIdx; j++) {
                    sum += inputData[j];
                    count++;
                }
                s = count > 0 ? sum / count : 0;
            }
            
            if (s > 1.0) s = 1.0;
            if (s < -1.0) s = -1.0;
            
            if (isFloat) {
                this.buffer[this.bufferIdx] = s;
                this.bufferSumSq += s * s;
            } else {
                const val = s < 0 ? s * 0x8000 : s * 0x7FFF;
                this.buffer[this.bufferIdx] = val;
                this.bufferSumSq += s * s;
            }
            
            this.bufferIdx++;
            
            if (this.bufferIdx >= this.bufferSize) {
                this.handleGateAndPost();
            }
        }
    }

    handleGateAndPost() {
        const rms = Math.sqrt(this.bufferSumSq / this.bufferSize);
        if (rms > 0.005) {
            this.gateHold = 6; // Approx 250ms hold
        }
        
        if (this.gateHold > 0) {
            this.gateHold--;
            const sendBuffer = this.buffer;
            
            // Reallocate buffer
            this.buffer = this.outputFormat === 'pcmf32' ? new Float32Array(this.bufferSize) : new Int16Array(this.bufferSize);
            
            this.port.postMessage(sendBuffer.buffer, [sendBuffer.buffer]);
        } else {
            // Silence, just reuse buffer (reset index)
        }
        
        this.bufferIdx = 0;
        this.bufferSumSq = 0;
    }
}

registerProcessor('recorder-processor', RecorderProcessor);