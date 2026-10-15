# Content authoring guide

All study content lives in `assets/content/` as JSON. No code changes are needed
to add or fix lessons.

```
assets/content/
  index.json            levels + list of subject files
  circuit_theory.json   one file per subject
  ...
```

After editing, always run the validator:

```sh
flutter test test/content_test.dart
CONTENT_SUBJECT=circuit-theory flutter test test/content_test.dart   # one subject
```

and check your circuit diagrams visually (writes one PNG per unit):

```sh
CONTENT_SUBJECT=circuit-theory PREVIEW_OUT=build/previews flutter test tool/circuit_preview_test.dart
```

To see steps exactly as in the app (graphs, tap questions, layout), render them
one PNG per step:

```sh
CONTENT_UNIT=tr-rc PREVIEW_OUT=build/steps flutter test tool/step_preview_test.dart
CONTENT_UNIT=tr-rc CONTENT_STEP=tr-rc-3/g1 PREVIEW_OUT=build/steps flutter test tool/step_preview_test.dart
```

## Hierarchy

```
Level (index.json)          "Year 1 – Basics"
 └ Subject (one file)       "Circuit Theory"
    └ Unit                  "Thévenin & Norton"
       ├ study: [cards]     the study material / cheat sheet for the unit
       └ lessons: [...]     3–5 minute lessons
          └ steps: [...]    info cards and exercises
```

### index.json

```json
{
  "levels": [
    {"id": "y1-basics", "title": "Year 1 – Basics", "subtitle": "DC circuits & logic",
     "description": "…", "subjects": ["circuit-theory", "digital-logic"]}
  ],
  "subjectFiles": ["circuit_theory.json", "digital_logic.json"]
}
```

### Subject file

```json
{
  "id": "circuit-theory",
  "title": "Circuit Theory",
  "description": "One sentence.",
  "icon": "bolt",
  "color": "#58CC02",
  "reference": "Hambley ch. 1–2",
  "units": [ … ]
}
```

`icon` is one of: `bolt, memory, timeline, waves, developer_board,
settings_input_component, show_chart, electrical_services, calculate, tune,
graphic_eq, functions, flare, cable, code, speed, sensors, bar_chart, speaker,
shield, cell_tower, power, equalizer, account_tree, casino, electric_meter,
settings_input_antenna, grain, data_object`.

### Unit

```json
{
  "id": "ct-thevenin",
  "title": "Thévenin & Norton",
  "description": "Replace any linear two-terminal network by a source and a resistor.",
  "reference": "Hambley §2.6",
  "study": [ {"title": "…", "body": "…", "formula": "V_t = v_{oc}", "circuit": {…}} ],
  "lessons": [ … ]
}
```

Ids must be unique across the whole app. Prefix them with a subject
abbreviation (`ct-`, `dl-`, `tr-`, `ac-`, `sc-`, `oa-`).

### Lesson

```json
{"id": "ct-thevenin-1", "title": "What is an equivalent?", "kind": "learn", "steps": [ … ]}
```

`kind`:
- `learn`: introduces the idea. Mix `info` steps with easy questions.
- `practice`: mostly calculations, few or no info steps.
- `challenge`: harder multi-step problems (optional, usually last in a unit).

A lesson has **5–10 steps** and at least 3 questions, so it takes 3–5 minutes.

## Text

Every text field (`title`, `body`, `prompt`, `options`, `explanation`, `hint`,
pairs, items, circuit labels) supports:

- `$…$` inline LaTeX, `$$…$$` display LaTeX (on its own line)
- `**bold**`
- new lines with `\n`; lines starting with `- ` render as bullets
- `{{expr}}` placeholders, see below

Escape backslashes in JSON: `"$\\frac{a}{b}$"`. Use `\\Omega` inside math, `Ω` in
plain text. A literal dollar sign is written `\\$`.

## Random parameters (the key feature)

Most calculation questions should use random values so students cannot just
memorize answers.

