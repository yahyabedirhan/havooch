# Research: transcribe a local video on macOS

Ticket: #14 (`Research: Find the best way to transcribe a local video`). Spec: #1 (`Spec: Video Review v1`). Researched and measured on 2026-10-04.

## Question

What is the fastest, most reliable, cheapest and simplest way to transcribe a local video on macOS? How does each option compare with Apple SpeechAnalyzer? Which one should sit behind the spec's `Transcriber` interface?

The spec puts on-device transcription third, after the `voiceover.json` and `.srt`/`.vtt` sidecars. It starts in the background when a video opens and caches its result in Store. The `Transcript` module takes a video and a time window and returns timed lines. Each batch comment carries `transcript[]`, the timed lines from 15 s before to 15 s after the comment's time (#1, "Modules", "The batch payload", "Transcript sources, in order").

## Recommendation

**Use Apple SpeechAnalyzer with `SpeechTranscriber` as the on-device `Transcriber` source, as the spec already says.** Keep the sidecar sources ahead of it.

Why:

- **Fast enough, with nothing to load.** The 21.2 s fixture took 0.44 s wall clock, about 48x real time. The 212 s test file took 2.9 s, about 73x (see [Measurements](#measurements)), so a 30 min video takes about 25 s in the background. Only FluidAudio was faster (0.27 s and 0.71 s, about 300x). Every Whisper option was slower: 1.5 to 7 s on the fixture and 11 to 14 s on the long file.
- **Reliable on long audio in this test.** It kept every scene of the 212 s file, as did FluidAudio, WhisperKit and whisper.cpp `base.en`. whisper.cpp with `large-v3-turbo` dropped 5 of the 30 scenes, and parakeet-mlx dropped 2 sentences (see [Long-form check](#long-form-check)).
- **Cheapest and simplest.** It is a system framework: `import Speech`, no package, no model in the app bundle, no cloud cost. The model "is retained in system storage and does not increase the download or storage size of your application" ([WWDC25 277][wwdc277]). `AVAudioFile` opened `sample.mp4` directly, so the app needs no ffmpeg step (measured).
- **No permission prompt.** Apple says the authorization flow "only applies to speech recognition using SFSpeechRecognizer" ([permission doc][perm]). The measuring script ran with `SFSpeechRecognizer.authorizationStatus()` still `.notDetermined` and saw no prompt (measured). The older `SFSpeechRecognizer` failed on this Mac with `Siri and Dictation are disabled` (measured).
- **Fits `Transcriber` directly.** Each result is a sentence-like phrase with a `CMTimeRange`, and with `.audioTimeRange` each word run has its own range ([audioTimeRange][sa-timerange]). A phrase maps to one timed line; the words stay available if a later version wants them.

Accuracy did not decide it. All seven measured options transcribed the fixture with 0 word errors against `sample.srt`. The fixture is clean Kokoro TTS, so it cannot separate the models (see [Open questions](#open-questions)).

**Runner-up: FluidAudio** (Parakeet TDT v3 on Core ML and the Neural Engine). It was the fastest option measured, about 4x faster than SpeechAnalyzer, kept every scene, gives per-word timings with confidence, and is a SwiftPM package. It loses on cost and simplicity: a 470 MB model download from Hugging Face on first use (240 s here, download and compile), a third-party dependency that moves fast (v0.17.5), CC-BY-4.0 attribution for the weights, and 25 European languages only (no Japanese, Chinese or Korean, which SpeechTranscriber has). The speed gap does not matter for v1, because transcription runs once per video in the background and the result is cached. Put FluidAudio behind the same `Transcriber` interface later if SpeechTranscriber's accuracy on real speech falls short. Neither option covers Turkish (see [Open questions](#open-questions)).

### Answers to the ticket

- **Fastest:** FluidAudio (Parakeet TDT v3), 0.71 s for 212 s of audio; SpeechAnalyzer second at 2.9 s.
- **Most reliable:** SpeechAnalyzer, FluidAudio, WhisperKit and whisper.cpp `base.en` kept every scene of the long file; whisper.cpp turbo and parakeet-mlx dropped speech.
- **Cheapest:** every local option is free; SpeechAnalyzer also costs no app size and no model download by the app. The cloud option costs $0.006 per minute.
- **Simplest:** SpeechAnalyzer: one system framework, reads the mp4 directly, no permission prompt.
- **Compared with SpeechAnalyzer:** see the table below, one row per option, with speed, accuracy, cost, setup and model size.
- **Measured:** SpeechAnalyzer, whisper.cpp (three models), WhisperKit, parakeet-mlx and FluidAudio, on the fixture and a 212 s file.
- **For `Transcriber`:** SpeechAnalyzer (see [How it fits the spec](#how-it-fits-the-spec)).

## Comparison

One row per option. Times are measured on this Mac unless marked; "warm" excludes the first-run download and compile. RTFx is audio seconds per wall-clock second.

| Option | Version measured | Speed, 21 s fixture (warm wall) | Speed, 212 s file (warm wall, RTFx) | Fixture word errors | Long-form check (30 scenes) | Timestamps | Setup | Model size | Cost and license | Languages |
|---|---|---|---|---|---|---|---|---|---|---|
| **Apple SpeechAnalyzer + SpeechTranscriber** | macOS 26.5.1 (25F80), SDK 26.5 | **0.44 s** | **2.9 s, 73x** | 0 / 58 | **30 / 30** | phrase + per-word `CMTimeRange` | none (system framework); assets via `AssetInventory` | system-managed, not in app; size not published | free; Apple SDK | 30 locales, no `tr-TR` |
| Apple SFSpeechRecognizer (on-device) | macOS 26.5.1 | failed: `Siri and Dictation are disabled` | not run | — | — | per-word `SFTranscriptionSegment` | Info.plist key + user authorization + Siri/Dictation on | system | free; Apple SDK | per `supportedLocales`; one-minute limit documented for server requests |
| whisper.cpp, `large-v3-turbo` (Metal) | 1.9.4 (Homebrew), ggml 0.25.3 | 1.76 s | 11.4 s, 19x | 0 / 58 | 25 / 30 | segment; experimental word (`-ml 1`), DTW tokens | brew or C library / xcframework; needs 16 kHz WAV | 1.5 GiB | free; MIT code and weights | 98 in training data ([model card][whisper-card]) |
| whisper.cpp, `large-v3-turbo-q5_0` | 1.9.4 | 1.55 s | 11.5 s, 18x | 0 / 58 | 25 / 30; 30 / 30 with `-mc 0` (11.2 s) | as above | as above | 547 MiB | free; MIT | 98 |
| whisper.cpp, `base.en` | 1.9.4 | 0.47 s | 4.3 s, 49x | 0 / 58 | 30 / 30 | as above | as above | 142 MiB | free; MIT | English only |
| WhisperKit, `large-v3-v20240930_626MB` (ANE) | whisperkit-cli 1.1.0 | 7.1 s (4.7 s of it model load) | 14.1 s, 15x | 0 / 58 | 30 / 30 | segment + word (`wordTimestamps`, DTW) | SwiftPM; model download at runtime; first run 589 s (download + ANE compile) | 601 MB | free; MIT code and weights | 98 |
| parakeet-mlx, `parakeet-tdt-0.6b-v3` (MLX GPU) | 0.5.3, mlx 0.32.3 | 1.74 s | 5.6 s, 38x | 0 / 58 | 30 / 30, but 2 sentences lost | sentence + token | Python venv + ffmpeg; not usable from Swift | 2.3 GB (HF cache) | free; Apache-2.0 code, CC-BY-4.0 weights | 25 European |
| FluidAudio, Parakeet TDT v3 (ANE) | v0.17.5 @ `16c7dd6` | **0.27 s** | **0.71 s, 300x** | 0 / 58 | **30 / 30** | token + word, with confidence | SwiftPM; model download at runtime; first run 240 s (download + compile) | 470 MB | free; Apache-2.0 code, CC-BY-4.0 weights | 25 European |
| mlx-whisper | 0.4.3 (PyPI) | not run | not run | — | — | segment + word | Python only | per Whisper model | free; MIT | 98 |
| OpenAI API (`whisper-1`) | — | not run (cloud) | not run | — | — | segment + word (`whisper-1` only) | API key, upload, 25 MB limit | none local | $0.006 / min | 98 |
| Embedded caption track (AVFoundation) | — | instant if present | — | exact | — | per cue | none | none | free | whatever the file has |

## Measurements

### Machine and tools

- MacBook Pro, Apple M3 Pro, 11 cores (5 performance, 6 efficiency), 18 GB memory (`system_profiler SPHardwareDataType`).
- macOS 26.5.1 (25F80) (`sw_vers`). Swift 6.3.2, macOS SDK 26.5, Command Line Tools 26.5.0.
- ffmpeg 9.0.2, whisper.cpp 1.9.4 (with ggml 0.25.3), whisperkit-cli 1.1.0 (all Homebrew).
- Python 3.12 venv (uv): parakeet-mlx 0.5.3, mlx-whisper 0.4.3, mlx 0.32.3.
- FluidAudio `fluidaudiocli` built from `FluidInference/FluidAudio@16c7dd6a263223f42d1e2b23da8c3bceb81516d2` with `swift build -c release --product fluidaudiocli` (530 s build).

### Inputs

- `fixtures/sample/sample.mp4`: 21.248 s container, 3 Kokoro TTS scenes, ground truth in `sample.srt` (58 words).
- `sample16k.wav`: `ffmpeg -i fixtures/sample/sample.mp4 -ar 16000 -ac 1 -c:a pcm_s16le sample16k.wav`.
- `long16k.wav`: the same WAV joined 10 times with the ffmpeg concat demuxer, 212.48 s, 30 sentences. It measures speed on longer audio and checks that no sentence is dropped. Exact repeats are a hard case for Whisper's previous-text conditioning, so read the long-form column as a stress test, not a WER.
- The fixture has no embedded subtitle or caption track: `ffprobe -show_entries stream=index,codec_type` lists only video and audio.

### Commands

All throwaway scripts and outputs are in `.scratch/` (ignored). Times are `/usr/bin/time -p` wall clock, best of 2 or 3 warm runs.

```sh
# Apple SpeechAnalyzer: .scratch/tx/speechanalyzer.swift (SpeechTranscriber en-US,
# attributeOptions [.audioTimeRange], AssetInventory check, analyzeSequence(from: AVAudioFile))
swiftc -O -parse-as-library speechanalyzer.swift -o speechanalyzer
./speechanalyzer fixtures/sample/sample.mp4      # reads the mp4 directly
./speechanalyzer long16k.wav

# Apple SFSpeechRecognizer: .scratch/tx/sfspeech.swift (SFSpeechURLRecognitionRequest,
# requiresOnDeviceRecognition = true)
./sfspeech fixtures/sample/sample.mp4

# whisper.cpp (Metal backend loaded: "GPU name: MTL0 (Apple M3 Pro)")
whisper-cli -m ggml-large-v3-turbo.bin -f sample16k.wav -l en -osrt -of out
whisper-cli -m ggml-large-v3-turbo-q5_0.bin -f sample16k.wav -l en -ml 1 -sow -osrt -of words
whisper-cli -m ggml-large-v3-turbo-q5_0.bin -f long16k.wav -l en -mc 0 -osrt -of out   # no previous-text context

# WhisperKit
whisperkit-cli transcribe --audio-path fixtures/sample/sample.mp4 \
  --model large-v3-v20240930_626MB --language en --word-timestamps --report

# parakeet-mlx (default model mlx-community/parakeet-tdt-0.6b-v3)
parakeet-mlx sample16k.wav --output-format json

# FluidAudio (default model parakeet-tdt-0.6b-v3-coreml)
fluidaudiocli transcribe sample16k.wav --word-timestamps --output-json out.json
```

ggml models came from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<model>.bin`.

### Results

| Option | Fixture runs (wall, s) | Long file runs (wall, s) | First run (wall, s) | Notes |
|---|---|---|---|---|
| SpeechAnalyzer | 1.54, 0.47, 0.44 | 2.84, 3.03 | 1.54 | `en-US` assets were already installed; the asset check took 0.06 s warm, 0.47 s first |
| whisper.cpp `base.en` | 21.34, 0.47 | 4.62, 4.30 | 21.34 | first run includes Metal shader compile |
| whisper.cpp `large-v3-turbo` | 2.62, 1.76 | 11.15, 11.37 | 2.62 | `whisper_print_timings: total time = 1648.74 ms` |
| whisper.cpp `large-v3-turbo-q5_0` | 2.24, 1.55 | 11.81, 11.52 (`-mc 0`: 11.15) | 2.24 | |
| WhisperKit `626MB` | 589.40, 7.08, 7.07 | 14.14 | 589.40 | first run downloads 601 MB and compiles for the ANE; warm load 1.4 to 4.7 s; CLI reports speed factor 14.1x (fixture), 17.0x (long) excluding load |
| parakeet-mlx v3 | 3.13, 1.74 | 5.60, 5.68 | 1045.67 | first run downloads 2.3 GB |
| FluidAudio v3 | 240.19, 0.27, 0.27 | 0.70, 0.71 | 240.19 | first run downloads 470 MB and compiles for the ANE; the CLI reports 0.13 s processing (161x) on the fixture and 0.56 s (378x) on the long file |

Model downloads ran on a slow link during this test (about 1 to 2.5 MB/s), so first-run times say more about the network than the tool.

### Accuracy on the fixture

Word errors against `sample.srt`, after lower-casing, dropping punctuation and splitting hyphens (`.scratch/tx/wer.py`):

| Option | Errors / words |
|---|---|
| SpeechAnalyzer | 0 / 58 |
| whisper.cpp `base.en`, `large-v3-turbo`, `large-v3-turbo-q5_0` | 0 / 58 each |
| WhisperKit `626MB` | 0 / 58 |
| parakeet-mlx v3 | 0 / 58 |
| FluidAudio v3 | 0 / 58 |

Only casing and punctuation differ, for example "video review" for "Video Review" (all), "Command-Enter" (whisper.cpp turbo) and "Command Enter" (WhisperKit, Parakeet).

SpeechAnalyzer output, phrase and word ranges (excerpt):

```text
SEG [0.00-1.56] This is video review.
  WORDS [0.00-0.48]This [0.48-0.60] is [0.60-0.84] video [0.84-1.50] review.
SEG [5.16-13.20]  Your comments queue up. Press command enter, and they go to your agent as one batch, with the time, the frame, and the transcript.
  WORDS [5.16-6.42] Your [6.42-6.84] comments [6.84-7.20] queue [7.20-7.50] up. [7.50-8.10] Press [8.10-8.52] command [8.52-9.06] enter, ...
SEG [17.46-19.98]  No copying and no screenshots.
```

### Timestamp accuracy

`ffmpeg -af silencedetect=noise=-40dB:d=0.3` on the fixture gives the true speech onsets after each pause: 0.32, 1.84, 6.38, 7.87, 14.65 and 18.15 s.

| Onset (true) | SpeechAnalyzer | whisper.cpp turbo `-ml 1` | WhisperKit | parakeet-mlx | FluidAudio |
|---|---|---|---|---|---|
| "This" (0.32) | 0.00 | 0.32 | 0.10 | 0.16 | 0.08 |
| "Pause" (1.84) | 1.56 | 1.87 | 1.50 | 1.76 | 1.68 |
| "Your" (6.38) | 5.16 | 6.00 | 6.40 | 6.00 | 5.92 |
| "Press" (7.87) | 7.50 | 8.00 | 7.88 | 7.68 | 7.60 |
| "The" (14.65) | 13.56 | 14.00 | 14.52 | 14.32 | 14.24 |

SpeechAnalyzer's word ranges are gap-free: a word starts where the previous one ended, so a word after a pause starts up to 1.2 s early. Its word ends match the silence starts within 0.3 s (for example "comment." ends at 5.04 against 5.19, "transcript." at 13.14 against 13.45). whisper.cpp's default segments land on whole seconds here (0, 6, 14). For a ±15 s transcript window every option is precise enough; WhisperKit is the most exact.

### Long-form check

Phrase counts in the 212 s output (10 loops of 3 scenes); each should be 10:

| Option | "This is video review" | "Pause any video" | "queue up" | "right inside the player" | "screenshots" |
|---|---|---|---|---|---|
| SpeechAnalyzer | 10 | 10 | 10 | 10 | 10 |
| whisper.cpp `base.en` | 10 | 10 | 10 | 10 | 10 |
| whisper.cpp `large-v3-turbo` | 11 | 11 | 10 | **5** | **5** |
| whisper.cpp `large-v3-turbo-q5_0` | 9 | 11 | 10 | **5** | **5** |
| whisper.cpp `large-v3-turbo-q5_0 -mc 0` | 10 | 10 | 10 | 9 | 10 |
| WhisperKit `626MB` | 10 | 10 | 10 | 10 | 10 |
| parakeet-mlx v3 | 10 | **8** | 10 | 10 | 10 |
| FluidAudio v3 | 10 | 10 | 10 | 10 | 10 |

whisper.cpp turbo skipped the third scene in 5 of the 10 loops (5 of 30 scenes) and once wrote "Pause any video review." This is the documented Whisper failure: "predictions may include texts that are not actually spoken" and repeated text ([Whisper model card][whisper-card]). Turning off previous-text context (`-mc 0`) fixed most of it. parakeet-mlx lost the "Pause any video ..." sentence at 63.8 s and 191.2 s, near its chunk boundaries.

## Per-option notes

### Apple SpeechAnalyzer and SpeechTranscriber

- `SpeechAnalyzer`, `SpeechTranscriber` and `AssetInventory` are available from macOS 26.0 (Speech.framework `.swiftinterface` in SDK 26.5). The spec targets macOS 26 (#1), so no fallback for older systems is needed.
- It is a new on-device model for "long-form and distant audio, such as lectures, meetings, and conversations", faster than the model behind SFSpeechRecognizer. It already runs Notes, Voice Memos and Journal ([WWDC25 277][wwdc277]).
- The model lives in system storage, outside the app's memory, and the system updates it ([WWDC25 277][wwdc277]). Assets are downloaded from Apple and shared between apps. An app reserves locales, and the system "may unsubscribe your app from assets that haven't been used in a while" ([AssetInventory][assetinventory]). On this Mac `maximumReservedLocales` is 5.
- File input: `analyzeSequence(from: AVAudioFile)`, `start(inputAudioFile:finishAfterFile:)` and `init(inputAudioFile:modules:)` ([SpeechAnalyzer][sa]). `AVAudioFile` read the AAC track of `sample.mp4` with no conversion (measured). "The analyzer can only analyze one input sequence at a time" ([SpeechAnalyzer][sa]).
- Timestamps: `ResultAttributeOption.audioTimeRange` "includes time-code attributes in a transcription's attributed string" ([audioTimeRange][sa-timerange]); presets `timeIndexedProgressiveTranscription` and `timeIndexedTranscriptionWithAlternatives` turn it on ([Preset][sa-preset]). Apple: "timecodes are precise down to an individual audio sample" ([WWDC25 277][wwdc277]). Measured: per-word ranges, 5 finalized phrases for the fixture.
- Locales: `SpeechTranscriber.supportedLocales` returned 30 on this Mac (de, en, es, fr, it, ja, ko, pt, yue, zh variants), with no Turkish. `DictationTranscriber` covers 54, including `tr-TR`, with the older model ([DictationTranscriber][dictation]).
- `SpeechTranscriber.isAvailable` is hardware dependent and returned true here ([SpeechTranscriber][st]).
- Apple publishes no WER for it, and no size for its assets.

### Apple SFSpeechRecognizer

- Apple says to plan for "a one-minute limit on audio duration" and per-day limits, because it is "a network-based service" ([SFSpeechRecognizer][sfsr]). `requiresOnDeviceRecognition` keeps audio on the Mac, but "on-device requests won't be as accurate" ([requiresOnDeviceRecognition][sfondevice]).
- It needs `NSSpeechRecognitionUsageDescription` and `requestAuthorization` ([permission doc][perm]).
- Per-word timing through `SFTranscriptionSegment` (`timestamp`, `duration`) ([SFTranscriptionSegment][sfseg]).
- Measured: on this Mac, with Siri and Dictation off, the on-device request failed at once with `kLSRErrorDomain Code=201 "Siri and Dictation are disabled"`. WWDC25 notes that the new API removes the need for users "to go into Settings and turn on Siri or keyboard dictation" ([WWDC25 277][wwdc277]). Do not use it.

### whisper.cpp

- `ggml-org/whisper.cpp`, latest release v1.9.4 (2026-09-11), read at commit `60c0be6ac8fa71b1a2ae2dd938a31a34a508e774`. MIT license (`LICENSE`).
- "On Apple Silicon, the inference runs fully on the GPU via Metal" (`README.md`). An optional Core ML encoder on the ANE is "more than x3 faster compared with CPU-only", but it needs `coremltools`, a `-DWHISPER_COREML=1` build and a slow first run (`README.md`). Not measured here; the Homebrew build uses Metal.
- `whisper-cli` "currently runs only with 16-bit WAV files" (`README.md`), so the app would decode the video's audio first (AVFoundation can do this).
- Output: `-osrt`, `-ovtt`, `-ocsv`, `-oj`, `-ojf` (`examples/cli/cli.cpp`). Word timestamps with `-ml 1` are "experimental"; DTW token timestamps (`-dtw`) are also marked experimental (`include/whisper.h`).
- Model sizes from `models/README.md`: tiny 75 MiB, base 142 MiB, small 466 MiB, medium 1.5 GiB, large-v3 2.9 GiB, large-v3-turbo 1.5 GiB, large-v3-turbo-q5_0 547 MiB.
- Swift: the README shows a SwiftPM `.binaryTarget` on the release xcframework, but v1.9.3 and v1.9.4 ship no release assets; the newest prebuilt xcframework is in v1.9.2 (2026-08-04).
- Measured: fast once warm, but the turbo models dropped sentences on the long file, and `base.en` is English only.

### WhisperKit

- Now `argmaxinc/argmax-oss-swift` (old `argmaxinc/WhisperKit` redirects), latest release v1.1.0 (2026-08-06), read at `f4e5d6be37ec820614fb0d72037e76c22d4c16f7`. MIT (`LICENSE`).
- SwiftPM product `WhisperKit`, only default dependency `swift-argument-parser` (`Package.swift`). `DecodingOptions.wordTimestamps` gives DTW word timings (`Sources/WhisperKit/Core/Configurations.swift`, `Core/Text/SegmentSeeker.swift`). Reads audio with `AVAudioFile` (`Core/Audio/AudioProcessor.swift`).
- Models download at runtime from `argmaxinc/whisperkit-coreml` on Hugging Face (MIT). The README recommends `large-v3-v20240930_626MB` for accuracy and `_turbo` on macOS.
- Real-time and custom-vocabulary features are in the commercial Argmax Pro SDK, not the open package (`README.md`).
- Measured: correct and complete, the best word timing, but the slowest warm option here and a 589 s first run.

### MLX: mlx-whisper and parakeet-mlx

- `mlx-whisper` 0.4.3 (PyPI, MIT), `transcribe(..., word_timestamps=True)` (`ml-explore/mlx-examples@796f5b53`, `whisper/README.md`). Python only. Not measured: it runs the same Whisper weights as whisper.cpp, and a Python runtime does not fit a SwiftPM app.
- `parakeet-mlx` 0.5.3 (PyPI, 2026-10-01, Apache-2.0), `senstella/parakeet-mlx@2d9748c0`. Default model `mlx-community/parakeet-tdt-0.6b-v3`. Gives sentences with token timings, srt/vtt/json output (`README.md`). Python only. Measured: fast, but lost 2 sentences on the long file.
- NVIDIA `parakeet-tdt-0.6b-v3`: 600M parameters, 25 European languages, word/segment/char timestamps, CC-BY-4.0, "ready for commercial/non-commercial use"; average WER FLEURS 11.97 %, MLS 7.83 % ([model card][parakeet-v3]). The English-only v2 lists an Open ASR average WER of 6.05 ([model card][parakeet-v2]).

### FluidAudio (Parakeet on Core ML)

- `FluidInference/FluidAudio`, latest release v0.17.5 (2026-10-01), read and built at `16c7dd6a263223f42d1e2b23da8c3bceb81516d2`. Apache-2.0 code (`README.md`), CC-BY-4.0 models on Hugging Face.
- SwiftPM, swift-tools 6.0, macOS 14 (`Package.swift`). Word timings via `ASRResult.tokenTimings` and `buildWordTimings(from:)` (`Sources/FluidAudio/ASR/Parakeet/AsrTypes.swift`).
- Its own claims: "~190x on M4 Pro (1 hour in ~19 s)" (`README.md`); v3 download ~480 MB, LibriSpeech test-clean WER 2.27 % (`Documentation/Benchmarks.md`, M5 Pro).
- Measured: the fastest option here (0.27 s fixture, 0.71 s long file, warm), complete on the long file, 0 errors on the fixture, and per-word timings with confidence in its JSON (`wordTimings`). The first run downloaded 470 MB into the `--model-dir` and took 240 s. Building the CLI from source took 530 s; an app would link the `FluidAudio` library product instead.

### Embedded caption tracks (AVFoundation)

- `AVMediaCharacteristicLegible` covers subtitle and closed-caption tracks; mp4 text formats include `tx3g`, `wvtt` and CEA-608 (SDK headers `AVMediaFormat.h`, `CMFormatDescription.h`). `AVAssetReaderOutputCaptionAdaptor` reads `AVCaptionGroup`s from a timed-text track (macOS 12+, `AVAssetReaderOutput.h`).
- When a video carries such a track, it is a free, exact source. The fixture has none. It would be a new source between the `.srt` sidecar and SpeechAnalyzer. It is not in the spec's list; see [Open questions](#open-questions).

### Cloud API (OpenAI, for comparison)

- `whisper-1` costs $0.006 per minute ([whisper-1][oai-whisper]) and is the only model with `timestamp_granularities[]` (word, segment) ([speech-to-text guide][oai-guide]). Uploads are limited to 25 MB ([speech-to-text guide][oai-guide]).
- It needs a network, a key and an upload of the person's audio. The spec asks for on-device transcription (#1), and the local options are both free and faster here. Not measured.

## How it fits the spec

- **Source order.** Keep the spec's order: `voiceover.json`, then `.srt`/`.vtt`, then SpeechAnalyzer (#1). The fixture has both sidecars, so SpeechAnalyzer only runs for videos without them.
- **`Transcriber` shape.** Run SpeechAnalyzer once over the whole file in the background, store each finalized result as a timed line (`start`, `end`, `text`), and cache the lines in Store keyed by the content hash (#1). The window cut (15 s before to 15 s after `time`) stays a pure function over cached lines, so the unit tests of the `Transcript` module never touch Speech.
- **Input.** Open the video with `AVAudioFile(forReading:)` and pass it to `analyzeSequence(from:)`; no ffmpeg and no temp WAV (measured on the fixture mp4).
- **Assets.** Before the first run, call `AssetInventory.assetInstallationRequest(supporting:)` and `downloadAndInstall()` for the chosen locale. If it is not ready yet, the comment payload can carry an empty `transcript[]` until the cache fills.
- **Locale.** `SpeechTranscriber` takes a locale. Pick `SpeechTranscriber.supportedLocale(equivalentTo: .current)` (declared in the SDK 26.5 `.swiftinterface`), else `en-US` (#1 does not say).
- **Line length.** SpeechAnalyzer phrases here ran 2.5 to 8 s, similar to the sidecar cues. A long phrase that crosses the window edge should be included whole.

## Open questions

1. **Accuracy on real speech.** The fixture is clean TTS, so every option scored 0 errors. A test on a recorded voice (accents, noise, technical words such as "SwiftPM") would separate SpeechTranscriber from Whisper and Parakeet. Apple publishes no WER.
2. **First-time asset download.** `en-US` assets were already on this Mac, so the cost of a first `downloadAndInstall()` (size and time) is unmeasured, and Apple does not publish the size.
3. **Bundled app behavior.** SpeechAnalyzer ran without a prompt from an unbundled binary. Confirm the same in the signed `.app` (the handoff warns that macOS may ask for Speech Recognition permission).
4. **Language.** No automatic language detection was found in the SpeechTranscriber docs; the app must choose a locale. Turkish needs `DictationTranscriber` or a Whisper option.
5. **Embedded caption tracks.** Should the spec add them as a source after the `.srt`/`.vtt` sidecar? They cost nothing when present.

## Sources

Apple:

- [wwdc277]: WWDC25 session 277, "Bring advanced speech-to-text to your app with SpeechAnalyzer", https://developer.apple.com/videos/play/wwdc2025/277/
- [sa]: SpeechAnalyzer, https://developer.apple.com/documentation/speech/speechanalyzer
- [st]: SpeechTranscriber, https://developer.apple.com/documentation/speech/speechtranscriber
- [sa-timerange]: `SpeechTranscriber.ResultAttributeOption.audioTimeRange`, https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange
- [sa-preset]: `SpeechTranscriber.Preset`, https://developer.apple.com/documentation/speech/speechtranscriber/preset
- [assetinventory]: AssetInventory, https://developer.apple.com/documentation/speech/assetinventory
- [dictation]: DictationTranscriber, https://developer.apple.com/documentation/speech/dictationtranscriber
- [perm]: Asking permission to use speech recognition, https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition
- [sfsr]: SFSpeechRecognizer, https://developer.apple.com/documentation/speech/sfspeechrecognizer
- [sfondevice]: `requiresOnDeviceRecognition`, https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
- [sfseg]: SFTranscriptionSegment, https://developer.apple.com/documentation/speech/sftranscriptionsegment
- macOS SDK 26.5 headers and interfaces: `Speech.framework` `.swiftinterface`, `AVFoundation.framework/Headers/AVMediaFormat.h`, `AVAssetReaderOutput.h`, `CoreMedia.framework/Headers/CMFormatDescription.h`.

Projects (cloned into `~/Developer/open-source/`):

- `ggml-org/whisper.cpp` @ `60c0be6ac8fa71b1a2ae2dd938a31a34a508e774` (release v1.9.4): `README.md`, `models/README.md`, `examples/cli/cli.cpp`, `include/whisper.h`, `LICENSE`.
- `argmaxinc/argmax-oss-swift` (formerly `argmaxinc/WhisperKit`) @ `f4e5d6be37ec820614fb0d72037e76c22d4c16f7` (release v1.1.0): `README.md`, `Package.swift`, `Sources/WhisperKit/Core/Configurations.swift`, `Core/Text/SegmentSeeker.swift`, `Core/Audio/AudioProcessor.swift`, `LICENSE`.
- `FluidInference/FluidAudio` @ `16c7dd6a263223f42d1e2b23da8c3bceb81516d2` (release v0.17.5): `README.md`, `Package.swift`, `Documentation/Benchmarks.md`, `Sources/FluidAudio/ASR/Parakeet/AsrTypes.swift`.
- `senstella/parakeet-mlx` @ `2d9748c04aca31405274a13c20ef9b62f1a73351` (PyPI 0.5.3): `README.md`.
- `ml-explore/mlx-examples` @ `796f5b53cab69a3d48a44233ce21aae889e94a08` (PyPI `mlx-whisper` 0.4.3): `whisper/README.md`.
- [whisper-card]: `openai/whisper` @ `86098128c0b4f24f0e2aa2994de830614b474227`: `README.md`, `model-card.md`.

Model cards and APIs:

- OpenAI `whisper-large-v3-turbo`, https://huggingface.co/openai/whisper-large-v3-turbo
- [parakeet-v3]: NVIDIA `parakeet-tdt-0.6b-v3`, https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- [parakeet-v2]: NVIDIA `parakeet-tdt-0.6b-v2`, https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2
- WhisperKit Core ML models, https://huggingface.co/argmaxinc/whisperkit-coreml
- [oai-whisper]: OpenAI `whisper-1`, https://platform.openai.com/docs/models/whisper-1
- [oai-guide]: OpenAI speech-to-text guide, https://platform.openai.com/docs/guides/speech-to-text

[wwdc277]: https://developer.apple.com/videos/play/wwdc2025/277/
[sa]: https://developer.apple.com/documentation/speech/speechanalyzer
[st]: https://developer.apple.com/documentation/speech/speechtranscriber
[sa-timerange]: https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange
[sa-preset]: https://developer.apple.com/documentation/speech/speechtranscriber/preset
[assetinventory]: https://developer.apple.com/documentation/speech/assetinventory
[dictation]: https://developer.apple.com/documentation/speech/dictationtranscriber
[perm]: https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition
[sfsr]: https://developer.apple.com/documentation/speech/sfspeechrecognizer
[sfondevice]: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
[sfseg]: https://developer.apple.com/documentation/speech/sftranscriptionsegment
[whisper-card]: https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/model-card.md
[parakeet-v3]: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
[parakeet-v2]: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2
[oai-whisper]: https://platform.openai.com/docs/models/whisper-1
[oai-guide]: https://platform.openai.com/docs/guides/speech-to-text
