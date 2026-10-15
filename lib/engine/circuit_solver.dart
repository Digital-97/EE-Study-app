import 'dart:math' as math;
import 'dart:ui';

import '../models/circuit.dart';
import 'complex.dart';
import 'expression.dart';
import 'units.dart';

/// Circuit solver for drawn schematics (modified nodal analysis), for DC and
/// for sinusoidal steady state (phasors, when the circuit has `"ac"`).
///
/// Connectivity comes straight from the drawing: wires join points, and a
/// point lying on a wire segment joins that wire. Elements with a `name` and
/// a `val` take part in the analysis; their results are exported as variables
/// usable in answers and explanations:
///
/// * `V_X`: voltage across X. For passive elements this is v(from) − v(to)
///   (matching `"polarity": "+-"`). For sources it is v(+) − v(−).
/// * `I_X`: current through X. For passive elements it flows from `from` to
///   `to`. For sources it is the current delivered out of the + terminal
///   (voltage sources) or in the arrow direction (current sources).
/// * `P_X`: power absorbed by passive elements, power delivered by sources.
/// * For op amps: `V_X` is the output voltage, `I_X` the current flowing out
///   of the output pin.
/// * `v_<label>`: voltage of a labelled node/terminal relative to ground.
///   Labels keep only [A-Za-z0-9_], so terminal "v_1" gives `v_v_1`.
/// * For every pair of labelled terminals a, b: `R_a_b` (equivalent
///   resistance with independent sources zeroed), `Voc_a_b` (open-circuit
///   voltage v_a − v_b) and `Isc_a_b` (short-circuit current from a to b).
///   With exactly two terminals these are also available as `Req`, `Voc`,
///   `Isc`.
///
/// Without `"ac"`, DC steady state is assumed: capacitors are open circuits,
/// inductors are short circuits. Ideal op amps (`opamp`) are supported via the
/// virtual short. Dependent sources (`cvsource`, `ccsource`) need `val` (the
/// gain) and `ctrl`, e.g. `"V(R2)"`, `"I(R1)"` or `"V(a,b)"`.
///
/// With `"ac": {"f": ...}` or `{"omega": ...}` the circuit is solved with
/// phasors: capacitors are 1/(jωC), inductors jωL, and sources take `val` as
/// the phasor magnitude (peak, or rms with `"rms": true`) and `phase` in
/// degrees. Then every quantity Q above is exported as its magnitude `Q`, its
/// angle in degrees `Q_ph` and its parts `Q_re`, `Q_im`; `P_X` is the average
/// power (½·Re{V·I*} for peak phasors), with `Q_X` (reactive power),
/// `S_X` (apparent power) and `pf_X` (power factor). R, L and C also export
/// their impedance `Z_X`. Terminal pairs export `Z_a_b` (with `Zeq` for two
/// terminals) instead of `R_a_b`.
class CircuitSolver {
  CircuitSolver._(this.spec, this.vars);

  final CircuitSpec spec;
  final Map<String, double> vars;

  /// Whether [spec] asks to be solved (has at least one element with `val`).
  static bool isSolvable(CircuitSpec spec) => spec.elements.any((e) => e.val != null);

  /// Solves [spec] with parameter values [vars]; returns the exported results.
  static Map<String, double> solve(CircuitSpec spec, Map<String, double> vars) =>
      CircuitSolver._(spec, vars)._run();

  /// Solves [spec] and describes the solution step by step (node names,
  /// constraints, KCL equations, node voltages, element values).
  static CircuitReport report(CircuitSpec spec, Map<String, double> vars) =>
      CircuitSolver._(spec, vars)._report();

  static const _gmin = 1e-12;

  /// Angular frequency for AC analysis; null for DC.
  late final double? _omega = () {
    final ac = spec.ac;
    if (ac == null) return null;
    if (ac.omega != null) return _eval(ac.omega!);
    if (ac.f != null) return 2 * math.pi * _eval(ac.f!);
    throw CircuitException('"ac" needs "f" or "omega"');
  }();

  bool get _isAc => _omega != null;

  /// Factor between V·I* and complex power: ½ for peak phasors.
  double get _powerFactor => _isAc && !(spec.ac?.rms ?? false) ? 0.5 : 1.0;

  /// Complex power V·I* (·½ for peak phasors); parts that are rounding noise
  /// next to |S| (e.g. the average power of an ideal L or C) become exactly 0.
  Complex _power(Complex v, Complex i) {
    final s = (v * i.conj).scale(_powerFactor);
    final tiny = 1e-9 * s.abs;
    return Complex(s.re.abs() < tiny ? 0 : s.re, s.im.abs() < tiny ? 0 : s.im);
  }

  Complex _source(CircuitElement e) {
    final mag = _eval(e.val!);
    if (!_isAc) return Complex(mag);
    return Complex.polar(mag, e.phase == null ? 0 : _eval(e.phase!));
  }