```json
{
  "id": "q3",
  "type": "numeric",
  "params":  {"Vs": [5, 9, 12], "R1": {"values": [1000, 2200, 4700]}, "R2": {"min": 1000, "max": 10000, "step": 1000}},
  "derived": {"Rp": "par(R1, R2)"},
  "require": "abs(R1 - R2)",
  "prompt":  "With $V_s$ = {{Vs|V}}, $R_1$ = {{R1|Ω}} and $R_2$ = {{R2|Ω}}, find $V_{out}$.",
  "answer":  "Vs*R2/(R1+R2)",
  "unit": "V",
  "explanation": "$V_{out} = V_s\\frac{R_2}{R_1+R_2}$ = {{Vs*R2/(R1+R2)|V}}"
}
```

- `params`: list of values, or `{min, max, step}`. Use **SI base units**
  (ohms, volts, amps, farads, seconds), so 4.7 kΩ is `4700` and 10 µF is `10e-6`.
- `derived`: values computed from params (in order). Use them to keep
  expressions readable.
- `require`: optional expression that must be `> 0` for a draw to be accepted
  (e.g. `abs(R1-R2)` to force different values). It is retried up to 200 times.
- Placeholders may sit directly inside LaTeX braces: `"$\\frac{{{V}}}{2}$"` works.
- `{{expr}}` prints a number with 3 significant figures. `{{expr|unit}}` adds an
  SI prefix: `{{4700|Ω}}` → `4.7 kΩ`, `{{0.0025|A}}` → `2.5 mA`. `{{expr|unit|sig}}`
  sets significant figures. Units without prefixes: `%`, `°`, `°C`, `rad`,
  `rpm`, `cm`, `mm`, `km`, `cm²`, `mm²`, `h`, `min`, `bins`, `pu` (per unit), `K`,
  `bit`, `bits`, `bit/symbol`, `bits/symbol`, `bit/s/Hz`, `bits/s/Hz`, `cm⁻³`,
  `cm²/V·s`, `cm²/s`, `cm/s` and every unit starting with `dB` (`dB`, `dBm`,
  `dBµV/m`, `dB/dec`).
  Use `{{expr||4}}` for a plain number with 4 significant figures.
  `{{n|hex}}` and `{{n|bin}}` print an integer in hexadecimal (upper case) or
  binary; `{{n|hex|4}}` pads to 4 digits (`00AB`).
- Values with magnitude below 1e-12 print as 0 (this hides floating-point
  noise such as cos(90°) = 6e-17), in placeholders and in plot readouts. For
  genuinely tiny quantities (noise current densities, kT, noise powers) print a
  scaled number instead: `{{In*1e12||2}} pA/√Hz`, `{{P*1e15||3}} fW`.
- Expression language: `+ - * / ^ ( )`, `pi`, `e`, and functions `sqrt abs exp ln
  log10 sin cos tan asin acos atan atan2 deg rad min max round floor ceil par
  step sign clamp mod`. `step(x)` is 0 for x < 0 and 1 otherwise, `clamp(x, lo, hi)`
  limits a value, `mod(a, b)` is always ≥ 0 (useful for periodic waveforms).
  `par(a, b, …)` is the parallel combination `1/(1/a + 1/b + …)`. Trig uses radians.
  There are no comparison operators; use `min`/`max`/`abs` or `if` instead.
- More functions: `if(c, a, b)` is `a` when `c > 0`, else `b`;
  `sinc(x)` = sin(πx)/(πx); `step2(t, zeta, wn)` is the unit-step response of
  ωn²/(s² + 2ζωn·s + ωn²) for any ζ ≥ 0 (under-, critically and overdamped);
  `sum(k, from, to, expr)` adds `expr` for k = from…to, e.g. a Fourier partial
  sum `sum(k, 1, N, 4/(pi*(2*k-1))*sin((2*k-1)*x))`.
- Also: `log2`, `sinh cosh tanh atanh`, `erf`, `erfc`, `Q(x)` (Gaussian tail
  probability ½·erfc(x/√2), accurate down to tiny bit-error rates), `fact(n)`,
  `choose(n, k)`, and for codes on non-negative integers `xor(a, b)`,
  `popcount(n)` (number of 1 bits) and `bit(n, i)` (bit i, 0 = least
  significant). Hamming distance is `popcount(xor(a, b))`.

