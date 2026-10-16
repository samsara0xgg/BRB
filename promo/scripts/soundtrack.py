#!/usr/bin/env python3
"""
The film's soundtrack: original music and sound design, synthesized from the same cue sheet the
picture uses (src/cues.json), so every hit lands on its frame.

    python3 scripts/soundtrack.py            # writes public/audio/soundtrack.wav

The siren and the soft beeps are BRB's own (Alarm.swift): a 650-1250 Hz sweep with a 1.2 s period,
overdriven with tanh(3 sin), and an 880 Hz beep of 0.15 s every second.
"""
import json
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parent.parent
Q = json.loads((ROOT / "src" / "cues.json").read_text())
SR = 48000
DUR = Q["duration"]
N = int(round(DUR * SR))
BEAT = 60 / Q["bpm"]
rng = np.random.default_rng(20261016)

I, ST, A, G, T, L, PH, P, TI, W, B, EN = (Q[k] for k in ("intro", "setup", "arm", "guard", "touch", "lift", "phone", "putback", "touchid", "welcome", "bento", "end"))


# ---------------------------------------------------------------- basics

def secs(n):
    return np.arange(n) / SR


def ns(d):
    return max(1, int(round(d * SR)))


NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    """'A4' → 440, 'C#5', 'Bb2' …"""
    letter, rest = name[0], name[1:]
    semi = NOTE[letter]
    if rest[0] in "#b":
        semi += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    midi = 12 * (int(rest) + 1) + semi
    return 440.0 * 2 ** ((midi - 69) / 12)


def sos(kind, f, order=2):
    return signal.butter(order, f, kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(sos("lowpass", min(f, SR * 0.45), order), x, axis=-1)


def hp(x, f, order=2):
    return signal.sosfilt(sos("highpass", f, order), x, axis=-1)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(sos("bandpass", [lo, min(hi, SR * 0.45)], order), x, axis=-1)


def fades(x, fin=0.003, fout=0.02):
    n = x.shape[-1]
    a, b = min(n, ns(fin)), min(n, ns(fout))
    env = np.ones(n)
    env[:a] = np.linspace(0, 1, a) ** 2
    env[n - b :] *= np.linspace(1, 0, b) ** 2
    return x * env


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    """An envelope n samples long, releasing over its last r seconds."""
    env = np.full(n, s)
    na, nd, nr = ns(a), ns(d), ns(r)
    na = min(na, n)
    env[:na] = np.linspace(0, 1, na)
    d_end = min(n, na + nd)
    env[na:d_end] = np.linspace(1, s, d_end - na)
    nr = min(nr, n)
    env[n - nr :] *= np.linspace(1, 0, nr) ** 1.5
    return env


def phase_of(f, n, phase0=0.0):
    if np.isscalar(f):
        return (phase0 + f * secs(n)) % 1.0, np.full(n, f / SR)
    return (phase0 + np.cumsum(f) / SR) % 1.0, f / SR


def sine(f, n, phase0=0.0):
    ph, _ = phase_of(f, n, phase0)
    return np.sin(2 * np.pi * ph)


def saw(f, n, phase0=0.0):
    """A band-limited sawtooth (polyBLEP)."""
    ph, dt = phase_of(f, n, phase0)
    y = 2 * ph - 1
    m = ph < dt
    x = ph[m] / dt[m]
    y[m] -= x + x - x * x - 1
    m = ph > 1 - dt
    x = (ph[m] - 1) / dt[m]
    y[m] -= x * x + x + x + 1
    return y


def noise(n, ch=1):
    return rng.standard_normal((ch, n)) if ch > 1 else rng.standard_normal(n)


def pan2(x, p):
    """Constant-power pan of a mono signal; p in -1…1, scalar or per-sample."""
    a = (np.asarray(p) + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)])


class Bus:
    def __init__(self):
        self.x = np.zeros((2, N))

    def add(self, sig, at, gain=1.0, pan=0.0):
        sig = np.asarray(sig, dtype=float)
        if sig.ndim == 1:
            sig = pan2(sig, pan)
        s = int(round(at * SR))
        a, b = max(0, s), min(N, s + sig.shape[1])
        if b <= a:
            return
        self.x[:, a:b] += gain * sig[:, a - s : b - s]


