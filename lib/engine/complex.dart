import 'dart:math' as math;

/// A complex number, used for phasors and impedances.
class Complex {
  const Complex(this.re, [this.im = 0]);

  /// From magnitude and angle in degrees.
  factory Complex.polar(double mag, double deg) {
    final r = deg * math.pi / 180;
    return Complex(mag * math.cos(r), mag * math.sin(r));
  }

  static const zero = Complex(0);
  static const one = Complex(1);

  final double re;
  final double im;

  Complex operator +(Complex o) => Complex(re + o.re, im + o.im);
  Complex operator -(Complex o) => Complex(re - o.re, im - o.im);
  Complex operator -() => Complex(-re, -im);
  Complex operator *(Complex o) => Complex(re * o.re - im * o.im, re * o.im + im * o.re);
  Complex operator /(Complex o) {
    final d = o.re * o.re + o.im * o.im;
    return Complex((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
  }

  Complex scale(double k) => Complex(re * k, im * k);
  Complex get conj => Complex(re, -im);
  double get abs => math.sqrt(re * re + im * im);
  double get abs2 => re * re + im * im;

  /// Angle in degrees, in (−180, 180]; 0 for (near) zero values.
  double get deg {
    if (abs < 1e-15) return 0;
    final d = math.atan2(im, re) * 180 / math.pi;
    return d <= -180 + 1e-9 ? 180 : d;
  }

  bool get isFinite => re.isFinite && im.isFinite;

  @override
  String toString() => '($re${im < 0 ? '-' : '+'}j${im.abs()})';
}
