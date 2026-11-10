// Runs on the audio thread. Every 20 ms it hands the window one frame: how
// loud it was, and the sound itself at about 16 kHz, which is what the ear
// model listens at. Keeping this off the main thread means a busy window
// cannot make the microphone stutter.
class VoiceFrames extends AudioWorkletProcessor {
  constructor() {
    super();
    // 48 kHz becomes one sample in three. Taking every third sample on its own
    // folds everything above 8 kHz back into the speech as noise, which the
    // ear then reads as different words, so each output sample is the average
    // of the ones it stands for.
    this.step = Math.max(1, Math.round(sampleRate / 16000));
    this.rate = sampleRate / this.step; // the true rate, which is not 16000 at 44.1 kHz
    this.frame = Math.max(1, Math.round(sampleRate / 50)); // 20 ms
    this.buf = new Float32Array(this.frame);
    this.at = 0;
  }

  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (!ch) return true;
    for (let i = 0; i < ch.length; i++) {
      this.buf[this.at++] = ch[i];
      if (this.at < this.frame) continue;
      let sum = 0;
      for (let k = 0; k < this.frame; k++) sum += this.buf[k] * this.buf[k];
      const out = new Float32Array(Math.ceil(this.frame / this.step));
      for (let k = 0, j = 0; k < this.frame; k += this.step) {
        let acc = 0;
        let n = 0;
        for (let m = k; m < Math.min(k + this.step, this.frame); m++, n++) acc += this.buf[m];
        out[j++] = acc / (n || 1);
      }
      this.port.postMessage({ rms: Math.sqrt(sum / this.frame), pcm: out, rate: this.rate }, [out.buffer]);
      this.at = 0;
    }
    return true;
  }
}

registerProcessor('voice-frames', VoiceFrames);