def make_ir(rt60, predelay=0.015, bright=6500, length=None, seed=1):
    r = np.random.default_rng(seed)
    n = ns(length or rt60 * 1.15)
    t = secs(n)
    env = 10 ** (-3 * t / rt60)
    ir = r.standard_normal((2, n)) * env
    ir = lp(ir, bright)
    dark = lp(ir, bright / 4)
    w = np.clip(t / (rt60 * 0.5), 0, 1)
    ir = ir * (1 - w) + dark * w
    ir[:, : ns(predelay)] = 0
    ir /= np.sqrt((ir**2).sum(axis=1, keepdims=True))
    return ir


def reverb(x, ir):
    return np.stack([signal.fftconvolve(x[c], ir[c])[:N] for c in range(2)])


# ---------------------------------------------------------------- instruments

def pad(freqs, dur, a=0.6, r=0.8, cutoff=1600, gain=1.0, s=0.85):
    n = ns(dur)
    out = np.zeros((2, n))
    for f in freqs:
        for ch, spread in ((0, -1), (1, 1)):
            for det, amp in ((-0.12, 0.7), (0.0, 1.0), (0.14, 0.7)):
                ff = f * 2 ** ((det + spread * 0.035) / 12)
                out[ch] += amp * saw(ff, n, rng.random())
    out = lp(lp(out, cutoff), cutoff * 1.5)
    out *= adsr(n, a, 0.4, s, r)
    return gain * out / (len(freqs) * 2.4)


def pluck(f, dur=0.9, decay=3.2, bright=0.72, gain=1.0):
    n = ns(dur)
    t = secs(n)
    y = np.zeros(n)
    for k in range(1, 14):
        if f * k > 14000:
            break
        y += (bright ** (k - 1)) / k * np.sin(2 * np.pi * f * k * t * (1 + 0.0003 * (k - 1) ** 2)) * np.exp(-t * decay * (1 + 0.45 * (k - 1)))
    return gain * fades(y, 0.002, 0.03)


def bell(f, dur=2.4, gain=1.0, decay=1.0):
    n = ns(dur)
    t = secs(n)
    y = np.zeros(n)
    for ratio, amp, d in ((1, 1.0, 1.3), (2.0, 0.42, 2.0), (2.76, 0.32, 2.8), (4.07, 0.16, 4.0), (5.4, 0.09, 5.5)):
        if f * ratio < 16000:
            y += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * d * decay)
    return gain * fades(y, 0.001, 0.05)


def bass_note(f, dur, cutoff=380, gain=1.0):
    n = ns(dur)
    y = 0.6 * saw(f, n) + 0.8 * sine(f, n) + 0.3 * sine(f / 2, n)
    y = lp(y, cutoff, 2)
    return gain * y * adsr(n, 0.004, 0.09, 0.55, min(0.06, dur * 0.3))


def kick(gain=1.0, tone=56, punch=1.0):
    n = ns(0.45)
    t = secs(n)
    f = tone + 130 * np.exp(-t * 32)
    y = sine(f, n) * np.exp(-t * 9)
    click = hp(noise(n), 2500) * np.exp(-t * 280) * 0.45 * punch
    y = np.tanh(1.8 * (y + click)) / np.tanh(1.8)
    return gain * fades(y, 0.0005, 0.03)


def hat(gain=1.0, open_=False):
    n = ns(0.25 if open_ else 0.07)
    t = secs(n)
    y = hp(noise(n), 7500, 4) * np.exp(-t * (12 if open_ else 60))
    return gain * fades(y, 0.0005, 0.01)


def shaker(gain=1.0):
    n = ns(0.09)
    t = secs(n)
    env = (1 - np.exp(-t * 300)) * np.exp(-t * 45)
    return gain * bp(noise(n), 4500, 11000, 2) * env


def clap(gain=1.0):
    n = ns(0.35)
    t = secs(n)
    env = np.zeros(n)
    for k, off in enumerate((0, 0.011, 0.022)):
        s = ns(off)
        env[s:] += np.exp(-(t[: n - s]) * (160 if k < 2 else 22)) * (0.8 if k < 2 else 1.0)
    y = bp(noise(n), 900, 3200, 2) * env
    return gain * fades(y, 0.0005, 0.05)


def tom(f=90, gain=1.0):
    n = ns(0.6)
    t = secs(n)
    y = sine(f * (1 + 0.6 * np.exp(-t * 20)), n) * np.exp(-t * 6) + lp(noise(n), 900) * np.exp(-t * 25) * 0.3
    return gain * fades(np.tanh(1.5 * y), 0.0005, 0.05)


