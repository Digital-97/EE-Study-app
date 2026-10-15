# EE Study

A Duolingo-style study app for first- to third-year Electrical Engineering students, built with Flutter (Android first).

- **Levels → subjects → units → lessons.** Pick a level (*Year 1 – Basics*, *Year 1 – Advanced*, *Year 2 – Basics*, *Year 2 – Advanced*, *Year 3 – Basics*, *Year 3 – Advanced*), choose a subject, and work through a path of short (3–5 minute) lessons.
- **Learn, practice, challenge.** Lessons mix short concept cards with exercises: multiple choice, true/false, numeric answers with units and SI prefixes (`4.7k`, `2.5m`, `10µ`), match the pairs, and put the steps in order.
- **Randomized values.** Most calculation questions draw new values every time, so students learn the method instead of memorizing answers.
- **Circuit solver.** Exercises can be backed by a DC circuit solver (nodal analysis) that works out every voltage, current, power and equivalent resistance from the schematic itself. The *Circuit Lab* subjects use it for endless randomized "find the voltage across R5" problems.
- **Interactive graphs.** Sliders on graphs (damping, cutoff frequency, gain, aliasing, load lines…) redraw the curve live, and "adjust the graph" exercises ask you to drag a slider until the graph matches a target. Graphs include Bode plots, pole-zero maps and Smith charts.
- **AC Circuit Lab.** Randomized AC circuits solved with phasors (impedances, dividers, nodal analysis, power, Thévenin, op-amp filters), with step-by-step worked solutions.
- **Study material.** Every unit has a set of study cards (definitions, formulas, worked examples, schematics) and references the matching sections of the textbooks:
  - Hambley, *Electrical Engineering: Principles and Applications* (Years 1–2)
  - Phillips, Parr & Riskin, *Signals, Systems, and Transforms* (Signals & Systems, Discrete-Time Signals & Systems)
  - Horowitz & Hill, *The Art of Electronics* (Analog Electronics, plus cross-references in Year 1)
  - Ott, *Electromagnetic Compatibility Engineering* (EMC)
  - Frenzel, *Principles of Electronic Communication Systems* (Communication Systems)
  - Erickson & Maksimović, *Fundamentals of Power Electronics* (Power Electronics)
  - Oppenheim & Schafer, *Discrete-Time Signal Processing* (Digital Signal Processing)
  - Franklin, Powell & Emami-Naeini, *Feedback Control of Dynamic Systems* (Modern & Digital Control)
  - Leon-Garcia, *Probability, Statistics, and Random Processes for Electrical Engineering* (Probability & Random Signals)
  - Glover, Overbye & Sarma, *Power System Analysis and Design* (Power Systems)
  - Pozar, *Microwave Engineering* (RF & Microwave)
  - Neamen, *Semiconductor Physics and Devices* (Semiconductor Devices)
  - Cover & Thomas, *Elements of Information Theory*; Lin & Costello, *Error Control Coding* (Information Theory & Coding)
- **No hearts.** Wrong answers come back later in the lesson with new numbers, and go to a review list until you answer them correctly twice.
- **Progress saved on the device.** XP, daily goal, streak, completed lessons and the review list are stored locally.

## Install on Android

1. Open the [latest release](https://github.com/Digital-97/EE-Study-app/releases/latest) on your phone (in the GitHub app or a browser).
2. Under **Assets**, tap **EE-Study.apk** to download it.
3. Open the downloaded file and tap **Install**. The first time, Android asks you to allow installing apps from this source (your browser or the GitHub app). If Play Protect warns about an unrecognized app, choose **Install anyway**.

Every push builds a new release. Installing a newer build over an older one keeps your progress.

## Content

| Level | Subjects |
|---|---|
| Year 1 – Basics | Circuit Theory · Circuit Lab · Digital Logic |
| Year 1 – Advanced | Capacitors, Inductors & Transients · AC Circuits · Frequency Response & Filters · Semiconductors · Amplifiers & Op Amps · Circuit Lab II · AC Circuit Lab |
| Year 2 – Basics | Signals & Systems I · Electromagnetics · Magnetic Circuits & Transformers · Digital Systems & Microcontrollers |
| Year 2 – Advanced | Signals & Systems II · Control Systems · Electric Machines & Power · Instrumentation & Measurement |
| Year 3 – Basics | Discrete-Time Signals & Systems · Analog Electronics · Electromagnetic Compatibility · Communication Systems |
| Year 3 – Advanced | Power Electronics · Digital Signal Processing · Modern & Digital Control · Probability & Random Signals · Power Systems · RF & Microwave · Semiconductor Devices · Information Theory & Coding |

All content is JSON in [`assets/content/`](assets/content/). See [`CONTENT_GUIDE.md`](CONTENT_GUIDE.md) for the format: exercise types, random parameters, circuit diagrams and solved circuits. No code changes are needed to add lessons.

## Development

```sh
flutter pub get
flutter run                     # on a connected Android device or emulator
flutter test                    # unit tests, content validation and render smoke test
flutter build apk --release     # build an installable APK
```

Release builds are signed with the key in `~/.ee-study/` (or the `release-signing.properties` that `EE_STUDY_SIGNING` points to); the key is not in this repository. Without it, release builds use the debug key, which can't update an installed release. CI restores the key from the `RELEASE_KEYSTORE_BASE64` and `RELEASE_SIGNING_PROPERTIES` secrets.

Content tools:

```sh
# Validate one subject
CONTENT_SUBJECT=circuit-theory flutter test test/content_test.dart
# Render all circuit diagrams of a unit to PNG
CONTENT_SUBJECT=circuit-theory CONTENT_UNIT=ct-node PREVIEW_OUT=build/previews flutter test tool/circuit_preview_test.dart
# Dump all questions (with one random draw resolved) as text for review
CONTENT_SUBJECT=circuit-theory DUMP_OUT=build/dump flutter test tool/dump_content_test.dart
```

GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the analyzer and tests, builds the APK and publishes it as a GitHub Release.

## Code overview

```
lib/
  main.dart                    app entry, bottom navigation
  content/                     loads assets/content
  models/                      levels, subjects, units, lessons, steps, circuits
  engine/
    expression.dart            expression evaluator for random parameters
    units.dart                 SI-prefix formatting and parsing
    step_instance.dart         a randomized, ready-to-show exercise
    circuit_solver.dart        DC circuit solver (MNA) for solved circuits
  lesson/                      lesson session, lesson screen, exercise widgets
  screens/                     learn, subject path, study material, practice, profile
  state/progress_store.dart    locally saved progress (XP, streak, review list)
  widgets/                     circuit diagram renderer, LaTeX text, buttons
```