  // ---- Topology ----

  final Map<String, int> _pointIds = {};
  final List<int> _parent = [];

  static String _k(Offset p) => '${(p.dx * 1000).round()},${(p.dy * 1000).round()}';

  int _point(Offset p) => _pointIds.putIfAbsent(_k(p), () {
        _parent.add(_parent.length);
        return _parent.length - 1;
      });

  int _find(int i) {
    while (_parent[i] != i) {
      _parent[i] = _parent[_parent[i]];
      i = _parent[i];
    }
    return i;
  }

  void _union(int a, int b) {
    final ra = _find(a), rb = _find(b);
    if (ra != rb) _parent[ra] = rb;
  }

  late List<_Branch> _branches;
  late Map<int, int> _nodeIndex; // root point id -> matrix index (ground = -1)
  final Map<String, int> _labelNodes = {}; // label -> root point id
  final List<String> _terminals = [];

  void _buildTopology() {
    final connectionPoints = <Offset>[];
    for (final e in spec.elements) {
      if (e.from != null) connectionPoints.add(e.from!);
      if (e.to != null) connectionPoints.add(e.to!);
      if (e.at != null) connectionPoints.addAll(_pins(e).values);
      connectionPoints.addAll(e.points);
    }
    for (final p in connectionPoints) {
      _point(p);
    }
    for (final e in spec.elements.where((e) => e.type == 'wire')) {
      for (var i = 0; i + 1 < e.points.length; i++) {
        final a = e.points[i], b = e.points[i + 1];
        _union(_point(a), _point(b));
        for (final p in connectionPoints) {
          if (_onSegment(p, a, b)) _union(_point(p), _point(a));
        }
      }
    }

    _branches = [];
    for (final e in spec.elements) {
      final pins = _pins(e);
      if (e.type == 'ground') continue;
      if ((e.type == 'terminal' || e.type == 'node') && e.label != null) {
        final name = _ident(e.label!);
        if (name.isNotEmpty) {
          _labelNodes[name] = _point(e.at!);
          if (e.type == 'terminal' && !_terminals.contains(name)) _terminals.add(name);
        }
        continue;
      }
      if (e.type == 'opamp') {
        _branches.add(_Branch('opamp', e.name, pins['+']!, pins['-']!, out: pins['out']));
        continue;
      }
      if (!twoTerminalTypes.contains(e.type)) continue;
      final from = e.from!, to = e.to!;
      switch (e.type) {
        case 'resistor' || 'lamp':
          if (e.val == null) throw CircuitException('${e.type} ${e.name ?? ''} needs "val"');
          final r = _eval(e.val!);
          if (r <= 0) throw CircuitException('Resistance must be positive');
          _branches.add(_Branch('R', e.name, from, to, value: Complex(r), element: 'R'));
        case 'vsource' || 'battery' || 'acsource':
          if (e.val == null) throw CircuitException('${e.type} ${e.name ?? ''} needs "val"');
          _branches.add(_Branch('V', e.name, from, to, value: _source(e)));
        case 'isource':
          if (e.val == null) throw CircuitException('isource ${e.name ?? ''} needs "val"');
          _branches.add(_Branch('I', e.name, from, to, value: _source(e)));
        case 'switch':
          if (e.closed) _branches.add(_Branch('short', e.name, from, to));
          if (!e.closed) _branches.add(_Branch('open', e.name, from, to));
        case 'inductor' when _isAc:
          if (e.val == null) throw CircuitException('inductor ${e.name ?? ''} needs "val" in an AC circuit');
          _branches.add(_Branch('R', e.name, from, to, value: Complex(0, _omega! * _eval(e.val!)), element: 'L'));
        case 'capacitor' when _isAc:
          if (e.val == null) throw CircuitException('capacitor ${e.name ?? ''} needs "val" in an AC circuit');
          _branches.add(
              _Branch('R', e.name, from, to, value: Complex(0, -1 / (_omega! * _eval(e.val!))), element: 'C'));
        case 'ammeter' || 'inductor':
          _branches.add(_Branch('short', e.name, from, to));
        case 'voltmeter' || 'capacitor':
          _branches.add(_Branch('open', e.name, from, to));
        case 'cvsource' || 'ccsource':
          if (e.val == null || e.ctrl == null) {
            throw CircuitException('${e.type} ${e.name ?? ''} needs "val" (gain) and "ctrl"');
          }
          _branches.add(_Branch(e.type == 'cvsource' ? 'VC' : 'IC', e.name, from, to,
              value: Complex(_eval(e.val!)), ctrl: e.ctrl));
        default:
          throw CircuitException('The solver does not support "${e.type}" elements');
      }
    }

    // Ground: any ground symbol; otherwise the − terminal of the first voltage
    // source, otherwise the first branch node.
    int? groundRoot;
    for (final e in spec.elements.where((e) => e.type == 'ground')) {
      final r = _find(_point(e.at!));
      if (groundRoot != null) _union(r, groundRoot);
      groundRoot = _find(r);
    }
    if (groundRoot == null) {
      final v = _branches.where((b) => b.kind == 'V');
      if (v.isNotEmpty) {
        groundRoot = _find(_point(v.first.from));
      } else if (_branches.isNotEmpty) {
        groundRoot = _find(_point(_branches.first.from));
      }
    }
    _nodeIndex = {};
    var n = 0;
    for (final id in List.generate(_parent.length, (i) => i)) {
      final r = _find(id);
      if (r == groundRoot) {
        _nodeIndex[r] = -1;
      } else {
        _nodeIndex.putIfAbsent(r, () => n++);
      }
    }
  }