def whoosh(dur, f0, f1, peak=0.6, pan0=-0.4, pan1=0.4, gain=1.0, k=10):
    """Air moving past: noise through a band that slides from f0 to f1."""
    n = ns(dur)
    t = secs(n) / dur
    src = lp(noise(n), 9000)
    centers = np.geomspace(f0, f1, k)
    u = t * (k - 1)
    y = np.zeros(n)
    for i, c in enumerate(centers):
        w = np.exp(-((i - u) ** 2) / 1.2)
        y += bp(src, c / 1.7, c * 1.7) * w
    env = np.where(t < peak, (t / peak) ** 2, ((1 - t) / (1 - peak)) ** 1.6)
    y = fades(y * env, 0.005, 0.02)
    return gain * pan2(y, pan0 + (pan1 - pan0) * t)


def riser(dur, f0=300, f1=5000, gain=1.0):
    n = ns(dur)
    t = secs(n) / dur
    up = whoosh(dur, f0, f1, peak=0.97, pan0=-0.2, pan1=0.2)
    glide = sine(220 * 2 ** (t * 1.5), n) * 0.12 * t**2
    return gain * (up + pan2(glide, 0))


def impact(gain=1.0, sub0=95, sub1=44, length=2.2, bright=2400):
    n = ns(length)
    t = secs(n)
    sub = 0.8 * sine(sub1 + (sub0 - sub1) * np.exp(-t * 7), n) * np.exp(-t * 2.2)
    hit = lp(noise(n), bright) * np.exp(-t * 11) * 0.7
    y = np.tanh(1.6 * (sub + hit)) / np.tanh(1.6)
    return gain * fades(y, 0.0008, 0.2)


def click(gain=1.0, f=2600):
    n = ns(0.05)
    t = secs(n)
    y = hp(noise(n), 2000) * np.exp(-t * 420) * 0.6 + np.sin(2 * np.pi * f * t) * np.exp(-t * 260) * 0.5 + np.sin(2 * np.pi * 950 * t) * np.exp(-t * 140) * 0.25
    return gain * fades(y, 0.0003, 0.01)


def tick(f, gain=1.0):
    n = ns(0.18)
    t = secs(n)
    y = np.sin(2 * np.pi * f * t) * np.exp(-t * 38) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 70)
    y += hp(noise(n), 3000) * np.exp(-t * 500) * 0.2
    return gain * fades(y, 0.0004, 0.02)


def pop(f, gain=1.0):
    n = ns(0.22)
    t = secs(n)
    y = sine(f * (1 + 0.5 * np.exp(-t * 60)), n) * np.exp(-t * 22)
    y += hp(noise(n), 3000) * np.exp(-t * 600) * 0.15
    return gain * fades(y, 0.0004, 0.02)


def thud(gain=1.0):
    n = ns(0.9)
    t = secs(n)
    body = sine(52 + 70 * np.exp(-t * 28), n) * np.exp(-t * 9)
    knock = bp(noise(n), 140, 1300) * np.exp(-t * 32) * 0.7
    rattle = hp(noise(n), 2500) * np.exp(-t * 70) * 0.12
    y = np.tanh(1.4 * (body + knock + rattle))
    return gain * fades(y, 0.0004, 0.1)


def buzz(dur=0.36, gain=1.0):
    """A phone's haptic buzz: two short pulses."""
    n = ns(dur)
    t = secs(n)
    gate = ((t < 0.13) | ((t > 0.2) & (t < 0.33))).astype(float)
    gate = lp(gate, 60)
    y = np.tanh(2.5 * np.sin(2 * np.pi * 168 * t)) * gate
    return gain * lp(y, 900)


def shimmer(dur=1.5, gain=1.0):
    n = ns(dur)
    out = np.zeros((2, n))
    for _ in range(46):
        at = rng.random() ** 0.8 * dur * 0.85
        f = 2200 * 2 ** (rng.random() * 1.8)
        b = bell(f, 0.5, decay=3.0) * 0.5
        s = ns(at)
        m = min(len(b), n - s)
        out += pan2(np.pad(b[:m], (s, n - s - m)), rng.uniform(-0.8, 0.8)) * (1 - at / dur) ** 0.5
    out += whoosh(dur, 1800, 9000, peak=0.35, pan0=-0.6, pan1=0.6) * 0.5
    return gain * out / 6


def chord(names):
    return [hz(x) for x in names]


# ---------------------------------------------------------------- the score

music, drums, tension, sfx, siren_bus, amb, send_hall, send_room = (Bus() for _ in range(8))

