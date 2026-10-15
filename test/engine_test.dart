import 'package:ee_study/engine/expression.dart';
import 'package:ee_study/engine/step_instance.dart';
import 'package:ee_study/engine/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expressions', () {
    expect(Expression.eval('2 + 3 * 4', {}), 14);
    expect(Expression.eval('-2^2', {}), -4);
    expect(Expression.eval('2^-1', {}), 0.5);
    expect(Expression.eval('par(R1, R2)', {'R1': 1000, 'R2': 1000}), 500);
    expect(Expression.eval('1e3 * x', {'x': 2}), 2000);
    expect(Expression.eval('deg(atan2(1, 1))', {}), closeTo(45, 1e-12));
    expect(() => Expression.eval('foo(1)', {}), throwsA(isA<ExpressionException>()));
    expect(Expression.eval('step(-1) + step(0) + step(2)', {}), 2);
    expect(Expression.eval('sign(-3)', {}), -1);
    expect(Expression.eval('clamp(15, -12, 12)', {}), 12);
    expect(Expression.eval('mod(-1, 4)', {}), 3);
  });

  test('functions for probability, coding and lines', () {
    expect(Expression.eval('log2(8)', {}), closeTo(3, 1e-12));
    expect(Expression.eval('cosh(1)^2 - sinh(1)^2', {}), closeTo(1, 1e-12));
    expect(Expression.eval('tanh(atanh(0.5))', {}), closeTo(0.5, 1e-12));
    expect(Expression.eval('tanh(100)', {}), 1);
    expect(Expression.eval('erf(1)', {}), closeTo(0.8427007929, 1e-7));
    expect(Expression.eval('erfc(-1)', {}), closeTo(1.8427007929, 1e-7));
    expect(Expression.eval('Q(0)', {}), closeTo(0.5, 1e-7));
    expect(Expression.eval('Q(1)', {}), closeTo(0.158655254, 1e-7));
    // Relative accuracy far in the tail (BER-sized values).
    expect(Expression.eval('Q(6)', {}) / 9.865876450e-10, closeTo(1, 1e-6));
    expect(Expression.eval('fact(5)', {}), 120);
    expect(Expression.eval('choose(10, 3)', {}), 120);
    expect(Expression.eval('choose(7, 0) + choose(3, 5)', {}), 1);
    expect(Expression.eval('xor(12, 10)', {}), 6);
    expect(Expression.eval('popcount(xor(45, 54))', {}), 4);
    expect(Expression.eval('bit(5, 0) + bit(5, 1) + bit(5, 2)', {}), 2);
    expect(() => Expression.eval('bit(2.5, 0)', {}), throwsA(isA<ExpressionException>()));
  });

  test('placeholders', () {
    expect(StepInstance.fill(r'$\frac{{{V}}}{2}$', {'V': 5}), r'$\frac{5}{2}$');
    expect(StepInstance.fill('{{R|Ω}} and {{R*2||4}}', {'R': 4700}), '4.7 kΩ and 9400');
    expect(StepInstance.fill('{{5*cos(rad(90))|V}}', {}), '0 V');
    expect(StepInstance.fill('0x{{n|hex|4}} = {{n|bin|8}}', {'n': 171}), '0x00AB = 10101011');
  });

  test('SI formatting', () {
    expect(SiFormat.format(4700, 'Ω'), '4.7 kΩ');
    expect(SiFormat.format(0.0025, 'A'), '2.5 mA');
    expect(SiFormat.format(999.7, 'Ω'), '1 kΩ');
    expect(SiFormat.format(12, 'V'), '12 V');
    expect(SiFormat.format(-0.5, 'W'), '-500 mW');
    expect(SiFormat.format(45.123, '°'), '45.1°');
    expect(SiFormat.format(1455, 'rpm', 4), '1455 rpm');
    expect(SiFormat.format(-0.5, 'dBm'), '-0.5 dBm');
    expect(SiFormat.format(0.25, 'dBµV/m'), '0.25 dBµV/m');
    expect(SiFormat.format(0.5, '°C'), '0.5 °C');
    expect(SiFormat.takesPrefix('dB/dec'), isFalse);
    expect(SiFormat.takesPrefix('bps'), isTrue);
    expect(SiFormat.format(0.95, 'pu'), '0.95 pu');
    expect(SiFormat.format(1.5e16, 'cm⁻³'), '1.5e16 cm⁻³');
    expect(SiFormat.format(0.47, 'bits'), '0.47 bits');
    expect(SiFormat.format(65, '°C/W'), '65 °C/W');
    expect(SiFormat.format(0.35, 'µm'), '0.35 µm');
    // Small answers compare relatively: 5.7 nF is not 4.7 nF.
    expect(SiFormat.isClose(5.7e-9, 4.7e-9), isFalse);
    expect(SiFormat.isClose(4.75e-9, 4.7e-9), isTrue);
    expect(SiFormat.isClose(0, 1e-17), isTrue);
    expect(SiFormat.parse('8f', 'V²/Hz'), closeTo(8e-15, 1e-27));
    expect(SiFormat.parse('3f3', 'F'), closeTo(3.3e-15, 1e-27));
    expect(SiFormat.format(0.5, 'cm'), '0.5 cm');
    expect(SiFormat.format(0.5, 'h'), '0.5 h');
    expect(SiFormat.formatNumber(1234), '1230');
    expect(SiFormat.formatNumber(1234, 4), '1234');
  });

  test('SI parsing', () {
    expect(SiFormat.parse('4.7k'), 4700);
    expect(SiFormat.parse('4k7'), 4700);
    expect(SiFormat.parse('4,7 kΩ', 'Ω'), 4700);
    expect(SiFormat.parse('2.5m'), 0.0025);
    expect(SiFormat.parse('2.5 mA', 'A'), 0.0025);
    expect(SiFormat.parse('10µ'), closeTo(1e-5, 1e-18));
    expect(SiFormat.parse('10u'), closeTo(1e-5, 1e-18));
    expect(SiFormat.parse('-3.2'), -3.2);
    expect(SiFormat.parse('1e-3'), 0.001);
    expect(SiFormat.parse('1/3'), closeTo(1 / 3, 1e-12));
    expect(SiFormat.parse('abc'), isNull);
    expect(SiFormat.isClose(4.75, 4.7), isTrue);
    expect(SiFormat.isClose(4.9, 4.7), isFalse);
  });
}