  static bool _onSegment(Offset p, Offset a, Offset b) {
    const eps = 1e-6;
    final ab = b - a, ap = p - a;
    final cross = ab.dx * ap.dy - ab.dy * ap.dx;
    if (cross.abs() > eps) return false;
    final dot = ab.dx * ap.dx + ab.dy * ap.dy;
    return dot >= -eps && dot <= ab.distanceSquared + eps;
  }

  static Map<String, Offset> _pins(CircuitElement e) {
    final a = e.at;
    if (a == null) return const {};
    switch (e.type) {
      case 'opamp':
        final top = a + const Offset(-1, -0.5);
        final bot = a + const Offset(-1, 0.5);
        return {'-': e.flip ? bot : top, '+': e.flip ? top : bot, 'out': a + const Offset(1, 0)};
      case 'gate':
        return {'in1': a + const Offset(-1, -0.3), 'in2': a + const Offset(-1, 0.3), 'out': a + const Offset(1, 0)};
      case 'npn' || 'pnp' || 'nmos' || 'pmos':
        return {'b': a + const Offset(-1, 0), 't': a + const Offset(0, -1), 'e': a + const Offset(0, 1)};
      default:
        return {'at': a};
    }
  }

  static String _ident(String label) =>
      label.replaceAll(RegExp(r'[{}]'), '').replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');

  double _eval(String expr) => Expression.eval(expr, vars);

  int _node(Offset p) => _nodeIndex[_find(_point(p))]!;

  // ---- MNA ----

  Map<String, double> _run() {
    _buildTopology();
    final out = <String, double>{};
    final main = _solve();

    void put(String name, Complex v) {
      if (_isAc) {
        out[name] = v.abs;
        out['${name}_ph'] = v.deg;
        out['${name}_re'] = v.re;
        out['${name}_im'] = v.im;
      } else {
        out[name] = v.re;
      }
    }

    for (final b in _branches) {
      if (b.name == null) continue;
      final (v, i) = main.branch(b);
      put('V_${b.name}', v);
      put('I_${b.name}', i);
      final s = _power(v, i);
      out['P_${b.name}'] = s.re;
      if (_isAc) {
        out['Q_${b.name}'] = s.im;
        out['S_${b.name}'] = s.abs;
        out['pf_${b.name}'] = s.abs < 1e-15 ? 1 : s.re / s.abs;
        if (b.kind == 'R') put('Z_${b.name}', b.value);
      }
    }
    _labelNodes.forEach((label, root) {
      final i = _nodeIndex[_find(root)]!;
      put('v_$label', main.nodeVoltage(i));
    });

    for (var i = 0; i < _terminals.length; i++) {
      for (var j = i + 1; j < _terminals.length; j++) {
        final a = _terminals[i], b = _terminals[j];
        final na = _nodeIndex[_find(_labelNodes[a]!)]!;
        final nb = _nodeIndex[_find(_labelNodes[b]!)]!;
        put('Voc_${a}_$b', main.v(na) - main.v(nb));
        try {
          final test = _solve(zeroSources: true, testCurrent: (na, nb));
          put('${_isAc ? 'Z' : 'R'}_${a}_$b', test.v(na) - test.v(nb));
        } on CircuitException {
          // No finite impedance between a and b.
        }
        try {
          final sc = _solve(shortBetween: (na, nb));
          put('Isc_${a}_$b', sc.shortCurrent);
        } on CircuitException {
          // Shorting the terminals is not allowed (e.g. across a source).
        }
      }
    }
    if (_terminals.length == 2) {
      final a = _terminals[0], b = _terminals[1];
      final pairs = _isAc ? {'Z': 'Zeq', 'Voc': 'Voc', 'Isc': 'Isc'} : {'R': 'Req', 'Voc': 'Voc', 'Isc': 'Isc'};
      pairs.forEach((k, alias) {
        for (final suffix in _isAc ? const ['', '_ph', '_re', '_im'] : const ['']) {
          final v = out['${k}_${a}_$b$suffix'];
          if (v != null) out['$alias$suffix'] = v;
        }
      });
    }
    for (final v in out.values) {
      if (!v.isFinite) throw CircuitException('Circuit has no unique solution');
    }
    return out;
  }