# Chords by section.
AM = chord(["A2", "E3", "G3", "B3", "C4"])
F = chord(["F2", "C3", "E3", "A3", "C4"])
C = chord(["C3", "G3", "C4", "E4", "G4"])
GG = chord(["G2", "D3", "G3", "B3", "D4"])
AM_LOW = chord(["A1", "E2"])

ROOTS = {"Am": "A2", "F": "F2", "C": "C3", "G": "G2", "Gsus": "G2"}
ARPS = {
    "Am": ["A4", "E5", "C5", "E5", "B4", "E5", "C5", "G4"],
    "F": ["F4", "C5", "A4", "C5", "E5", "C5", "A4", "G4"],
    "C": ["C5", "G5", "E5", "G5", "D5", "G5", "E5", "C5"],
    "G": ["G4", "D5", "B4", "D5", "A4", "D5", "B4", "D5"],
    "Gsus": ["G4", "D5", "C5", "D5", "G5", "D5", "C5", "D5"],
}
PADS = {"Am": AM, "F": F, "C": C, "G": GG, "Gsus": chord(["G2", "D3", "G3", "C4", "D4"])}

kicks = []  # times, for the sidechain


def groove(start, end, chords, level):
    """Bars of 2 s from `start`; `level` 1 = setup, 2 = arming, 3 = full."""
    t = start
    i = 0
    while t < end - 1e-6:
        name = chords[i % len(chords)]
        bar_end = min(end, t + 4 * BEAT)
        music.add(pad(PADS[name], bar_end - t + 0.25, a=0.25 if i else 0.5, r=0.3, cutoff=1800 + 600 * level, gain=0.5), t)
        root = hz(ROOTS[name])
        for k in range(8):
            bt = t + k * BEAT / 2
            if bt >= end - 0.01:
                break
            if level >= 1:
                octave = 2 if (level >= 3 and k % 4 == 3) else 1
                music.add(bass_note(root * octave, BEAT / 2 * 0.9, gain=0.5 if level == 1 else 0.7), bt)
        for k in range(16 if level >= 3 else 8):
            step = BEAT / 4 if level >= 3 else BEAT / 2
            bt = t + k * step
            if bt >= end - 0.01 or level < 2:
                break
            arp = ARPS[name][k % 8]
            music.add(pluck(hz(arp), 0.6, decay=4.5, gain=0.22 if level == 2 else 0.2), bt, pan=0.35 if k % 2 else -0.35)
            send_hall.add(pluck(hz(arp), 0.6, decay=4.5, gain=0.08), bt)
        for b in range(4):
            bt = t + b * BEAT
            if bt >= end - 0.01:
                break
            if level >= 2 or b % 2 == 0:
                drums.add(kick(gain=0.75 if level >= 2 else 0.55), bt)
                kicks.append(bt)
            if level >= 3 and b % 2 == 1:
                drums.add(clap(0.32), bt, pan=0.05)
                send_hall.add(clap(0.12), bt)
            drums.add(hat(0.24 if level >= 2 else 0.14), bt + BEAT / 2, pan=0.3)
            if level >= 3:
                drums.add(shaker(0.14), bt + BEAT / 4, pan=-0.4)
                drums.add(shaker(0.11), bt + 3 * BEAT / 4, pan=-0.4)
        t = bar_end
        i += 1


# --- Intro: three notes for "Be Right Back", the fold, the logo.
music.add(pad(AM, I["shield"] + 0.2, a=1.1, r=0.4, cutoff=1700, gain=0.42), 0.0)
for at, nm in ((I["w1"], "A4"), (I["w2"], "C5"), (I["w3"], "E5")):
    music.add(pluck(hz(nm), 1.2, decay=2.6, gain=0.34), at, pan=-0.15)
    send_hall.add(pluck(hz(nm), 1.2, decay=2.6, gain=0.22), at)
sfx.add(whoosh(0.58, 500, 4000, peak=0.92, pan0=0.3, pan1=-0.1, gain=0.22), I["shield"] - 0.56)
sfx.add(impact(0.62, sub0=110, sub1=40, length=1.6, bright=1800), I["shield"])
music.add(pad(chord(["A2", "E3", "A3", "C4", "E4", "B4"]), 1.1, a=0.005, r=0.8, cutoff=3200, gain=0.62), I["shield"])
for at, nm in ((I["shield"], "E6"), (I["shield"] + 0.06, "A6")):
    music.add(bell(hz(nm), 2.0, gain=0.14), at, pan=0.2)
    send_hall.add(bell(hz(nm), 2.0, gain=0.1), at)
