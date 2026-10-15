# Roadmap

## In progress

- [x] Progress backup and restore (save to file, share, restore)
- [x] Daily reminder notification (skipped on days you already studied)
- [x] Spaced-repetition review (Leitner boxes: 1, 3, 7, 16, 35 days)
- [x] Exam mode: timed, mixed questions, feedback at the end, score per unit
- [x] Step-by-step worked solutions for Circuit Lab problems
- [x] Graph exercises (RC/RL curves, Bode plots, I–V characteristics, waveforms)
- [x] Tap-the-schematic questions
- [x] Year 2 content: Signals & Systems I/II, Electromagnetics, Magnetic Circuits & Transformers, Digital Systems & Microcontrollers, Control Systems, Electric Machines & Power, Instrumentation & Measurement
- [x] Year 3 content: Discrete-Time Signals & Systems (Phillips), Analog Electronics (Horowitz & Hill), Electromagnetic Compatibility (Ott), Communication Systems (Frenzel)
- [x] Year 3 – Advanced content: Power Electronics (Erickson & Maksimović), Digital Signal Processing (Oppenheim & Schafer), Modern & Digital Control (Franklin, Powell & Emami-Naeini), Probability & Random Signals (Leon-Garcia), Power Systems (Glover, Overbye & Sarma), RF & Microwave (Pozar), Semiconductor Devices (Neamen), Information Theory & Coding (Cover & Thomas; Lin & Costello)

## Learning features

- [x] Interactive graphs with sliders, and "adjust the graph" exercises
- [x] AC Circuit Lab: randomized phasor circuits with worked solutions

## Later

### Going public

When the repository becomes public:

- [x] Move the release signing key out of the repository into GitHub Actions
  secrets (and keep the same key, so installed apps can still update).
- In-app update notice: check the latest GitHub release at startup and offer
  to download a newer APK.

### Accounts, sync and leaderboards

Goal: log in, keep progress across devices, and compete with friends on
weekly XP.

**Self-hosted on Windows (preferred).** [PocketBase](https://pocketbase.io) is a
single `pocketbase.exe` with official Windows builds and needs no Linux, Docker or
WSL. It provides:

- user accounts (email/password, Google login), a database (SQLite) and an admin
  web UI
- realtime updates, useful for a live friends leaderboard
- a Dart/Flutter client package (`pocketbase` on pub.dev)

Running it: download the Windows zip, run `pocketbase.exe serve --http=0.0.0.0:8090`,
and install it as a Windows service (e.g. with NSSM) so it starts on boot. To
reach it from phones outside the home network, use a tunnel instead of opening
router ports: **Cloudflare Tunnel** (`cloudflared` has a Windows installer and
gives an HTTPS address) or **Tailscale** (private network for you and your friends).

**Hosted alternative.** Firebase (Auth + Firestore) needs no server at all and its
free tier is enough for a small group, at the cost of depending on Google.

App changes needed either way:

1. Optional login screen (the app keeps working offline without an account).
2. Sync: upload the progress JSON (the same format as the backup file) and merge
   on conflict: union of completed lessons, max XP per day, earliest review due.
3. Leaderboard tab: weekly XP of friends, friend invites by code.
