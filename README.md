# GuitarTabScroller

A minimalist macOS app that scrolls guitar tab and sheet music PDFs hands-free — either at a steady speed, or triggered by a sound cue you record yourself (a click, a stomp, a spoken word).

Built with SwiftUI, PDFKit, AVFoundation, and Accelerate. No external dependencies.

## Why

Playing guitar with a tab open on a laptop means stopping mid-song to scroll or hit the arrow key. I wanted something that would either scroll on its own at a set pace, or flip pages when I made a sound — without installing a speech recognition model or depending on cloud APIs.

## Features

- Drag-and-drop any PDF
- **Auto-scroll** mode with adjustable speed (5–200 px/s)
- **Voice cue** mode: record any short sound once, and the app flips the page whenever it hears a match
- Keyboard shortcuts: `Space` play/pause, `←/→` page navigation
- Dark, single-window, zero-chrome UI

## How the voice cue works

The interesting part. Rather than shipping a speech recognition model (heavy, overkill for a single trigger word, and slow to start), the app does template matching on a spectral fingerprint.

When you click **Record cue**, the next above-threshold audio frame gets:

1. **Windowed** with a Hann function
2. **FFT'd** via Accelerate's `vDSP_fft_zrip`
3. **Log-compressed** magnitude spectrum
4. **Binned** into 32 linear frequency bands
5. **L2-normalized** into a 32-dimensional unit vector

That vector is the template. While listening, every incoming audio buffer gets the same treatment and is compared against the template via cosine similarity (one `vDSP_dotpr` call, since both vectors are already normalized).

To keep false positives low, a match only fires when all of the following are true:
- Cosine similarity ≥ adjustable threshold (default 0.88)
- RMS loudness is at least 50% of the recorded cue's loudness
- Two consecutive buffers match (rejects single-frame transients)
- Past the 0.8 s cooldown since the last fire

This runs with negligible CPU, has no startup latency, and works fully offline. It's great for percussive cues (clicks, claps, tongue clicks, foot stomps) which are exactly what you want for hands-busy guitar playing.

## Architecture

```
TabScrollerApp           // @main entry point, single WindowGroup
 └─ ContentView          // Layout: PDF area + control bar
     ├─ PDFViewRepresentable   // NSViewRepresentable wrapping PDFKit.PDFView
     ├─ ScrollerModel          // ObservableObject: playback state + mode
     │    └─ AudioCueEngine    // AVAudioEngine tap → vDSP FFT → cosine match
     └─ KeyCatcher             // NSView subclass for keyboard shortcuts
```

The auto-scroll loop runs on a 60 Hz timer that computes a delta and calls into the `NSScrollView` underlying `PDFView` — this gives smooth pixel-level scrolling rather than discrete page jumps.

## Build

Requires Xcode 15+ and macOS 13+.

```bash
git clone https://github.com/Bertram-Qian/GuitarTabScroller.git
open tab-scroller/GuitarTabScroller.xcodeproj
```

Hit ▶. First run, macOS will ask for microphone permission the first time you enter Voice cue mode.

## What I'd add next

- [ ] Save recent PDFs and last-read position
- [ ] Better audio recognition
- [ ] Per-section scroll speed (slow the verse, speed up the bridge)
- [ ] MIDI pedal input as an alternative trigger
- [ ] Multi-template support (different cues for next/previous)
- [ ] Optional `SFSpeechRecognizer` backend for full-word triggers

## License

MIT