send_hall.add(impact(0.25, length=1.2), I["shield"])
sfx.add(riser(ST["start"] - I["toMenu"] + 0.02, 250, 6000, gain=0.28), I["toMenu"])
sfx.add(impact(0.35, sub0=70, sub1=36, length=1.0, bright=600), ST["start"])

# --- The café, quietly, from the first shot to the put-back (and on after).
def cafe(dur):
    n = ns(dur)
    out = np.zeros((2, n))
    t = secs(n)
    for v in range(7):
        lfo = 0.5 + 0.5 * np.sin(2 * np.pi * (0.7 + rng.random() * 2.2) * t + rng.random() * 6)
        lfo *= 0.5 + 0.5 * np.sin(2 * np.pi * (0.13 + rng.random() * 0.3) * t + rng.random() * 6)
        voice = bp(noise(n), 260 + rng.random() * 200, 1200 + rng.random() * 900) * lfo**2
        out += pan2(voice, rng.uniform(-0.9, 0.9))
    out += pan2(bp(noise(n), 70, 300), 0) * 0.15
    for _ in range(int(dur / 1.3)):
        at = rng.random() * dur
        b = bell(3000 + rng.random() * 2500, 0.4, decay=4) * 0.25
        s = ns(at)
        m = min(len(b), n - s)
        out += pan2(np.pad(b[:m], (s, n - s - m)), rng.uniform(-0.9, 0.9))
    out = lp(out, 3000)
    return fades(out / 8, 0.8, 0.8)


amb.add(cafe(DUR - ST["start"] + 0.5), ST["start"] - 0.4, gain=0.55)

# --- Setup, arming, guarding: the groove builds.
# One grid from 2.5 s: Am, F, C, G, Am, building at each step.
groove(ST["start"], ST["start"] + 2.0, ["Am"], 1)
groove(ST["start"] + 2.0, G["start"], ["F", "C"], 2)
groove(G["start"], T["flood"], ["G", "Am"], 3)

sfx.add(click(0.5), A["clickIcon"], pan=0.5)
sfx.add(whoosh(0.22, 2500, 6000, peak=0.3, gain=0.06), A["panelOpen"])
sfx.add(click(0.55, f=2200), A["clickStart"], pan=0.3)
sfx.add(whoosh(0.2, 5000, 2000, peak=0.2, gain=0.05), A["panelClose"])
sfx.add(shimmer(1.6, gain=0.75), A["frost"])
send_hall.add(shimmer(1.6, gain=0.3), A["frost"])
for k in range(5):
    sfx.add(tick(1250 * 2 ** (k / 12 * 2), gain=0.26), A["count"] + k * A["step"], pan=0.0)
    send_room.add(tick(1250 * 2 ** (k / 12 * 2), gain=0.1), A["count"] + k * A["step"])
for at, nm in ((A["sign"], "E6"), (A["sign"] + 0.08, "B6")):
    sfx.add(bell(hz(nm), 1.4, gain=0.12), at)
    send_hall.add(bell(hz(nm), 1.4, gain=0.08), at)
sfx.add(impact(0.25, sub0=80, sub1=40, length=0.8, bright=900), A["sign"])

# Someone walks past; someone close to the lens wipes the frame.
for k in range(4):
    sfx.add(lp(tom(70, 0.25), 300), G["start"] + 0.35 + k * 0.42, pan=-0.6 + k * 0.35)
sfx.add(whoosh(0.6, 250, 1800, peak=0.55, pan0=0.8, pan1=-0.8, gain=0.4), G["wipe"] - 0.1)

# --- Touched: the red floods in, the music drops out.
sfx.add(click(0.4, f=1800), T["tap"], pan=0.2)
sfx.add(whoosh(0.22, 3000, 9000, peak=0.95, gain=0.2), T["flood"] - 0.2)
sfx.add(impact(0.95, sub0=120, sub1=32, length=2.2, bright=3200), T["flood"])
send_hall.add(impact(0.4, length=1.8), T["flood"])
tension.add(pad(chord(["A1", "Bb1", "E2"]), P["thud"] - T["flood"] + 0.5, a=0.4, r=0.4, cutoff=500, gain=0.55), T["flood"])


def beep_soft(dur):
    """BRB's soft stage: 880 Hz for 0.15 s every second, at half volume."""
    n = ns(dur)
    t = secs(n)
    gate = ((t % 1.0) < 0.15).astype(float) * 0.5
    gate = lp(gate, 400)
    return np.tanh(3 * np.sin(2 * np.pi * 880 * t)) / np.tanh(3) * gate


