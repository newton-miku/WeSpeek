
window.rnnoiseBridge = {
    module: null,
    state: null,
    ptrIn: null,
    ptrOut: null,
    heapFloat32: null,
    frameSize: 480,

    init: async function(wasmUrl) {
        if (this.module) return true;
        
        try {
             const config = {
                 locateFile: (path, prefix) => {
                     if (path.endsWith('.wasm')) return wasmUrl;
                     return prefix + path;
                 }
             };
             
             this.module = await createRNNWasmModule(config);
             this.state = this.module._rnnoise_create(null);
             this.ptrIn = this.module._malloc(this.frameSize * 4);
             this.ptrOut = this.module._malloc(this.frameSize * 4);
             this.heapFloat32 = this.module.HEAPF32;
             console.log("RNNoise Initialized (Flutter Bridge)");
             return true;
        } catch (e) {
            console.error("RNNoise Init Error:", e);
            return false;
        }
    },

    process: function(inputArray) {
        if (!this.module || !this.state) return inputArray;

        // Ensure input is Float32Array
        const input = inputArray instanceof Float32Array ? inputArray : new Float32Array(inputArray);
        const output = new Float32Array(input.length);
        
        // Process in 480-sample chunks
        for (let offset = 0; offset < input.length; offset += this.frameSize) {
            if (offset + this.frameSize > input.length) {
                // Copy remaining
                output.set(input.subarray(offset), offset);
                break;
            }

            // Copy to WASM memory (scale to PCM16)
            for (let i = 0; i < this.frameSize; i++) {
                this.heapFloat32[(this.ptrIn >> 2) + i] = input[offset + i] * 32768;
            }

            // Process
            this.module._rnnoise_process_frame(this.state, this.ptrOut, this.ptrIn);

            // Copy back (scale to Float32)
            for (let i = 0; i < this.frameSize; i++) {
                output[offset + i] = this.heapFloat32[(this.ptrOut >> 2) + i] / 32768.0;
            }
        }
        
        return output;
    }
};