  _Solution _solve({
    bool zeroSources = false,
    (int, int)? testCurrent,
    (int, int)? shortBetween,
  }) {
    final n = _nodeIndex.values.where((v) => v >= 0).toSet().length;
    // Branches that add a current unknown.
    final vb = <_Branch>[
      for (final b in _branches)
        if (b.kind == 'V' || b.kind == 'short' || b.kind == 'VC' || b.kind == 'opamp') b,
    ];
    final size = n + vb.length + (shortBetween != null ? 1 : 0);
    final a = List.generate(size, (_) => List<Complex>.filled(size, Complex.zero));
    final rhs = List<Complex>.filled(size, Complex.zero);
    final branchRow = <_Branch, int>{for (var i = 0; i < vb.length; i++) vb[i]: n + i};

    void add(int r, int c, Complex v) => a[r][c] = a[r][c] + v;

    for (var i = 0; i < n; i++) {
      add(i, i, const Complex(_gmin));
    }

    void stampY(int p, int q, Complex y) {
      if (p >= 0) add(p, p, y);
      if (q >= 0) add(q, q, y);
      if (p >= 0 && q >= 0) {
        add(p, q, -y);
        add(q, p, -y);
      }
    }

    void inject(int node, Complex i) {
      if (node >= 0) rhs[node] = rhs[node] + i;
    }

    Map<int, Complex> control(String ctrl) => _control(ctrl, branchRow);

    for (final b in _branches) {
      final p = _node(b.from), q = _node(b.to);
      switch (b.kind) {
        case 'R':
          stampY(p, q, Complex.one / b.value);
        case 'I':
          final i = zeroSources ? Complex.zero : b.value;
          inject(q, i);
          inject(p, -i);
        case 'IC':
          // Current g·ctrl flows from→to inside the source (out of `to`).
          for (final e in control(b.ctrl!).entries) {
            if (q >= 0) add(q, e.key, -(b.value * e.value));
            if (p >= 0) add(p, e.key, b.value * e.value);
          }
        case 'V' || 'short' || 'VC':
          final k = branchRow[b]!;
          // i_k flows from node `to` through the branch to node `from`.
          if (q >= 0) {
            add(q, k, Complex.one);
            add(k, q, Complex.one);
          }
          if (p >= 0) {
            add(p, k, -Complex.one);
            add(k, p, -Complex.one);
          }
          if (b.kind == 'V') rhs[k] = zeroSources ? Complex.zero : b.value;
          if (b.kind == 'VC') {
            for (final e in control(b.ctrl!).entries) {
              add(k, e.key, -(b.value * e.value));
            }
          }
        case 'opamp':
          final k = branchRow[b]!;
          final o = _node(b.out!);
          if (o >= 0) add(o, k, Complex.one); // output supplies whatever current is needed
          if (p >= 0) add(k, p, Complex.one); // v+ − v− = 0
          if (q >= 0) add(k, q, -Complex.one);
        case 'open':
          break;
      }
    }

    if (testCurrent != null) {
      inject(testCurrent.$1, Complex.one);
      inject(testCurrent.$2, -Complex.one);
    }
    if (shortBetween != null) {
      final k = size - 1;
      final (p, q) = shortBetween;
      // Current k flows from a (p) to b (q) through the added short.
      if (p >= 0) {
        add(p, k, Complex.one);
        add(k, p, Complex.one);
      }
      if (q >= 0) {
        add(q, k, -Complex.one);
        add(k, q, -Complex.one);
      }
    }

    final x = _gauss(a, rhs);
    return _Solution(x, n, branchRow, this, shortBetween != null ? x[size - 1] : Complex.zero);
  }

  /// Linear expression for a control quantity: unknown index -> coefficient.
  Map<int, Complex> _control(String ctrl, Map<_Branch, int> branchRow) {
    final m = RegExp(r'^\s*([VI])\(\s*(\w+)\s*(?:,\s*(\w+)\s*)?\)\s*$').firstMatch(ctrl);
    if (m == null) throw CircuitException('Bad ctrl "$ctrl"');
    final coeffs = <int, Complex>{};
    void add(int idx, Complex c) {
      if (idx >= 0) coeffs[idx] = (coeffs[idx] ?? Complex.zero) + c;
    }

    if (m.group(3) != null) {
      add(_nodeOfLabel(m.group(2)!), Complex.one);
      add(_nodeOfLabel(m.group(3)!), -Complex.one);
      return coeffs;
    }
    final target = _branches.where((b) => b.name == m.group(2)).firstOrNull ??
        (throw CircuitException('ctrl refers to unknown element ${m.group(2)}'));
    final p = _node(target.from), q = _node(target.to);
    if (m.group(1) == 'V') {
      add(p, Complex.one);
      add(q, -Complex.one);
    } else if (target.kind == 'R') {
      add(p, Complex.one / target.value);
      add(q, -(Complex.one / target.value));
    } else if (branchRow.containsKey(target)) {
      // Current from→to through a voltage branch is −i_k.
      add(branchRow[target]!, -Complex.one);
    } else {
      throw CircuitException('Cannot use the current of ${target.name} as a control');
    }
    return coeffs;
  }