Pick parameter sets that produce sensible, realistic values.

## Step types

All steps need a unique `id` (within the lesson) and a `type`. Every question
needs an `explanation` (shown after answering, right or wrong). It should show
the method, not only the result. `hint` is optional. `circuit` is optional on
any step.

### info

```json
{"id": "i1", "type": "info", "title": "Kirchhoff's current law",
 "body": "The sum of currents **entering** a node equals the sum **leaving** it.",
 "formula": "\\sum i_{in} = \\sum i_{out}"}
```

### multipleChoice

```json
{"id": "q1", "type": "multipleChoice", "prompt": "…",
 "options": ["correct one", "distractor", "distractor"], "answer": 0,
 "explanation": "…"}
```

`answer` is the index of the correct option in the list as written, or an
expression that evaluates to that index, so the right option can depend on the
random values. For example, `"answer": "max(0, min(2, round(zeta - 0.5)))"`.
Options are
shuffled at display time (set `"shuffle": false` for things like "all of the
above"). Use 2–5 options. Options may use `{{…}}`. Build **numeric
distractors from common mistakes** (e.g. series instead of parallel). Make sure
they can never coincide with the right answer for any parameter draw; the
validator checks this.

### trueFalse

```json
{"id": "q2", "type": "trueFalse", "prompt": "Statement…", "answer": false, "explanation": "…"}
```

`answer` can also be an expression, which counts as true when it is > 0, so the
truth can depend on random values: `"answer": "R1 - R2"` ("$R_1$ is larger than
$R_2$").

### numeric

```json
{"id": "q3", "type": "numeric", "prompt": "…", "answer": "expr", "unit": "Ω",
 "tolerance": 0.02, "explanation": "…"}
```

- `unit` is shown next to the input (`"Ω"`, `"V"`, `"A"`, `"W"`, `"s"`, `"F"`,
  `"H"`, `"Hz"`, `"rad/s"`, `"°"`, `"dB"`, `""` for dimensionless). The student may
  type prefixes: `4.7k`, `2.5m`, `10u`, `4k7`, `1e-3`.
- `tolerance` is relative (default 0.02 = 2 %). For answers that can be 0, add
  `"absTolerance": 0.01`.
- Ask for one clearly defined value with a clear sign convention.

### matchPairs

```json
{"id": "q4", "type": "matchPairs", "prompt": "Match each quantity to its unit",
 "pairs": [["Resistance", "Ω"], ["Capacitance", "F"], ["Inductance", "H"]],
 "explanation": "…"}
```

Use 3–5 pairs. Both sides must be distinct. Keep each side short.

### orderSteps

```json
{"id": "q5", "type": "orderSteps", "prompt": "Put the steps of node-voltage analysis in order",
 "items": ["Select a reference node", "Label the node voltages", "Write KCL at each node", "Solve the equations"],
 "explanation": "…"}
```

Write `items` in the **correct** order; they are shuffled for the student. Use 3–6 items.

### tapCircuit

The student taps elements in the schematic, e.g. "tap every resistor in
parallel with $R_3$". Give the tappable elements a `name`.

```json
{"id": "t1", "type": "tapCircuit", "prompt": "Tap every resistor in **parallel** with $R_3$.",
 "circuit": {"elements": [ … {"type": "resistor", "name": "R2", …} … ]},
 "selectable": ["R1", "R2", "R4", "R5"],
 "answer": ["R2"],
 "explanation": "…"}
```

- `answer`: the names that must be selected (all of them, and nothing else).
- `selectable`: the names that respond to taps (default: every named element).
  Leave out the element the question is about, so it can't be tapped by mistake.
- Named `node` elements (junction dots) are tappable too, e.g. "tap the node you
  would choose as reference" or "tap the nodes of the supernode".
- The schematic is drawn as the exercise itself, so don't repeat it elsewhere.
  Labels and values are templated as usual, and solver values (`val`) work too.

### slider

"Adjust the graph": the student drags one or more sliders until the graph
does what the prompt asks, e.g. "set ζ so the overshoot is 20 %" or "move the
cutoff frequency to 1 kHz". The `plot` needs `sliders` (see *Interactive
graphs* below). Either give the target value of each slider:

```json
{"id": "s1", "type": "slider",
 "params": {"target": [5, 10, 20, 30]},
 "derived": {"zt": "-ln(target/100)/sqrt(pi^2+ln(target/100)^2)"},
 "prompt": "Set the damping ratio so the step response overshoots by about {{target}}%.",
 "plot": {"x": {…}, "y": {…},
   "sliders": [{"name": "zeta", "label": "$\\zeta$", "min": 0.05, "max": 1.5, "step": 0.01, "value": 1}],
   "curves": [{"f": "step2(x, zeta, 2)"}, {"f": "1+target/100", "dash": true, "color": "orange", "label": "target peak"}],
   "readouts": [{"label": "Overshoot", "value": "…", "unit": "%", "reveal": true}]},
 "answer": {"zeta": "zt"}, "tolerance": 0.06,
 "explanation": "…"}
```

or a `check` expression (in the slider variables and params) that is > 0
when the setting is right, plus an optional `solution` text shown as the
correct answer: `"check": "0.05 - abs(fc - 1000)/1000"`.

- `tolerance` (relative, default 0.05) / `absTolerance` (default 0) apply to `answer`.
  The tolerance must be larger than half a slider step, and the starting
  `value` must not already be correct (the validator checks both, and that a
  correct position exists for every random draw).
- Items marked `"reveal": true` (curves, points, lines, labels, readouts) only
  appear after the answer is checked: use them for the target curve or a
  readout that would give the answer away.
- After checking, the sliders lock.

## Graphs

Any step or study card can have a `plot`: a graph with curves defined as
expressions in `x`, using the step's params. Use them for "read the value from
the graph" questions (set a looser `tolerance`, e.g. 0.05–0.1) and to show
waveforms, transient responses, Bode plots and I–V characteristics.

```json
"plot": {
  "x": {"min": 0, "max": "5*tau", "label": "t", "unit": "s"},
  "y": {"min": 0, "max": "1.15*Vs", "label": "v_C (V)"},
  "curves": [{"f": "Vs*(1-exp(-x/tau))", "label": "v_C(t)"}],
  "points": [{"x": "tau", "y": "0.632*Vs", "label": "τ"}],
  "hlines": [{"y": "Vs", "label": "{{Vs|V}}"}],
  "vlines": [{"x": "tau", "label": "τ"}]
}
```

- Axes: `min`, `max` (numbers or expressions), `label`, `unit` (tick labels get
  SI prefixes, e.g. `"s"` gives 0, 5 ms, 10 ms), `log: true` for logarithmic axes
  (Bode plots: frequency axis log, dB axis linear), optional `ticks: [...]`.
- `curves`: `f` (expression in `x` and the params), optional `label`, `color`
  (`primary` default, `red`, `blue`, `orange`, `green`, `purple`, `grey`),
  `dash: true`, `labelAt` (0–1, where along the x-range the label goes; default
  0.62), and `from`/`to` to limit the x-range.
- `points`: marked points with dashed guides to the axes (`"guides": false` to
  hide them), optional `color` and `marker`: `"dot"` (default), `"x"` (pole) or
  `"o"` (zero), for pole-zero maps. `hlines` / `vlines`: dashed reference lines with optional labels and `color`.
- `labels`: free text at a data position, e.g. signal names in a timing diagram:
  `{"x": 0.2, "y": 4.5, "text": "CLK", "color": "grey"}` (left edge at x,
  centred on y).
- Labels support `_` subscripts (`v_C`, `V_{out}`), `~` overlines (`~Q`) and
  `{{…}}` placeholders. Tick labels thin out automatically when crowded.
- Avoid giving the answer away: if the question is "read τ", don't mark τ.
- `height` (default 200) sets the drawing height in pixels.
- **Parametric curves**: give `x` and `y` (expressions in `t`) and the range
  `t: [min, max]` instead of `f`, e.g. a circle
  `{"x": "r*cos(t)", "y": "r*sin(t)", "t": [0, "2*pi"]}`. Use them for unit
  circles, Nyquist plots, constellations, SWR circles and impedance loci.
- `"equal": true` gives both axes the same scale (circles stay round): the
  shorter axis range is widened to fit. Use it for z-plane and s-plane
  pole-zero maps and phasor or constellation diagrams.
- `"smith": true` draws a **Smith chart** (default height 300; no `x`/`y` axes
  needed). Coordinates are the real and imaginary part of the reflection
  coefficient Γ: a normalized load z = r + jx sits at Γ = (z − 1)/(z + 1),
  i.e. x: `((r^2+x^2)-1)/((r+1)^2+x^2)`, y: `2*x/((r+1)^2+x^2)`. Points (guides
  are not drawn), parametric curves (SWR circles, loci) and labels work as usual.

### Interactive graphs (sliders)

Add `sliders` to any `plot` (study cards, info steps, questions) to let the
student explore: dragging a slider sets a variable and redraws the graph.

```json
"plot": {
  "x": {"min": 0, "max": 10, "label": "t", "unit": "s"},
  "y": {"min": 0, "max": 2, "label": "y(t)"},
  "sliders": [
    {"name": "zeta", "label": "$\\zeta$", "min": 0.05, "max": 2, "step": 0.05, "value": 0.3},
    {"name": "wn", "label": "$\\omega_n$", "min": 0.5, "max": 5, "step": 0.1, "value": 2, "unit": "rad/s"}
  ],
  "let": {"Mp": "if(1-zeta, 100*exp(-pi*zeta/sqrt(abs(1-zeta^2)+1e-12)), 0)"},
  "curves": [{"f": "step2(x, zeta, wn)", "label": "step response"}],
  "readouts": [
    {"label": "Overshoot", "value": "Mp", "unit": "%"},
    {"label": "$T_s$", "value": "4/(zeta*wn)", "unit": "s"}
  ]
}
```

- Slider fields: `name` (the variable), `label` (inline math allowed), `min`,
  `max`, `value` (start; numbers or expressions in the params), `step` (grid
  the value snaps to; required for linear sliders, at most 2000 steps),
  `unit` (value shown with SI prefixes), `sig` (significant figures, default
  3), `log: true` for a logarithmic slider (e.g. frequency over decades; then
  `step` is not used and values round to 3 significant figures).
- `let`: values computed from the sliders and params (in order), usable in
  curves, points, lines, labels and readouts.
- `readouts`: live values under the graph: `label`, `value` (expression),
  `unit`, `sig`.
- Points, lines and labels can move too: their positions are expressions, so
  `{"x": "-zeta*wn", "y": "wn*sqrt(1-zeta^2)", "marker": "x"}` puts a pole that
  follows the sliders. Labels can use `{{…}}` with slider variables.
- Choose axis ranges that keep the curve readable over the whole slider range.
- Good uses: damping (ζ) and step responses, cutoff frequency on a Bode plot,
  RC time constant, phasor angle, Fourier partial sums with N terms, sampling
  and aliasing, load lines, root-locus gain K moving the closed-loop poles.

### Graphs as answer options

A `multipleChoice` step can show graphs as its options with `optionPlots`
(2–4 plots, same format as `plot`). `answer` is the index of the right graph;
`options` is then optional. Example: "Which graph is the step response of an
underdamped RLC circuit?".

## Circuits

Circuits are drawn on a grid. Coordinates are `[x, y]` with **y pointing down**.
A typical two-terminal component spans 2 grid units (minimum 1). The renderer
scales the drawing to the screen; aim for at most ~7 units wide and ~5 high.

```json
"circuit": {"elements": [
  {"type": "vsource", "from": [0, 2], "to": [0, 0], "label": "V_s", "value": "{{Vs|V}}"},
  {"type": "wire", "points": [[0, 0], [3, 0]]},
  {"type": "resistor", "from": [3, 0], "to": [3, 2], "label": "R_1", "value": "{{R1|Ω}}"},
  {"type": "wire", "points": [[3, 2], [0, 2]]},
  {"type": "ground", "at": [0, 2]}
]}
```

Two-terminal elements (`from`, `to`, optional `label`, `value`, `flip`, `polarity`):

| type | notes |
|---|---|
| `resistor`, `capacitor`, `inductor`, `lamp`, `switch` (`closed: true/false`) | |
| `vsource` | independent DC voltage source; **+ terminal at `to`** |
| `battery` | long plate (+) at `to` |
| `acsource` | sinusoidal source |
| `isource` | current flows (arrow points) from `from` to `to` |
| `cvsource` / `ccsource` | dependent (diamond) voltage / current sources, same conventions |
| `diode`, `zener`, `led` | anode at `from`, cathode at `to` |
| `voltmeter`, `ammeter`, `motor`, `generator` | circle with V, A, M or G |

- `label` and `value` are drawn beside the element (above horizontal elements,
  right of vertical ones). `"flip": true` puts them on the other side.
- `_` makes a subscript: `R_1`, `V_{th}`, `R_L`.
- `"polarity": "+-"` draws + at `from` and − at `to` (`"-+"` the reverse). Use it
  to define voltage references on resistors.

Other elements:

| type | fields | notes |
|---|---|---|
| `wire` | `points: [[x,y], …]` | polyline |
| `node` | `at`, optional `label` | junction dot |
| `terminal` | `at`, `label`, `flip` | open circle, e.g. terminals a and b |
| `ground` | `at`, optional `rotation` | |
| `text` | `at`, `label` | free text |
| `arrow` | `from`, `to`, `label` | current direction arrow drawn on a wire segment |
| `loop` | `at`, `label`, `flip` | circular mesh-current arrow centred in a window; clockwise, `flip: true` for counter-clockwise |
| `transformer` | `at`, `label`, `flip` | primary pins at `at+[-1,-1]` (top) and `at+[-1,1]`, secondary at `at+[1,-1]` and `at+[1,1]`. Dots at both top ends; `"flip": true` moves the secondary dot to the bottom |
| `block` | `at`, `label`, `value`, `size` | block-diagram box (`size: [w, h]`, default `[2, 1]`) with `label` inside and `value` above. Connect to the middle of a side, e.g. `at+[-1,0]` / `at+[1,0]` for the default size |
| `sum` | `at`, `kind`, `label` | summing junction (radius 0.3). `kind` gives the input signs for the left, bottom and top inputs, e.g. `"+-"` |
| `signal` | `points`, `label`, `flip` | block-diagram signal: a polyline with an arrowhead at the last point; `label` above its first segment (`flip`: below) |
| `opamp` | `at` | pins: − input at `at+[-1,-0.5]`, + input at `at+[-1,0.5]`, output at `at+[1,0]`. `"flip": true` swaps + and − |
| `gate` | `at`, `kind` | `and or not nand nor xor xnor buffer`. Inputs at `at+[-1,-0.3]` and `at+[-1,0.3]` (single input at `at+[-1,0]`), output at `at+[1,0]` |
| `npn`, `pnp` | `at` | base at `at+[-1,0]`. npn: collector `at+[0,-1]`, emitter `at+[0,1]`. pnp: emitter top, collector bottom |
| `nmos`, `pmos` | `at` | gate at `at+[-1,0]`. nmos: drain `at+[0,-1]`, source `at+[0,1]`. pmos: source top, drain bottom |

Connect everything with explicit wires to the exact pin coordinates. Add a
`node` dot wherever three or more wires meet.

## Solved circuits (automatic answers)

Instead of writing the answer formula yourself, you can let the app **solve
the drawn circuit**. Give elements a `name` and a value expression `val`
(ohms, volts, amps). The app works out the nodes from the wires, solves the
circuit with nodal analysis for each random draw, and exposes the results as
variables:

| variable | meaning |
|---|---|
| `V_R5` | voltage across R5 = v(`from`) − v(`to`), matching `"polarity": "+-"` |
| `I_R5` | current through R5 from `from` to `to` |
| `P_R5` | power absorbed by R5 |
| `V_Vs`, `I_Vs`, `P_Vs` | for sources: voltage v(+) − v(−), current delivered out of the + terminal (or in the arrow direction for current sources), power **delivered** |
| `v_a` | voltage of the node/terminal labelled `a` relative to ground. Labels keep only letters, digits and `_`, so a terminal labelled `v_1` gives `v_v_1` |
| `V_U1`, `I_U1` | for a named op amp: output voltage and the current flowing **out of** its output pin |
| `I_F` | for a named dependent current source: its current in the arrow direction |
| `Req`, `Voc`, `Isc` | with exactly two `terminal`s: equivalent resistance (independent sources zeroed), open-circuit voltage v_a − v_b, short-circuit current a→b. So $R_t$ = `Req`, $V_t$ = `Voc`, $I_n$ = `Isc` |
| `R_a_b`, `Voc_a_b`, `Isc_a_b` | the same for any pair of terminals `a`, `b` (in the order they appear) |

```json
{
  "id": "q1",
  "type": "numeric",
  "params": {"Vs": {"min": 5, "max": 24, "step": 1}, "R1": [100, 220, 470], "R2": [330, 680, 1000], "R3": [1000, 1500, 2200]},
  "prompt": "All values are shown in the schematic.",
  "ask": [
    {"prompt": "Find the voltage across $R_3$.", "answer": "abs(V_R3)", "unit": "V",
     "explanation": "$R_2 \\parallel R_3$ = {{par(R2,R3)|Ω}}, so $V_{R_3}$ = {{abs(V_R3)|V}}."},
    {"prompt": "Find the current through $R_1$.", "answer": "abs(I_R1)", "unit": "A",
     "explanation": "$I$ = $V_s/(R_1 + R_2\\parallel R_3)$ = {{abs(I_R1)|A}}."},
    {"prompt": "Find the power delivered by the source.", "answer": "P_Vs", "unit": "W",
     "explanation": "$P = V_s I$ = {{P_Vs|W}}."}
  ],
  "circuit": {"elements": [
    {"type": "vsource", "name": "Vs", "val": "Vs", "from": [0, 2], "to": [0, 0], "label": "V_s"},
    {"type": "resistor", "name": "R1", "val": "R1", "from": [0, 0], "to": [2, 0], "label": "R_1"},
    {"type": "resistor", "name": "R2", "val": "R2", "from": [2, 0], "to": [2, 2], "label": "R_2"},
    {"type": "wire", "points": [[2, 0], [4, 0]]},
    {"type": "resistor", "name": "R3", "val": "R3", "from": [4, 0], "to": [4, 2], "label": "R_3"},
    {"type": "wire", "points": [[0, 2], [4, 2]]},
    {"type": "node", "at": [2, 0]}, {"type": "node", "at": [2, 2]},
    {"type": "ground", "at": [0, 2]}
  ]}
}
```

- Elements with `val` automatically show their value (e.g. "4.7 kΩ") unless
  you give a `value` yourself (`"value": ""` hides it).
- `ask` (numeric steps only) is a list of question variants. Each time, one is
  picked at random. Its `prompt` is appended to the step's `prompt`, and its
  `answer`, `unit`, `explanation`, `tolerance` override the step's.
- `computed` works like `derived` but is evaluated **after** solving, so it can
  use solver results: `"computed": {"Pmax": "Voc^2/(4*Req)"}`. `require` is
  also checked after solving.
- Supported: `resistor`, `lamp` (with `val`), `vsource`, `battery`, `isource`,
  `cvsource`/`ccsource` (dependent: `val` is the gain, `ctrl` is `"V(R2)"`,
  `"I(R1)"` or `"V(a,b)"` with node labels), `switch` (closed = short, open =
  open), `ammeter`/`inductor` (short), `voltmeter`/`capacitor` (open), and ideal
  `opamp`s (virtual short). DC steady state is assumed. Diodes and transistors
  are not supported in solved circuits.
- Without a `ground` the − terminal of the first voltage source is the reference.
- Give dependent sources a `name` too: unnamed elements are left out of the
  worked solution's element list and power balance.
- Circuits without an independent source get no worked solution (all node
  voltages would be 0); explain the method in the `explanation` instead.

### AC circuits (phasors)

Add `"ac": {"f": "f"}` (frequency in Hz) or `"ac": {"omega": "w"}` (rad/s) to
the circuit to solve it in sinusoidal steady state. Then:

- `capacitor` and `inductor` need a `val` (F, H) and become impedances
  1/(jωC) and jωL.
- Sources (`acsource`, `vsource`, `isource`) take `val` as the phasor
  **magnitude** (peak, like Hambley; add `"rms": true` to `ac` for rms
  phasors) and an optional `phase` in degrees (expression). The automatic
  label shows e.g. "10∠30° V".
- Every exported quantity is a phasor: `V_R1` is its magnitude, `V_R1_ph` the
  angle in degrees (−180…180), `V_R1_re` / `V_R1_im` its parts. The same for
  `I_X`, `v_label`, `Voc`, `Isc`.
- Power: `P_X` is the **average** power (½·Re{V·I*} for peak phasors), `Q_X` the
  reactive power (var), `S_X` the apparent power (VA), `pf_X` the power factor.
- Impedances: `Z_R1`, `Z_L1`, `Z_C1` (with `_ph`, `_re`, `_im`) for every R, L
  and C, and `Z_a_b` / `Zeq` (with `_ph`, `_re`, `_im`) between terminals,
  instead of `R_a_b` / `Req`.
- Angles: answer with unit `"°"` and an `absTolerance` (e.g. 1), since angles
  near 0 make relative tolerances useless. Answers in `°` accept equivalent
  angles (−170° = 190°).
- The worked solution shows ω, the impedances, phasor KCL equations, node
  voltage phasors and every element's V, I and average power.
- Use `abs()` when you ask for "the voltage across" or "the current through"
  without defining a direction. Define it with `polarity` or an `arrow` when
  the sign matters.
- Every wire end, pin and junction must land exactly on grid coordinates that
  touch. A point lying on a wire segment connects to it.

## Writing good content

- Short. A study card body is 2–5 sentences. A prompt is 1–3 sentences.
- One idea per step. Build up: concept, then simple check, then calculation.
- Use the notation of Hambley (*Electrical Engineering: Principles and
  Applications*): passive reference configuration, $v_{oc}$, $i_{sc}$, $R_t$, etc.
  Mention the section in the unit `reference` field. Signals subjects follow
  Phillips, Parr & Riskin (*Signals, Systems, and Transforms*, "Phillips §…"),
  Analog Electronics follows Horowitz & Hill (*The Art of Electronics*, "H&H §…")
  EMC follows Ott (*Electromagnetic Compatibility Engineering*, "Ott §…") and
  Communication Systems follows Frenzel (*Principles of Electronic Communication
  Systems*, "Frenzel §…"). Year 3 – Advanced: Power Electronics follows Erickson
  & Maksimović ("Erickson §…"), Digital Signal Processing Oppenheim & Schafer
  ("O&S §…"), Modern & Digital Control Franklin, Powell & Emami-Naeini
  ("FPE §…"), Probability & Random Signals Leon-Garcia ("Leon-Garcia §…"),
  Power Systems Glover, Overbye & Sarma ("Glover §…"), RF & Microwave Pozar
  ("Pozar §…"), Semiconductor Devices Neamen ("Neamen §…") and Information
  Theory & Coding Cover & Thomas ("C&T §…") and Lin & Costello ("Lin & Costello §…").
  Separate references to several books with `; `.
- Write original explanations and problems. Do not copy text or problems from
  the book.
- Explanations should teach. Show the formula with numbers filled in.
- Double-check every answer expression and every circuit picture.
