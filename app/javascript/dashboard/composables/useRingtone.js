// Ringtone for incoming calls, synthesized with WebAudio (no asset): dual tone
// 440 + 480 Hz, 2 s on / 4 s off, looped until stop().
const TONE_A = 440;
const TONE_B = 480;
const RING_ON_MS = 2000;
const RING_PERIOD_MS = 6000;
const GAIN = 0.08;

let context = null;
let timer = null;
let oscillators = [];

const stopTone = () => {
  oscillators.forEach(o => {
    try {
      o.stop();
    } catch (e) {
      // already stopped
    }
  });
  oscillators = [];
};

const playTone = () => {
  if (!context) return;
  const gain = context.createGain();
  gain.gain.value = GAIN;
  gain.connect(context.destination);
  oscillators = [TONE_A, TONE_B].map(freq => {
    const osc = context.createOscillator();
    osc.type = 'sine';
    osc.frequency.value = freq;
    osc.connect(gain);
    osc.start();
    osc.stop(context.currentTime + RING_ON_MS / 1000);
    return osc;
  });
};

export const useRingtone = () => {
  const start = () => {
    if (timer) return;
    try {
      context =
        context || new (window.AudioContext || window.webkitAudioContext)();
      if (context.state === 'suspended') context.resume();
    } catch (e) {
      return; // no audio available in this environment
    }
    playTone();
    timer = setInterval(playTone, RING_PERIOD_MS);
  };

  const stop = () => {
    if (timer) clearInterval(timer);
    timer = null;
    stopTone();
  };

  return { start, stop };
};
