import 'dart:math' as math;

/// Formatting and parsing of values with SI prefixes (e.g. 4.7 kΩ, 2.5 mA).
class SiFormat {
  static const _prefixes = <int, String>{
    -12: 'p',
    -9: 'n',
    -6: 'µ',
    -3: 'm',
    0: '',
    3: 'k',
    6: 'M',
    9: 'G',
  };

  /// Units for which SI prefixes should not be applied.
  static const _noPrefixUnits = {
    '%', '°', '°C', 'rad', 's⁻¹', 'rpm', '',
    // Units that already carry a prefix, or are not SI: "500 mcm", "500 mh".
    'cm', 'mm', 'km', 'cm²', 'mm²', 'h', 'min', 'bins',
    // Per-unit values, kelvin, information and device-physics units.
    'pu', 'K', 'bit', 'bits', 'bit/symbol', 'bits/symbol', 'bit/s/Hz', 'bits/s/Hz',
    'cm⁻³', 'cm²/V·s', 'cm²/s', 'cm/s',
    // Units that already carry a prefix or that a prefix would garble.
    'µm', 'nm', '°C/W', 'K/W', 'V⁻¹',
  };

  /// Whether values in [unit] get SI prefixes. Logarithmic units (dB, dBm,
  /// dBµV/m, dB/dec, …) never do: "-500 mdBm" would be meaningless.
  static bool takesPrefix(String unit) =>
      !_noPrefixUnits.contains(unit) && !unit.startsWith('dB');

  /// Formats [value] with [sig] significant figures and an engineering
  /// prefix when [unit] is given, e.g. `format(0.0047, 'A')` → `4.7 mA`.
  static String format(double value, [String unit = '', int sig = 3]) {
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value > 0 ? '∞' : '-∞';
    if (!takesPrefix(unit)) {
      final s = formatNumber(value, sig);
      if (unit.isEmpty) return s;
      return unit == '%' || unit == '°' ? '$s$unit' : '$s $unit';
    }
    if (value == 0) return '0 $unit';
    var exp = (math.log(value.abs()) / math.ln10).floor();
    var eng = (exp / 3).floor() * 3;
    eng = eng.clamp(-12, 9);
    var scaled = value / math.pow(10, eng);
    // Rounding could push 999.7 → 1000; move to next prefix in that case.
    final rounded = double.parse(scaled.toStringAsPrecision(sig));
    if (rounded.abs() >= 1000 && eng < 9) {
      eng += 3;
      scaled = value / math.pow(10, eng);
    }
    return '${formatNumber(scaled, sig)} ${_prefixes[eng]}$unit';
  }

  /// Formats a plain number with up to [sig] significant figures, trimming
  /// trailing zeros (e.g. 4.700 → 4.7, 12.0 → 12).
  static String formatNumber(double value, [int sig = 3]) {
    if (value == 0) return '0';
    if (value.isNaN) return 'NaN';
    final abs = value.abs();
    if (abs >= 1e6 || abs < 1e-4) {
      final s = value.toStringAsExponential(sig - 1);
      final parts = s.split('e');
      return '${_trim(parts[0])}e${parts[1].replaceAll('+', '')}';
    }
    final digits = (math.log(abs) / math.ln10).floor() + 1;
    final decimals = (sig - digits).clamp(0, 12);
    final fixed = value.toStringAsFixed(decimals);
    // Large integers beyond sig figures: round them.
    if (decimals == 0 && digits > sig) {
      final factor = math.pow(10, digits - sig);
      return ((value / factor).round() * factor).toStringAsFixed(0);
    }
    return _trim(fixed);
  }

  static String _trim(String s) {
    if (!s.contains('.')) return s;
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  static const _inputPrefixes = <String, double>{
    'f': 1e-15,
    'p': 1e-12,
    'n': 1e-9,
    'u': 1e-6,
    'µ': 1e-6,
    'μ': 1e-6,
    'm': 1e-3,
    'k': 1e3,
    'K': 1e3,
    'M': 1e6,
    'G': 1e9,
  };

  /// Parses user input like `4.7k`, `4,7 k`, `2.5m`, `10u`, `1e-3`, `-3.2`,
  /// `4k7`. The trailing [unit] (e.g. `Ω`, `A`) is optional and ignored.
  /// Returns null when the input cannot be parsed.
  static double? parse(String input, [String unit = '']) {
    var s = input.trim().replaceAll(' ', '').replaceAll(',', '.');
    s = s.replaceAll('−', '-');
    if (s.isEmpty) return null;
    if (unit.isNotEmpty && s.endsWith(unit)) {
      s = s.substring(0, s.length - unit.length);
    }
    // Common unit spellings users might type.
    for (final u in const ['ohm', 'Ohm', 'Ω', 'Hz', 'V', 'A', 'W', 'F', 'H', 'J', 'C', 's', '%', '°']) {
      if (s.length > u.length && s.endsWith(u)) {
        final rest = s.substring(0, s.length - u.length);
        // Avoid stripping 'm' style prefixes by accident: only strip known units.
        s = rest;
        break;
      }
    }
    if (s.isEmpty) return null;
    final direct = double.tryParse(s);
    if (direct != null) return direct;

    // Fraction like 1/3.
    final frac = RegExp(r'^(-?\d*\.?\d+)/(\d*\.?\d+)$').firstMatch(s);
    if (frac != null) {
      final a = double.parse(frac.group(1)!);
      final b = double.parse(frac.group(2)!);
      return b == 0 ? null : a / b;
    }

    // Number followed by prefix: 4.7k, 10u, 2e3k (unlikely).
    final suffix = RegExp(r'^(-?\d*\.?\d+(?:[eE][-+]?\d+)?)([fpnuµμmkKMG])$').firstMatch(s);
    if (suffix != null) {
      return double.parse(suffix.group(1)!) * _inputPrefixes[suffix.group(2)!]!;
    }
    // Prefix used as decimal point: 4k7 → 4.7k.
    final infix = RegExp(r'^(-?\d+)([fpnuµμmkKMG])(\d+)$').firstMatch(s);
    if (infix != null) {
      return double.parse('${infix.group(1)}.${infix.group(3)}') *
          _inputPrefixes[infix.group(2)!]!;
    }
    return null;
  }

  /// Whether [given] is within tolerance of [expected].
  ///
  /// [relTol] is relative (0.02 = 2 %). When the expected value is (close to)
  /// zero, [absTol] is used instead.
  static bool isClose(double given, double expected,
      {double relTol = 0.02, double absTol = 1e-12}) {
    if (expected.isNaN || given.isNaN) return false;
    final diff = (given - expected).abs();
    if (diff <= absTol) return true;
    return diff <= relTol * expected.abs();
  }
}
