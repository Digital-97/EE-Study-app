import 'dart:ui';

/// A schematic described on a grid, rendered by `CircuitDiagram`.
///
/// See CONTENT_GUIDE.md for the authoring format.
class CircuitSpec {
  CircuitSpec(this.elements, {this.height, this.ac});

  final List<CircuitElement> elements;

  /// Optional maximum rendered height in logical pixels.
  final double? height;

  /// Sinusoidal steady state (phasor analysis) settings; null for DC.
  final AcSettings? ac;

  factory CircuitSpec.fromJson(Map<String, dynamic> j) => CircuitSpec(
        [
          for (final e in (j['elements'] as List))
            CircuitElement.fromJson(e as Map<String, dynamic>),
        ],
        height: (j['height'] as num?)?.toDouble(),
        ac: j['ac'] == null ? null : AcSettings.fromJson(j['ac'] as Map<String, dynamic>),
      );

  /// Returns a copy with all labels passed through [transform] (used to
  /// substitute `{{param}}` placeholders). Elements with a solver `val` but
  /// no `value` label get [autoValue] as their value label.
  CircuitSpec mapText(String Function(String) transform,
          {String? Function(CircuitElement e)? autoValue}) =>
      CircuitSpec(
        [for (final e in elements) e.mapText(transform, autoValue: autoValue?.call(e))],
        height: height,
        ac: ac,
      );
}

/// The frequency of an AC (phasor) circuit: `{"f": "<expr in Hz>"}` or
/// `{"omega": "<expr in rad/s>"}`. Source values are peak phasor magnitudes
/// unless `"rms": true`.
class AcSettings {
  AcSettings({this.f, this.omega, this.rms = false});

  final String? f;
  final String? omega;
  final bool rms;

  factory AcSettings.fromJson(Map<String, dynamic> j) => AcSettings(
        f: j['f']?.toString(),
        omega: j['omega']?.toString(),
        rms: (j['rms'] ?? false) as bool,
      );
}

/// Element kinds placed between two points.
const twoTerminalTypes = {
  'resistor',
  'capacitor',
  'inductor',
  'vsource',
  'isource',
  'acsource',
  'battery',
  'cvsource',
  'ccsource',
  'diode',
  'zener',
  'led',
  'switch',
  'lamp',
  'voltmeter',
  'ammeter',
  'motor',
  'generator',
};

/// Element kinds placed at a single point.
const pointTypes = {
  'ground',
  'node',
  'terminal',
  'text',
  'opamp',
  'gate',
  'npn',
  'pnp',
  'nmos',
  'pmos',
  'loop',
  'tag',
  'transformer',
  'block',
  'sum',
};

const allCircuitTypes = {'wire', 'signal', 'arrow', ...twoTerminalTypes, ...pointTypes};

class CircuitElement {
  CircuitElement({
    required this.type,
    this.points = const [],
    this.from,
    this.to,
    this.at,
    this.label,
    this.value,
    this.flip = false,
    this.polarity,
    this.kind,
    this.closed = false,
    this.rotation = 0,
    this.name,
    this.val,
    this.ctrl,
    this.size,
    this.phase,
  });

  final String type;
  final List<Offset> points;
  final Offset? from;
  final Offset? to;
  final Offset? at;
  final String? label;
  final String? value;
  final bool flip;

  /// "+-" puts + at `from` and − at `to`; "-+" the reverse.
  final String? polarity;

  /// Gate kind (and, or, not, nand, nor, xor, xnor).
  final String? kind;

  /// For switches: closed or open.
  final bool closed;

  /// For ground: rotation in degrees (0 = pointing down).
  final double rotation;

  /// Identifier used by the circuit solver, e.g. "R5" (exports V_R5, I_R5...).
  final String? name;

  /// Value expression for the solver (Ω, V, A or gain), e.g. "R5" or "4700".
  final String? val;

  /// Control quantity of a dependent source, e.g. "V(R2)" or "I(R1)".
  final String? ctrl;

  /// Width and height of a `block` in grid units (default 2 × 1).
  final Offset? size;

  /// Phase in degrees of an AC source phasor (expression; default 0).
  final String? phase;

  static Offset _pt(dynamic v) {
    final l = v as List;
    return Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
  }

  factory CircuitElement.fromJson(Map<String, dynamic> j) => CircuitElement(
        type: j['type'] as String,
        points: [for (final p in (j['points'] as List? ?? const [])) _pt(p)],
        from: j['from'] == null ? null : _pt(j['from']),
        to: j['to'] == null ? null : _pt(j['to']),
        at: j['at'] == null ? null : _pt(j['at']),
        label: j['label']?.toString(),
        value: j['value']?.toString(),
        flip: (j['flip'] ?? false) as bool,
        polarity: j['polarity'] as String?,
        kind: j['kind'] as String?,
        closed: (j['closed'] ?? false) as bool,
        rotation: ((j['rotation'] ?? 0) as num).toDouble(),
        name: j['name'] as String?,
        val: j['val']?.toString(),
        ctrl: j['ctrl'] as String?,
        size: j['size'] == null ? null : _pt(j['size']),
        phase: j['phase']?.toString(),
      );

  CircuitElement mapText(String Function(String) t, {String? autoValue}) => CircuitElement(
        type: type,
        points: points,
        from: from,
        to: to,
        at: at,
        label: label == null ? null : t(label!),
        value: value == null ? autoValue : t(value!),
        flip: flip,
        polarity: polarity,
        kind: kind,
        closed: closed,
        rotation: rotation,
        name: name,
        val: val,
        ctrl: ctrl,
        size: size,
        phase: phase,
      );

  /// All grid points this element touches (for bounds computation).
  List<Offset> get extent {
    final out = <Offset>[...points];
    if (from != null) out.add(from!);
    if (to != null) out.add(to!);
    if (at != null) {
      final a = at!;
      switch (type) {
        case 'opamp':
          out.addAll([a + const Offset(-1.2, -1), a + const Offset(1.2, 1)]);
        case 'gate':
          out.addAll([a + const Offset(-1, -0.8), a + const Offset(1, 0.8)]);
        case 'npn' || 'pnp' || 'nmos' || 'pmos':
          out.addAll([a + const Offset(-1, -1), a + const Offset(0.6, 1)]);
        case 'ground':
          out.add(a + const Offset(0, 0.6));
        case 'loop':
          out.addAll([a + const Offset(-0.5, -0.5), a + const Offset(0.5, 0.5)]);
        case 'transformer':
          out.addAll([a + const Offset(-1, -1.1), a + const Offset(1, 1.1)]);
        case 'block':
          final sz = size ?? const Offset(2, 1);
          out.addAll([a - sz / 2, a + sz / 2]);
        case 'sum':
          out.addAll([a + const Offset(-0.5, -0.5), a + const Offset(0.5, 0.5)]);
        default:
          out.add(a);
      }
    }
    return out;
  }
}
