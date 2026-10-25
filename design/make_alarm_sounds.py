"""Synthesizes Bedtime Bridge's alarm sounds (original, no samples) as 16-bit mono WAVs."""
import sys, wave
import numpy as np

SR = 44100
LENGTH = 28.0  # under 30 s, so iOS accepts them as alert sounds
out = sys.argv[1]
rng = np.random.default_rng(7)

def t_of(d): return np.arange(int(SR * d)) / SR
def midi(n): return 440.0 * 2 ** ((n - 69) / 12)

def place(buf, sig, at):
    i = int(at * SR); j = min(len(buf), i + len(sig))
    if i < len(buf): buf[i:j] += sig[: j - i]

def bell(f, d=3.0):
    t = t_of(d)
    parts = [(1, 1.0, 1.2), (2.76, 0.5, 2.5), (5.4, 0.25, 4.0), (8.93, 0.12, 6.0)]
    s = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-k * t) for r, a, k in parts)
    return s * np.minimum(1, t / 0.003)

def mallet(f, d=0.9):
    t = t_of(d)
    s = np.sin(2 * np.pi * f * t) * np.exp(-6 * t) + 0.35 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-18 * t)
    return s * np.minimum(1, t / 0.002)

def pluck(f, d=2.5):
    n = int(SR / f); buf = rng.uniform(-1, 1, n); outp = np.zeros(int(SR * d))
    for i in range(len(outp)):
        outp[i] = buf[i % n]
        buf[i % n] = 0.996 * 0.5 * (buf[i % n] + buf[(i + 1) % n])
    return outp

def tone(f, d, shape="sine"):
    t = t_of(d)
    s = np.sin(2 * np.pi * f * t)
    if shape == "square": s = np.tanh(4 * s)
    env = np.minimum(1, t / 0.005) * np.minimum(1, (d - t) / 0.01)
    return s * env

def finish(buf, name, ramp=None):
    if ramp is not None: buf *= ramp
    buf /= max(1e-9, np.abs(buf).max()); buf *= 0.89
    data = (buf * 32767).astype(np.int16)
    with wave.open(f"{out}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

n = int(SR * LENGTH); t = t_of(LENGTH)

# Sunrise: a slow, warm chord arpeggio that starts quiet and builds.
buf = np.zeros(n)
chords = [[60, 64, 67, 72], [57, 60, 64, 69], [53, 57, 60, 65], [55, 59, 62, 67]]
at = 0.0
while at < LENGTH:
    for chord in chords:
        for k, note in enumerate(chord):
            place(buf, 0.6 * bell(midi(note + 12), 3.5), at + k * 0.35)
            place(buf, 0.4 * mallet(midi(note), 1.2), at + k * 0.35)
        at += 1.75
finish(buf, "sunrise", ramp=0.15 + 0.85 * np.clip(t / 20, 0, 1))

# Chimes: a bright four-note bell phrase, repeated.
buf = np.zeros(n)
phrase = [76, 72, 74, 67, 67, 74, 76, 72]
at = 0.0
while at < LENGTH:
    for k, note in enumerate(phrase):
        place(buf, bell(midi(note), 3.0), at + k * 0.5)
    at += 5.0
finish(buf, "chimes")

# Marimba: a bouncy mallet pattern.
buf = np.zeros(n)
pattern = [72, 76, 79, 76, 84, 79, 76, 79]
at = 0.0
while at < LENGTH:
    for k, note in enumerate(pattern):
        place(buf, mallet(midi(note)), at + k * 0.18)
        place(buf, 0.4 * mallet(midi(note - 12)), at + k * 0.18)
    at += 1.8
finish(buf, "marimba")

# Harp: rising plucked arpeggios.
buf = np.zeros(n)
notes = [55, 59, 62, 67, 71, 74, 79, 83]
at = 0.0
while at < LENGTH:
    for k, note in enumerate(notes):
        place(buf, pluck(midi(note)), at + k * 0.14)
    at += 2.6
buf /= np.abs(buf).max(); buf = np.tanh(3 * buf)
finish(buf, "harp")

# Classic: the four-beep digital alarm clock.
buf = np.zeros(n)
at = 0.0
while at < LENGTH:
    for k in range(4):
        place(buf, tone(2000, 0.08, "square") * 0.6, at + k * 0.14)
    at += 1.0
finish(buf, "classic")

# Pulse: an insistent two-tone pulse for heavy sleepers.
buf = np.zeros(n)
at = 0.0; hi = True
while at < LENGTH:
    place(buf, tone(988 if hi else 740, 0.22, "square"), at)
    hi = not hi; at += 0.3
finish(buf, "pulse")
print("ok")
