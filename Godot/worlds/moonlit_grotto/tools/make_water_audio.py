"""Generate an original seamless, filtered-noise waterfall loop using Python's standard library."""
from pathlib import Path
import math, random, struct, wave
rng = random.Random(1709)
rate, seconds, overlap = 22050, 10, 22050
low = broad = 0.0
samples = []
for i in range(rate * seconds + overlap):
    noise = rng.uniform(-1, 1)
    low += .025 * (noise - low)
    broad += .28 * (noise - broad)
    samples.append((low * 1.6 + broad * .6) * .65)
# Crossfade the tail into the head; the next loop then continues from head[overlap].
result = samples[overlap:rate * seconds]
for i in range(overlap):
    t = i / overlap
    result.append(samples[rate * seconds + i] * (1 - t) + samples[i] * t)
out = Path(__file__).resolve().parents[1] / 'audio' / 'waterfall.wav'
with wave.open(str(out), 'wb') as stream:
    stream.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    stream.writeframes(b''.join(struct.pack('<h', round(max(-1,min(1,x))*32767)) for x in result))
print(out)