soft_from = T["flood"] + 0.05
siren_bus.add(beep_soft(L["siren"] - soft_from), soft_from, gain=0.32)

# Tension under the alarm: a pulse and a ticking hat.
t0 = L["siren"]
k = 0
while t0 + k * BEAT / 4 < P["thud"] - 0.05:
    bt = t0 + k * BEAT / 4
    if k % 4 == 0:
        tension.add(tom(62, 0.55), bt)
    tension.add(hat(0.06 + 0.04 * (k % 2)), bt, pan=0.25)
    tension.add(bass_note(hz("A2"), BEAT / 4 * 0.8, cutoff=420, gain=0.45), bt)
    k += 1
for kk in range(int((L["siren"] - T["flood"] - 0.3) / (BEAT / 4))):
    tension.add(hat(0.05), T["flood"] + 0.3 + kk * BEAT / 4, pan=0.25)

# --- Picked up: the siren, BRB's own.
sfx.add(whoosh(0.4, 300, 2200, peak=0.5, pan0=-0.2, pan1=0.2, gain=0.3), L["up"] - 0.12)
siren_len = P["thud"] - L["siren"]
n = ns(siren_len)
st = secs(n)
sweep = np.abs(((st / 1.2) % 1) * 2 - 1)
freq = 650 + 600 * sweep
siren = np.tanh(3 * np.sin(2 * np.pi * np.cumsum(freq) / SR)) / np.tanh(3)
siren = bp(siren, 380, 7500, 2)
siren = fades(siren, 0.01, 0.006)
# Behind the phone it's further away: quieter and duller, then back as it's put down.
far = np.clip((st + L["siren"] - PH["start"]) / 0.35, 0, 1) * (1 - np.clip((st + L["siren"] - (PH["end"] - 0.25)) / 0.3, 0, 1))
far = lp(far, 20)
dull = lp(siren, 1500)
siren_mix = siren * (1 - far) + dull * far * 0.9
siren_mix *= 1 - 0.55 * far
siren_bus.add(siren_mix, L["siren"], gain=0.36, pan=0.08)
send_room.add(siren_mix * 0.35, L["siren"])

# --- The phone.
sfx.add(whoosh(0.5, 400, 2500, peak=0.7, pan0=0.5, pan1=0.1, gain=0.22), PH["start"] - 0.1)
for at, nm in ((PH["island"], "B5"), (PH["island"] + 0.11, "E6")):
    sfx.add(bell(hz(nm), 1.6, gain=0.24), at, pan=0.25)
    send_hall.add(bell(hz(nm), 1.6, gain=0.12), at)
sfx.add(buzz(0.36, 0.3), PH["island"] + 0.02, pan=0.25)
sfx.add(click(0.32, f=3000), PH["tapOpen"], pan=0.25)
sfx.add(whoosh(0.3, 1200, 5000, peak=0.25, pan0=0.1, pan1=0.4, gain=0.16), PH["page"])
sfx.add(click(0.18, f=4200), 16.62, pan=0.3)
sfx.add(whoosh(0.5, 2500, 300, peak=0.4, pan0=0.4, pan1=0.0, gain=0.22), PH["end"] - 0.5)

# --- Put back: down, thud, and quiet.
sfx.add(whoosh(0.34, 1600, 300, peak=0.6, pan0=0.1, pan1=0.0, gain=0.25), P["down"])
sfx.add(thud(0.9), P["thud"])
send_room.add(thud(0.35), P["thud"])
music.add(pad(chord(["F2", "C3", "G3", "A3", "E4"]), TI["ok"] - P["thud"] - 0.5 + 0.6, a=1.1, r=0.5, cutoff=900, gain=0.3), P["thud"] + 0.9)

# --- Touch ID, and back.
sfx.add(click(0.22, f=1500), TI["press"], pan=0.3)
for k, nm in enumerate(("G5", "C6", "E6")):
    sfx.add(bell(hz(nm), 1.4, gain=0.15), TI["ok"] + k * 0.055, pan=0.2)
    send_hall.add(bell(hz(nm), 1.4, gain=0.1), TI["ok"] + k * 0.055)
