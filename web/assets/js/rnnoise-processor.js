import createRNNWasmModule from './rnnoise/rnnoise.js';

class RnnoiseProcessor {
    constructor(module) {
        this.module = module;
        this.state = module._rnnoise_create(null);
        this.frameSize = 480;
        this.ptrIn = module._malloc(this.frameSize * 4);
        this.ptrOut = module._malloc(this.frameSize * 4);
        this.heapFloat32 = module.HEAPF32;
    }

    process(inputData) {
        // RNNoise expects PCM16-scale floats (e.g. -32768 to 32767), but WebAudio gives -1.0 to 1.0
        // We need to scale up input and scale down output.
        for (let i = 0; i < this.frameSize; i++) {
            this.heapFloat32[(this.ptrIn >> 2) + i] = inputData[i] * 32768;
        }

        const vadProb = this.module._rnnoise_process_frame(this.state, this.ptrOut, this.ptrIn);
        
        // Output is also in PCM16 scale, so we scale back to -1.0 to 1.0
        const output = new Float32Array(this.frameSize);
        for (let i = 0; i < this.frameSize; i++) {
            output[i] = this.heapFloat32[(this.ptrOut >> 2) + i] / 32768;
        }

        return {
            output: output,
            vadProb
        };
    }

    destroy() {
        this.module._rnnoise_destroy(this.state);
        this.module._free(this.ptrIn);
        this.module._free(this.ptrOut);
    }
}

class NoiseSuppressorWorklet extends AudioWorkletProcessor {
    constructor(options) {
        super(options);
        this._initialized = false;
        this._buffer = new Float32Array(0);
        this._outputBuffer = new Float32Array(0);
        this._denoiseSampleSize = 480;

        // AGC State
        this._agcGain = 1.0;
        this._targetLevel = 0.15; // Target RMS level
        this._maxGain = 6.0; // Reduced from 30.0 to 6.0 (approx 15dB) to prevent explosion
        this._lastVadProb = 0.0; // Track VAD for Smart AGC
        this._agcEnabled = options.processorOptions && !!options.processorOptions.agcEnabled;
        
        // If AGC is disabled, ensure we don't apply residual gain
        if (!this._agcEnabled) {
            this._agcGain = 1.0;
        }

        // Gate State
        this._gateGain = 0.0;
        this._gateHold = 0;

        const wasmBinary = options.processorOptions && options.processorOptions.wasmBinary;

        if (!wasmBinary) {
            console.error('No WASM binary provided to NoiseSuppressorWorklet');
            return;
        }

        const config = {
            wasmBinary: wasmBinary,
        };

        createRNNWasmModule(config).then(module => {
            this._processor = new RnnoiseProcessor(module);
            this._initialized = true;
        }).catch(err => {
            console.error('Error initializing RNNoise:', err);
        });
    }

    process(inputs, outputs) {
        const input = inputs[0][0];
        const output = outputs[0][0];

        if (!input) return true;
        if (!this._initialized) {
            output.set(input);
            return true;
        }

        // --- 1. AGC (Pre-processing) ---
        // Calculate RMS of the input chunk (128 samples)
        let sumSq = 0;
        for (let i = 0; i < input.length; i++) {
            sumSq += input[i] * input[i];
        }
        const rms = Math.sqrt(sumSq / input.length);

        // Calculate target gain
        let targetGain = this._agcGain;
        
        if (this._agcEnabled) {
            if (rms > 0.0001) {
                targetGain = this._targetLevel / rms;
            } else {
                // Silence. Don't boost. Drift to unity.
                targetGain = 1.0; 
            }
            
            // Smart VAD-based Gain Limiting
            if (this._lastVadProb < 0.3) {
                 // If it's likely noise, cap the gain aggressively.
                 // Lowered from 3.0 to 1.5 for extra safety against "explosions"
                 if (targetGain > 1.5) targetGain = 1.5;
            }
    
            // Global clamp
            if (targetGain > this._maxGain) targetGain = this._maxGain;
            if (targetGain < 1.0) targetGain = 1.0; // Don't attenuate below unity

            // Asymmetric Smoothing (Smart Attack/Release)
            // Release (Reducing Gain): FAST. If signal is loud, drop gain immediately to prevent clipping.
            // Attack (Increasing Gain): SLOW. If signal is quiet, boost slowly to avoid pumping.
            let agcAlpha = 0.005; 
            if (targetGain < this._agcGain) {
                agcAlpha = 0.15; // Fast Release (e.g. 100ms)
            } else {
                agcAlpha = 0.002; // Slow Attack (e.g. 2s)
            }
    
            this._agcGain = this._agcGain * (1 - agcAlpha) + targetGain * agcAlpha;
        } else {
            targetGain = 1.0;
            this._agcGain = 1.0; // Force unity gain
        }

        // Apply AGC to input buffer before appending
        // We clone input to avoid side effects if reused
        const amplifiedInput = new Float32Array(input.length);
        for (let i = 0; i < input.length; i++) {
            amplifiedInput[i] = input[i] * this._agcGain;
        }

        // Buffer input
        const newBuffer = new Float32Array(this._buffer.length + amplifiedInput.length);
        newBuffer.set(this._buffer);
        newBuffer.set(amplifiedInput, this._buffer.length);
        this._buffer = newBuffer;

        // Process 480-sample frames
        while (this._buffer.length >= this._denoiseSampleSize) {
            const frame = this._buffer.slice(0, this._denoiseSampleSize);
            this._buffer = this._buffer.slice(this._denoiseSampleSize);
            
            const { output: processed, vadProb } = this._processor.process(frame);
            this._lastVadProb = vadProb; // Update VAD for AGC Feedback loop
            
            // --- 2. VAD Gate (Post-processing) ---
            let targetGate = 0.0;
            // VAD threshold 0.6 (High probability of speech)
            if (vadProb > 0.6) {
                targetGate = 1.0;
                this._gateHold = 30; // Hold for 30 frames (300ms)
            } else {
                if (this._gateHold > 0) {
                    targetGate = 1.0;
                    this._gateHold--;
                }
            }
            
            // Smooth Gate (Fast Attack, Slower Release)
            // If opening, alpha high. If closing, alpha low.
            const gateAlpha = targetGate > this._gateGain ? 0.2 : 0.05;
            this._gateGain = this._gateGain * (1 - gateAlpha) + targetGate * gateAlpha;
            
            // Apply Gate to processed frame
            for (let i = 0; i < processed.length; i++) {
                processed[i] *= this._gateGain;
            }

            const newOut = new Float32Array(this._outputBuffer.length + processed.length);
            newOut.set(this._outputBuffer);
            newOut.set(processed, this._outputBuffer.length);
            this._outputBuffer = newOut;
        }

        // Output 128 samples
        if (this._outputBuffer.length >= 128) {
            output.set(this._outputBuffer.slice(0, 128));
            this._outputBuffer = this._outputBuffer.slice(128);
        } else {
            // Latency handling: if we don't have enough data, output silence
            // (This creates a slight initial delay but ensures continuous stream later)
            output.fill(0);
        }

        return true;
    }
}

registerProcessor('noise-suppressor', NoiseSuppressorWorklet);