  int _nodeOfLabel(String label) {
    final root = _labelNodes[label];
    if (root == null) throw CircuitException('Unknown node label $label');
    return _nodeIndex[_find(root)]!;
  }

  static List<Complex> _gauss(List<List<Complex>> a, List<Complex> b) {
    final n = b.length;
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs > a[pivot][col].abs) pivot = r;
      }
      if (a[pivot][col].abs < 1e-14) {
        throw CircuitException('Circuit has no unique solution (singular matrix)');
      }
      if (pivot != col) {
        final t = a[pivot];
        a[pivot] = a[col];
        a[col] = t;
        final tb = b[pivot];
        b[pivot] = b[col];
        b[col] = tb;
      }
      for (var r = col + 1; r < n; r++) {
        final f = a[r][col] / a[col][col];
        if (f.re == 0 && f.im == 0) continue;
        for (var c = col; c < n; c++) {
          a[r][c] = a[r][c] - f * a[col][c];
        }
        b[r] = b[r] - f * b[col];
      }
    }
    final x = List<Complex>.filled(n, Complex.zero);
    for (var r = n - 1; r >= 0; r--) {
      var s = b[r];
      for (var c = r + 1; c < n; c++) {
        s = s - a[r][c] * x[c];
      }
      x[r] = s / a[r][r];
    }
    return x;
  }
}

// ---------------------------------------------------------------------------
// Worked solutions
// ---------------------------------------------------------------------------

/// A node of the circuit, as shown in a worked solution.
class ReportNode {
  ReportNode({required this.name, required this.at, required this.phasor, required this.ground});

  /// Display name: a terminal/node label, or A, B, C...; "0" for ground.
  final String name;

  /// Where to draw the node's tag on the schematic.
  final Offset at;

  /// Node voltage (a real number in DC circuits).
  final Complex phasor;
  final bool ground;

  /// DC node voltage.
  double get voltage => phasor.re;
}

/// Voltage, current and power of a named element.
class ReportElement {
  ReportElement({
    required this.name,
    required this.kind,
    required this.v,
    required this.i,
    required this.s,
  });

  final String name;

  /// 'R' (any impedance), 'V', 'I', 'VC', 'IC', 'short', 'open', 'opamp'.
  final String kind;

  /// Voltage and current phasors (real numbers in DC circuits).
  final Complex v;
  final Complex i;

  /// Complex power: absorbed for passive elements, delivered for sources.
  final Complex s;

  double get voltage => v.re;
  double get current => i.re;

  /// (Average) power: absorbed for passive elements, delivered for sources.
  double get power => s.re;

  bool get isSource => const {'V', 'I', 'VC', 'IC'}.contains(kind);
}

/// Step-by-step nodal analysis of a solved circuit. Equations are LaTeX.
class CircuitReport {
  CircuitReport({
    required this.nodes,
    required this.constraints,
    required this.equations,
    required this.elements,
    this.ac = false,
    this.impedances = const [],
    this.omegaTex,
    this.rms = false,
  });

  final List<ReportNode> nodes;

  /// Relations fixed by voltage sources, shorts and op amps.
  final List<String> constraints;

  /// KCL equations (sum of currents leaving a node or supernode = 0), with a
  /// description of where each is written.
  final List<(String, String)> equations;
  final List<ReportElement> elements;

  /// Whether this is a phasor (AC) solution.
  final bool ac;

  /// AC only: the impedance of every R, L and C (LaTeX).
  final List<String> impedances;

  /// AC only: the angular frequency (LaTeX), e.g. "\omega = 2\pi f = 314\,rad/s".
  final String? omegaTex;

  /// AC only: whether phasor magnitudes are peak or rms values.
  final bool rms;

  String get rmsNote => rms ? 'magnitudes are rms values' : 'magnitudes are peak values';

  /// A voltage or current for display: plain text in DC, a LaTeX phasor
  /// (inside $...$) in AC.
  String quantity(Complex v, String unit, [int sig = 3]) =>
      ac ? '\$${texPhasor(v, unit, sig)}\$' : SiFormat.format(v.re, unit, sig);
}

/// Formats a value with an SI prefix as LaTeX, e.g. 2200 Ω → 2.2\,\mathrm{k\Omega}.
String texValue(double v, String unit) {
  final s = SiFormat.format(v, unit);
  final i = s.indexOf(' ');
  if (i < 0) return s;
  final number = s.substring(0, i);
  return '$number\\,\\mathrm{${_texUnit(s.substring(i + 1))}}';
}

String _texUnit(String u) => u.replaceAll('Ω', r'\Omega ').replaceAll('µ', r'\mu ').trim();