music.add(pad(C, B["start"] - W["clear"] + 0.3, a=0.35, r=0.4, cutoff=1500, gain=0.5), W["clear"])
sfx.add(shimmer(1.2, gain=0.4), W["clear"])
sfx.add(impact(0.22, sub0=70, sub1=40, length=1.0, bright=500), W["clear"])
sfx.add(bell(hz("E6"), 1.2, gain=0.09), W["sign"], pan=-0.1)
# a light pulse while it welcomes you back
for k in range(int((W["shrink"] - W["sign"]) / (BEAT / 2))):
    bt = W["sign"] + 0.1 + k * BEAT / 2
    nm = ["C5", "G5", "E5", "G5", "B4", "G5", "D5", "G5"][k % 8]
    music.add(pluck(hz(nm), 0.5, decay=5, gain=0.16), bt, pan=0.3 if k % 2 else -0.3)
sfx.add(whoosh(W["land"] - W["shrink"] + 0.05, 800, 6000, peak=0.9, pan0=-0.3, pan1=0.4, gain=0.22), W["shrink"])
sfx.add(pop(hz("C6"), 0.32), W["land"], pan=0.35)
sfx.add(riser(B["start"] - W["land"], 400, 7000, gain=0.2), W["land"])
for k in range(8):
    drums.add(clap(0.06 + 0.02 * k), W["land"] - 0.3 + k * (B["start"] - W["land"] + 0.3) / 8)

# --- Everything it does: the full groove.
for i, (at, name) in enumerate(((B["start"], "F"), (B["start"] + 1.0, "Am"), (B["start"] + 2.0, "G"), (B["start"] + 3.0, "Gsus"))):
    end = min(at + 1.0, EN["icon"])
    music.add(pad(PADS[name], end - at + 0.2, a=0.05, r=0.2, cutoff=2300, gain=0.5), at)
    root = hz(ROOTS[name])
    for k in range(4):
        bt = at + k * BEAT / 2
        if bt < end - 0.01:
            music.add(bass_note(root * (2 if k % 2 else 1), BEAT / 2 * 0.85, gain=0.7), bt)
    for k in range(8):
        bt = at + k * BEAT / 4
        if bt < end - 0.01:
            music.add(pluck(hz(ARPS[name][k]), 0.5, decay=5, gain=0.18), bt, pan=0.35 if k % 2 else -0.35)
    for b in range(2):
        bt = at + b * BEAT
        if bt < end - 0.01:
            drums.add(kick(0.8), bt)
            kicks.append(bt)
            drums.add(hat(0.15), bt + BEAT / 2, pan=0.3)
            drums.add(shaker(0.09), bt + BEAT / 4, pan=-0.4)
            drums.add(shaker(0.07), bt + 3 * BEAT / 4, pan=-0.4)
    drums.add(clap(0.34), at + BEAT, pan=0.05)
    send_hall.add(clap(0.12), at + BEAT)
for i, nm in enumerate(("F5", "G5", "A5", "C6", "D6", "F6")):
    sfx.add(pop(hz(nm), 0.2), B["start"] + 0.2 + i * 0.16, pan=-0.5 + i * 0.2)
sfx.add(whoosh(0.35, 3000, 600, peak=0.3, gain=0.12), B["start"] + 0.2 + 5 * 0.16 + 0.45)
sfx.add(whoosh(0.4, 600, 7000, peak=0.95, gain=0.22), EN["icon"] - 0.4)

# --- The end card: the logo again, resolved.
sfx.add(impact(0.5, sub0=100, sub1=50, length=2.6, bright=1500), EN["icon"])
music.add(pad(chord(["C2", "C3", "G3", "C4", "E4", "G4", "D5"]), DUR - EN["icon"], a=0.01, r=1.2, cutoff=2600, gain=0.62, s=0.7), EN["icon"])
for at, nm in ((EN["icon"], "C6"), (EN["icon"] + 0.06, "G6"), (EN["icon"] + 0.12, "E7")):
    music.add(bell(hz(nm), 2.6, gain=0.12), at, pan=0.15)
    send_hall.add(bell(hz(nm), 2.6, gain=0.1), at)
send_hall.add(impact(0.3, length=2.0), EN["icon"])
music.add(pluck(hz("G5"), 1.0, decay=3, gain=0.14), EN["word"], pan=-0.2)
for k, nm in enumerate(("E6", "G6", "C7")):
    sfx.add(bell(hz(nm), 1.4, gain=0.07), EN["cta"] + k * 0.05, pan=0.3)
    send_hall.add(bell(hz(nm), 1.4, gain=0.06), EN["cta"] + k * 0.05)

# ---------------------------------------------------------------- mix

def duck_env(times, depth, rel):
    env = np.ones(N)
    t = secs(N)
    for k in times:
        s = int(k * SR)
        e = min(N, s + ns(rel * 3))
        if s >= N:
            continue
        x = t[s:e] - k
        env[s:e] = np.minimum(env[s:e], 1 - depth * np.exp(-x / rel))
    return env