/// A phasor as LaTeX, e.g. 3.2\angle{-45^\circ}\,\mathrm{mA}.
String texPhasor(Complex v, String unit, [int sig = 3]) {
  final s = SiFormat.format(v.abs, unit, sig);
  final i = s.indexOf(' ');
  final number = i < 0 ? s : s.substring(0, i);
  final u = i < 0 ? '' : '\\,\\mathrm{${_texUnit(s.substring(i + 1))}}';
  return '$number\\angle{${SiFormat.formatNumber(v.deg, 3)}^\\circ}$u';
}

/// A complex value in rectangular form as LaTeX, e.g. (10 + j31.4)\,\mathrm{\Omega}.
String texRect(Complex z, String unit) {
  final m = z.abs;
  if (m == 0) return '0\\,\\mathrm{${_texUnit(unit)}}';
  if (z.im.abs() <= 1e-9 * m) return texValue(z.re, unit);
  // One shared prefix for both parts, chosen from the larger one.
  final probe = SiFormat.format(m, unit);
  final sp = probe.indexOf(' ');
  final prefixUnit = sp < 0 ? unit : probe.substring(sp + 1);
  final prefix = prefixUnit.substring(0, prefixUnit.length - unit.length);
  const scales = {'p': 1e-12, 'n': 1e-9, 'µ': 1e-6, 'm': 1e-3, '': 1.0, 'k': 1e3, 'M': 1e6, 'G': 1e9};
  final k = scales[prefix] ?? 1.0;
  final u = '\\,\\mathrm{${_texUnit(prefixUnit)}}';
  final im = 'j${SiFormat.formatNumber(z.im.abs() / k)}';
  if (z.re.abs() <= 1e-9 * m) return '${z.im < 0 ? '-' : ''}$im$u';
  return '(${SiFormat.formatNumber(z.re / k)} ${z.im < 0 ? '-' : '+'} $im)$u';
}

extension on CircuitSolver {
  CircuitReport _report() {
    _buildTopology();
    final sol = _solve();
    final ac = _isAc;

    // Node names: labels where the author gave them, otherwise A, B, C...
    final used = <int>{};
    for (final b in _branches) {
      for (final p in [b.from, b.to, if (b.out != null) b.out!]) {
        used.add(_node(p));
      }
    }
    final names = <int, String>{-1: '0'};
    _labelNodes.forEach((label, root) {
      final i = _nodeIndex[_find(root)]!;
      if (i >= 0) names.putIfAbsent(i, () => label);
    });
    // Representative point per node: the point where most things connect.
    final touches = <String, int>{};
    void touch(Offset p) => touches[CircuitSolver._k(p)] = (touches[CircuitSolver._k(p)] ?? 0) + 1;
    for (final e in spec.elements) {
      if (e.from != null) touch(e.from!);
      if (e.to != null) touch(e.to!);
      if (e.type == 'node' && e.at != null) touches[CircuitSolver._k(e.at!)] = 99;
      for (final p in e.points) {
        touch(p);
      }
      for (final p in CircuitSolver._pins(e).values) {
        if (e.type != 'node') touch(p);
      }
    }
    final best = <int, (Offset, int)>{};
    _pointIds.forEach((key, id) {
      final node = _nodeIndex[_find(id)]!;
      final parts = key.split(',');
      final p = Offset(int.parse(parts[0]) / 1000, int.parse(parts[1]) / 1000);
      final t = touches[key] ?? 0;
      final cur = best[node];
      // Prefer junctions; break ties top-left so letters read naturally.
      if (cur == null ||
          t > cur.$2 ||
          (t == cur.$2 && (p.dy < cur.$1.dy || (p.dy == cur.$1.dy && p.dx < cur.$1.dx)))) {
        best[node] = (p, t);
      }
    });
    final unnamed = used.where((i) => i >= 0 && !names.containsKey(i)).toList()
      ..sort((a, b) {
        final pa = best[a]!.$1, pb = best[b]!.$1;
        return pa.dy != pb.dy ? pa.dy.compareTo(pb.dy) : pa.dx.compareTo(pb.dx);
      });
    var letter = 0;
    for (final i in unnamed) {
      // Skip letters that clash with author labels.
      String n;
      do {
        n = String.fromCharCode(65 + letter++);
      } while (names.containsValue(n));
      names[i] = n;
    }

    String v(int node) {
      if (node < 0) return '0';
      final n = names[node]!;
      final sub = n.startsWith('v_') ? n.substring(2) : n;
      final symbol = ac ? r'\mathbf{V}' : 'v';
      return sub.length == 1 ? '${symbol}_$sub' : '${symbol}_{\\text{${sub.replaceAll('_', r'\_')}}}';
    }

    String ctrlTex(String ctrl) {
      final m = RegExp(r'^\s*([VI])\(\s*(\w+)\s*(?:,\s*(\w+)\s*)?\)\s*$').firstMatch(ctrl);
      if (m == null) return ctrl;
      if (m.group(3) != null) {
        return '(${v(_nodeOfLabel(m.group(2)!))} - ${v(_nodeOfLabel(m.group(3)!))})';
      }
      final q = ac ? '\\mathbf{${m.group(1)!}}' : m.group(1)!.toLowerCase();
      return '${q}_{\\text{${m.group(2)}}}';
    }

    String sourceTex(Complex value, String unit) => ac ? texPhasor(value, unit) : texValue(value.re, unit);

    String zName(_Branch b) => 'Z_{\\text{${b.name}}}';
    String impedanceTex(_Branch b) => !ac
        ? texValue(b.value.re, 'Ω')
        : (b.name != null ? zName(b) : texRect(b.value, 'Ω'));

    // Supernodes: nodes tied together by voltage sources and shorts.
    final group = <int, int>{};
    int g(int n) {
      while (group[n] != null && group[n] != n) {
        n = group[n]!;
      }
      return n;
    }

    for (final i in used) {
      group[i] = i;
    }
    final constraints = <String>[];
    for (final b in _branches) {
      final p = _node(b.from), q = _node(b.to);
      switch (b.kind) {
        case 'V':
          group[g(p)] = g(q);
          constraints.add(p < 0
              ? '${v(q)} = ${sourceTex(b.value, 'V')}'
              : '${v(q)} - ${v(p)} = ${sourceTex(b.value, 'V')}');
        case 'VC':
          group[g(p)] = g(q);
          final gain = SiFormat.formatNumber(b.value.re);
          constraints.add(p < 0
              ? '${v(q)} = $gain\\,${ctrlTex(b.ctrl!)}'
              : '${v(q)} - ${v(p)} = $gain\\,${ctrlTex(b.ctrl!)}');
        case 'short':
          group[g(p)] = g(q);
          constraints.add('${v(p)} = ${v(q)}');
        case 'opamp':
          final (a, b) = p < 0 ? (q, p) : (p, q);
          constraints.add('${v(a)} = ${v(b)} \\quad \\text{(virtual short)}');
      }
    }
    final groundGroup = g(-1);
    final opampOutGroups = {
      for (final b in _branches.where((b) => b.kind == 'opamp')) g(_node(b.out!)),
    };

    // KCL per group: sum of currents leaving the group = 0.
    final members = <int, List<int>>{};
    for (final i in used) {
      members.putIfAbsent(g(i), () => []).add(i);
    }
    final equations = <(String, String)>[];
    final groupKeys = members.keys.toList()
      ..sort((a, b) => names[members[a]!.reduce((x, y) => x < y ? x : y)]!
          .compareTo(names[members[b]!.reduce((x, y) => x < y ? x : y)]!));
    for (final key in groupKeys) {
      if (key == groundGroup || opampOutGroups.contains(key)) continue;
      final inG = members[key]!.toSet();
      final terms = <String>[];
      for (final b in _branches) {
        final p = _node(b.from), q = _node(b.to);
        final pIn = inG.contains(p), qIn = inG.contains(q);
        if (pIn == qIn) continue;
        switch (b.kind) {
          case 'R':
            final (inner, outer) = pIn ? (p, q) : (q, p);
            final num = outer < 0 ? v(inner) : '${v(inner)} - ${v(outer)}';
            terms.add('\\frac{$num}{${impedanceTex(b)}}');
          case 'I':
            // Current flows from→to through the source: it leaves `from`.
            final t = sourceTex(b.value, 'A');
            terms.add(pIn ? '+ $t' : '- $t');
          case 'IC':
            final t = '${SiFormat.formatNumber(b.value.re)}\\,${ctrlTex(b.ctrl!)}';
            terms.add(pIn ? '+ $t' : '- $t');
        }
      }
      if (terms.isEmpty) continue;
      var eq = terms.join(' + ').replaceAll('+ + ', '+ ').replaceAll('+ - ', '- ');
      if (eq.startsWith('+ ')) eq = eq.substring(2);
      final where = inG.length == 1
          ? 'KCL at node ${names[inG.first]}'
          : 'KCL around the supernode ${(inG.map((i) => names[i]!).toList()..sort()).join(', ')}';
      equations.add((where, '$eq = 0'));
    }

    final impedances = <String>[
      if (ac)
        for (final b in _branches.where((b) => b.kind == 'R' && b.name != null))
          switch (b.element) {
            'L' => '${zName(b)} = j\\omega L = ${texRect(b.value, 'Ω')}',
            'C' => '${zName(b)} = \\frac{1}{j\\omega C} = ${texRect(b.value, 'Ω')}',
            _ => '${zName(b)} = R = ${texRect(b.value, 'Ω')}',
          },
    ];
    String? omegaTex;
    if (ac) {
      final ws = '${SiFormat.formatNumber(_omega!, 4)}\\,\\mathrm{rad/s}';
      omegaTex = spec.ac!.omega != null
          ? '\\omega = $ws'
          : '\\omega = 2\\pi f = 2\\pi \\cdot ${texValue(_omega / (2 * math.pi), 'Hz')} = $ws';
    }

    final nodes = [
      for (final i in used.toList()..sort((a, b) => names[a]!.compareTo(names[b]!)))
        ReportNode(name: names[i]!, at: best[i]?.$1 ?? Offset.zero, phasor: sol.nodeVoltage(i), ground: i < 0),
    ];
    final elements = [
      for (final b in _branches)
        if (b.name != null)
          () {
            final (vv, ii) = sol.branch(b);
            return ReportElement(name: b.name!, kind: b.kind, v: vv, i: ii, s: _power(vv, ii));
          }(),
    ];
    return CircuitReport(
      nodes: nodes,
      constraints: constraints,
      equations: equations,
      elements: elements,
      ac: ac,
      impedances: impedances,
      omegaTex: omegaTex,
      rms: spec.ac?.rms ?? false,
    );
  }
}