sidechain = duck_env(kicks, 0.35, 0.09)
# Music steps back for the siren and for the moments that should be heard alone.
t_all = secs(N)
under_siren = np.clip((t_all - L["siren"]) / 0.2, 0, 1) * (1 - np.clip((t_all - P["thud"]) / 0.01, 0, 1))
# The groove stops dead as the red floods in, and nothing plays until it's put back.
music_gain = np.where((t_all >= T["flood"] + 0.03) & (t_all < P["thud"] + 0.5), 0.0, 1.0)
music_gain = signal.lfilter([1 - np.exp(-1 / (0.012 * SR))], [1, -np.exp(-1 / (0.012 * SR))], music_gain)
# The alarm's own music stops with the siren.
tension_gain = np.where(t_all < P["thud"], 1.0, 0.0)
tension_gain = signal.lfilter([1 - np.exp(-1 / (0.004 * SR))], [1, -np.exp(-1 / (0.004 * SR))], tension_gain)

mus = music.x * sidechain * music_gain
dr = drums.x * music_gain
# Less boom, more presence: these will mostly be heard on phones and laptops.
mus = mus - 0.35 * lp(mus, 90) + 0.4 * hp(mus, 3500)
dr = dr - 0.3 * lp(dr, 70) + 0.25 * hp(dr, 4000)
ten = tension.x * tension_gain * (1 - 0.3 * under_siren)
hall = reverb(send_hall.x + 0.12 * music.x * music_gain + 0.05 * sfx.x, make_ir(2.6, 0.02, 6000, seed=3))
room = reverb(send_room.x + 0.1 * sfx.x, make_ir(0.7, 0.008, 7000, seed=5))
amb_gain = 1 - 0.75 * under_siren
mix = 0.9 * mus + 0.85 * dr + 0.8 * ten + 1.0 * sfx.x + 1.0 * siren_bus.x + 0.9 * amb.x * amb_gain + 0.32 * hall + 0.28 * room
mix = hp(mix, 32, 4)

# A gentle bus compressor.
lvl = np.sqrt(lp(np.mean(mix**2, axis=0), 12) + 1e-12)
thr = 10 ** (-18 / 20)
gr = np.where(lvl > thr, (lvl / thr) ** (1 / 2.2 - 1), 1.0)
gr = lp(gr, 8)
mix *= gr

# The last half second fades.
fade = np.clip((DUR - t_all) / (DUR - EN["fade"]), 0, 1) ** 1.5
mix *= fade


def loudness(x):
    """Integrated loudness (ITU-R BS.1770 K-weighting with gating), LUFS."""
    b1, a1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585]
    b2, a2 = [1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]
    y = signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=-1), axis=-1)
    blk, hop = ns(0.4), ns(0.1)
    zs = np.array([np.mean(y[:, i : i + blk] ** 2, axis=1).sum() for i in range(0, y.shape[1] - blk, hop)])
    lk = -0.691 + 10 * np.log10(zs + 1e-12)
    zs = zs[lk > -70]
    rel = -0.691 + 10 * np.log10(zs.mean()) - 10
    zs = zs[-0.691 + 10 * np.log10(zs) > rel]
    return -0.691 + 10 * np.log10(zs.mean())


target = -14.0
mix *= 10 ** ((target - loudness(mix)) / 20)
# Soft-limit anything over -1 dBFS (4x oversampled peak check).
ceiling = 10 ** (-1.2 / 20)
over = np.abs(mix) > ceiling * 0.8
mix = np.where(over, np.sign(mix) * (ceiling * 0.8 + (ceiling * 0.2) * np.tanh((np.abs(mix) - ceiling * 0.8) / (ceiling * 0.2))), mix)
peak = np.max(np.abs(signal.resample_poly(mix, 4, 1, axis=-1)))
if peak > 10 ** (-1 / 20):
    mix *= 10 ** (-1 / 20) / peak

out = ROOT / "public" / "audio" / "soundtrack.wav"
out.parent.mkdir(parents=True, exist_ok=True)
dither = (rng.random(mix.shape) - rng.random(mix.shape)) / 32768
pcm = np.clip((mix + dither) * 32767, -32768, 32767).astype(np.int16)
wavfile.write(out, SR, pcm.T)
print(f"wrote {out.relative_to(ROOT)}: {DUR:.1f} s, {loudness(mix):.1f} LUFS, peak {20 * np.log10(np.max(np.abs(mix))):.1f} dBFS")