class CircuitException implements Exception {
  CircuitException(this.message);
  final String message;
  @override
  String toString() => 'CircuitException: $message';
}

class _Branch {
  _Branch(this.kind, this.name, this.from, this.to,
      {this.value = Complex.zero, this.ctrl, this.out, this.element});

  /// 'R' (any impedance), 'V', 'I', 'VC', 'IC', 'short', 'open', 'opamp'.
  final String kind;
  final String? name;
  final Offset from;
  final Offset to;

  /// Impedance (R), source phasor (V, I) or gain (VC, IC).
  final Complex value;
  final String? ctrl;

  /// 'R', 'L' or 'C' for impedance branches.
  final String? element;

  /// Op-amp output pin. For op amps [from] is the + input and [to] the − input.
  final Offset? out;
}

class _Solution {
  _Solution(this.x, this.n, this.branchRow, this.solver, this.shortCurrent);

  final List<Complex> x;
  final int n;
  final Map<_Branch, int> branchRow;
  final CircuitSolver solver;
  final Complex shortCurrent;

  Complex v(int node) => node < 0 ? Complex.zero : x[node];

  /// Largest node voltage and branch current, for removing rounding noise.
  late final double _vScale = [for (var i = 0; i < n; i++) x[i].abs].fold(0.0, math.max);
  late final double _iScale = [for (final b in solver._branches) _rawBranch(b).$2.abs].fold(0.0, math.max);

  /// Values that are only rounding noise next to the rest of the circuit
  /// (e.g. 3 pA through an element that carries no current) become 0.
  static Complex _clean(Complex v, double scale) => v.abs < 1e-9 * scale ? Complex.zero : v;

  /// Node voltage for display and export.
  Complex nodeVoltage(int node) => _clean(v(node), _vScale);

  /// (voltage, current) for a branch, using the conventions documented on
  /// [CircuitSolver].
  (Complex, Complex) branch(_Branch b) {
    final (vb, ib) = _rawBranch(b);
    return (_clean(vb, _vScale), _clean(ib, _iScale));
  }

  (Complex, Complex) _rawBranch(_Branch b) {
    final vFrom = v(solver._node(b.from));
    final vTo = v(solver._node(b.to));
    switch (b.kind) {
      case 'R':
        final vr = vFrom - vTo;
        return (vr, vr / b.value);
      case 'short' || 'open':
        final iFT = branchRow.containsKey(b) ? -x[branchRow[b]!] : Complex.zero;
        return (vFrom - vTo, iFT);
      case 'V' || 'VC':
        // i_k flows from `to` (+) through the source to `from`, so the
        // current delivered out of the + terminal is −i_k.
        return (vTo - vFrom, -x[branchRow[b]!]);
      case 'I':
        return (vTo - vFrom, b.value);
      case 'IC':
        // Current in the arrow direction = gain × control quantity.
        var ctrl = Complex.zero;
        solver._control(b.ctrl!, branchRow).forEach((i, c) => ctrl = ctrl + c * x[i]);
        return (vTo - vFrom, b.value * ctrl);
      case 'opamp':
        // Output voltage and the current flowing out of the output pin.
        return (v(solver._node(b.out!)), -x[branchRow[b]!]);
    }
    return (const Complex(double.nan), const Complex(double.nan));
  }
}

/// Default unit for an element's `val`, used for automatic value labels.
String unitForElement(String type) => switch (type) {
      'resistor' || 'lamp' => 'Ω',
      'vsource' || 'battery' || 'acsource' => 'V',
      'isource' => 'A',
      'capacitor' => 'F',
      'inductor' => 'H',
      _ => '',
    };

/// Formats an element value for its label, e.g. 4700 → "4.7 kΩ".
String formatElementValue(String type, double v) => SiFormat.format(v, unitForElement(type));
