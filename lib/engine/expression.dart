import 'dart:math' as math;

/// A small arithmetic expression evaluator used by lesson content.
///
/// Supports numbers (incl. scientific notation), variables, + - * / ^,
/// parentheses, unary minus and a set of functions useful for EE problems:
/// sqrt, abs, exp, ln, log10, sin, cos, tan, asin, acos, atan, atan2,
/// deg, rad, min, max, round, floor, ceil, par (parallel resistance),
/// step (unit step), sign, clamp(x, lo, hi), mod(a, b), if(c, a, b) (a when
/// c > 0, else b), sinc(x) = sin(πx)/(πx), step2(t, zeta, wn) (unit-step
/// response of ωn²/(s² + 2ζωn·s + ωn²) for any ζ ≥ 0),
/// sum(k, from, to, expr) (Σ expr for integer k = from..to), log2, sinh,
/// cosh, tanh, atanh, erf, erfc, Q (Gaussian tail), fact, choose(n, k), and
/// for codes on non-negative integers xor(a, b), popcount(n), bit(n, i).
/// Constants: pi, e.
class Expression {
  Expression._(this._root);

  final _Node _root;

  static final Map<String, Expression> _cache = {};

  static Expression parse(String source) {
    return _cache.putIfAbsent(source, () => Expression._(_Parser(source).parse()));
  }

  double evaluate(Map<String, double> vars) => _root.eval(vars);

  /// Variables referenced by the expression.
  Set<String> get variables {
    final out = <String>{};
    _root.collectVars(out);
    return out;
  }

  static double eval(String source, Map<String, double> vars) =>
      parse(source).evaluate(vars);
}

class ExpressionException implements Exception {
  ExpressionException(this.message);
  final String message;
  @override
  String toString() => 'ExpressionException: $message';
}

abstract class _Node {
  double eval(Map<String, double> vars);
  void collectVars(Set<String> out) {}
}

class _Num extends _Node {
  _Num(this.value);
  final double value;
  @override
  double eval(Map<String, double> vars) => value;
}

class _Var extends _Node {
  _Var(this.name);
  final String name;
  @override
  double eval(Map<String, double> vars) {
    final v = vars[name];
    if (v != null) return v;
    if (name == 'pi') return math.pi;
    if (name == 'e') return math.e;
    throw ExpressionException('Unknown variable "$name"');
  }

  @override
  void collectVars(Set<String> out) {
    if (name != 'pi' && name != 'e') out.add(name);
  }
}

class _Unary extends _Node {
  _Unary(this.child);
  final _Node child;
  @override
  double eval(Map<String, double> vars) => -child.eval(vars);
  @override
  void collectVars(Set<String> out) => child.collectVars(out);
}

class _Binary extends _Node {
  _Binary(this.op, this.left, this.right);
  final String op;
  final _Node left;
  final _Node right;

  @override
  double eval(Map<String, double> vars) {
    final a = left.eval(vars);
    final b = right.eval(vars);
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '*':
        return a * b;
      case '/':
        return a / b;
      case '^':
        return math.pow(a, b).toDouble();
    }
    throw ExpressionException('Unknown operator $op');
  }

  @override
  void collectVars(Set<String> out) {
    left.collectVars(out);
    right.collectVars(out);
  }
}

class _Call extends _Node {
  _Call(this.name, this.args);
  final String name;
  final List<_Node> args;

  @override
  double eval(Map<String, double> vars) {
    if (name == 'sum') return _sum(vars);
    final a = args.map((n) => n.eval(vars)).toList();
    void arity(int n) {
      if (a.length != n) {
        throw ExpressionException('$name expects $n argument(s), got ${a.length}');
      }
    }

    switch (name) {
      case 'sqrt':
        arity(1);
        return math.sqrt(a[0]);
      case 'abs':
        arity(1);
        return a[0].abs();
      case 'exp':
        arity(1);
        return math.exp(a[0]);
      case 'ln':
        arity(1);
        return math.log(a[0]);
      case 'log10':
      case 'log':
        arity(1);
        return math.log(a[0]) / math.ln10;
      case 'sin':
        arity(1);
        return math.sin(a[0]);
      case 'cos':
        arity(1);
        return math.cos(a[0]);
      case 'tan':
        arity(1);
        return math.tan(a[0]);
      case 'asin':
        arity(1);
        return math.asin(a[0]);
      case 'acos':
        arity(1);
        return math.acos(a[0]);
      case 'atan':
        arity(1);
        return math.atan(a[0]);
      case 'atan2':
        arity(2);
        return math.atan2(a[0], a[1]);
      case 'deg':
        arity(1);
        return a[0] * 180 / math.pi;
      case 'rad':
        arity(1);
        return a[0] * math.pi / 180;
      case 'round':
        arity(1);
        return a[0].roundToDouble();
      case 'floor':
        arity(1);
        return a[0].floorToDouble();
      case 'ceil':
        arity(1);
        return a[0].ceilToDouble();
      case 'min':
        if (a.isEmpty) throw ExpressionException('min needs arguments');
        return a.reduce(math.min);
      case 'max':
        if (a.isEmpty) throw ExpressionException('max needs arguments');
        return a.reduce(math.max);
      case 'step':
        // Unit step: 0 for x < 0, 1 for x >= 0.
        arity(1);
        return a[0] < 0 ? 0 : 1;
      case 'sign':
        arity(1);
        return a[0] == 0 ? 0 : (a[0] < 0 ? -1 : 1);
      case 'clamp':
        arity(3);
        return a[0].clamp(a[1], a[2]).toDouble();
      case 'mod':
        // Always non-negative for positive b, handy for periodic waveforms.
        arity(2);
        return a[0] - a[1] * (a[0] / a[1]).floorToDouble();
      case 'par':
        // Parallel combination: 1 / (1/a + 1/b + ...)
        if (a.isEmpty) throw ExpressionException('par needs arguments');
        return 1 / a.fold<double>(0, (s, x) => s + 1 / x);
      case 'if':
        arity(3);
        return a[0] > 0 ? a[1] : a[2];
      case 'sinc':
        arity(1);
        return a[0] == 0 ? 1 : math.sin(math.pi * a[0]) / (math.pi * a[0]);
      case 'step2':
        arity(3);
        return _step2(a[0], a[1], a[2]);
      case 'log2':
        arity(1);
        return math.log(a[0]) / math.ln2;
      case 'sinh':
        arity(1);
        return (math.exp(a[0]) - math.exp(-a[0])) / 2;
      case 'cosh':
        arity(1);
        return (math.exp(a[0]) + math.exp(-a[0])) / 2;
      case 'tanh':
        arity(1);
        if (a[0].abs() > 20) return a[0].sign;
        final e2 = math.exp(2 * a[0]);
        return (e2 - 1) / (e2 + 1);
      case 'atanh':
        arity(1);
        return 0.5 * math.log((1 + a[0]) / (1 - a[0]));
      case 'erf':
        arity(1);
        return 1 - _erfc(a[0]);
      case 'erfc':
        arity(1);
        return _erfc(a[0]);
      case 'Q':
        // Gaussian tail probability: Q(x) = P(Z > x) = ½·erfc(x/√2).
        arity(1);
        return 0.5 * _erfc(a[0] / math.sqrt2);
      case 'fact':
        arity(1);
        return _fact(a[0]);
      case 'choose':
        arity(2);
        return _choose(a[0], a[1]);
      case 'xor':
        arity(2);
        return (_int(a[0]) ^ _int(a[1])).toDouble();
      case 'popcount':
        arity(1);
        var n = _int(a[0]), c = 0;
        while (n > 0) {
          c += n & 1;
          n >>= 1;
        }
        return c.toDouble();
      case 'bit':
        // Bit i (0 = least significant) of a non-negative integer.
        arity(2);
        return ((_int(a[0]) >> _int(a[1])) & 1).toDouble();
    }
    throw ExpressionException('Unknown function "$name"');
  }

  /// A non-negative integer argument (for the bit functions).
  int _int(double v) {
    final n = v.round();
    if (n < 0 || (v - n).abs() > 1e-9) throw ExpressionException('$name expects non-negative integers, got $v');
    return n;
  }

  /// Complementary error function, relative error below 1.2e-7 everywhere
  /// (Chebyshev fit from Numerical Recipes), so Q(x) stays accurate for
  /// tiny bit-error rates.
  static double _erfc(double x) {
    final z = x.abs();
    final t = 1 / (1 + 0.5 * z);
    final r = t *
        math.exp(-z * z -
            1.26551223 +
            t * (1.00002368 +
                t * (0.37409196 +
                    t * (0.09678418 +
                        t * (-0.18628806 +
                            t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
    return x >= 0 ? r : 2 - r;
  }

  double _fact(double v) {
    final n = _int(v);
    if (n > 170) throw ExpressionException('fact($n) is too large');
    var f = 1.0;
    for (var i = 2; i <= n; i++) {
      f *= i;
    }
    return f;
  }

  /// Binomial coefficient n over k (0 when k > n).
  double _choose(double nv, double kv) {
    final n = _int(nv), k = _int(kv);
    if (k > n) return 0;
    var c = 1.0;
    for (var i = 1; i <= math.min(k, n - k); i++) {
      c = c * (n - math.min(k, n - k) + i) / i;
    }
    return c.roundToDouble();
  }

  /// Unit-step response of a standard second-order system.
  static double _step2(double t, double zeta, double wn) {
    if (t < 0) return 0;
    final x = wn * t;
    if ((zeta - 1).abs() < 1e-6) return 1 - math.exp(-x) * (1 + x);
    if (zeta < 1) {
      final wd = math.sqrt(1 - zeta * zeta);
      return 1 - math.exp(-zeta * x) * (math.cos(wd * x) + zeta / wd * math.sin(wd * x));
    }
    final r = math.sqrt(zeta * zeta - 1);
    final s1 = -zeta + r, s2 = -zeta - r; // both negative (times wn)
    return 1 + (s2 * math.exp(s1 * x) - s1 * math.exp(s2 * x)) / (s1 - s2);
  }

  double _sum(Map<String, double> vars) {
    if (args.length != 4 || args[0] is! _Var) {
      throw ExpressionException('sum expects (k, from, to, expr)');
    }
    final k = (args[0] as _Var).name;
    final from = args[1].eval(vars).round(), to = args[2].eval(vars).round();
    if (to - from > 10000) throw ExpressionException('sum range too large');
    final local = Map<String, double>.of(vars);
    var total = 0.0;
    for (var i = from; i <= to; i++) {
      local[k] = i.toDouble();
      total += args[3].eval(local);
    }
    return total;
  }

  @override
  void collectVars(Set<String> out) {
    if (name == 'sum' && args.length == 4 && args[0] is _Var) {
      final inner = <String>{};
      args[3].collectVars(inner);
      inner.remove((args[0] as _Var).name);
      out.addAll(inner);
      args[1].collectVars(out);
      args[2].collectVars(out);
      return;
    }
    for (final n in args) {
      n.collectVars(out);
    }
  }
}

class _Parser {
  _Parser(this.src);
  final String src;
  int pos = 0;

  _Node parse() {
    final node = _expr();
    _skipWs();
    if (pos != src.length) {
      throw ExpressionException('Unexpected "${src.substring(pos)}" in "$src"');
    }
    return node;
  }

  void _skipWs() {
    while (pos < src.length && src[pos].trim().isEmpty) {
      pos++;
    }
  }

  bool _eat(String ch) {
    _skipWs();
    if (pos < src.length && src[pos] == ch) {
      pos++;
      return true;
    }
    return false;
  }

  _Node _expr() {
    var node = _term();
    while (true) {
      if (_eat('+')) {
        node = _Binary('+', node, _term());
      } else if (_eat('-')) {
        node = _Binary('-', node, _term());
      } else {
        return node;
      }
    }
  }

  _Node _term() {
    var node = _unary();
    while (true) {
      if (_eat('*')) {
        node = _Binary('*', node, _unary());
      } else if (_eat('/')) {
        node = _Binary('/', node, _unary());
      } else {
        return node;
      }
    }
  }

  _Node _unary() {
    if (_eat('-')) return _Unary(_unary());
    if (_eat('+')) return _unary();
    return _power();
  }

  _Node _power() {
    final base = _atom();
    if (_eat('^')) {
      // Right associative; allow unary minus in exponent.
      return _Binary('^', base, _unary());
    }
    return base;
  }

  _Node _atom() {
    _skipWs();
    if (pos >= src.length) {
      throw ExpressionException('Unexpected end of "$src"');
    }
    final ch = src[pos];
    if (ch == '(') {
      pos++;
      final node = _expr();
      if (!_eat(')')) throw ExpressionException('Missing ")" in "$src"');
      return node;
    }
    if (_isDigit(ch) || ch == '.') return _number();
    if (_isIdentStart(ch)) {
      final start = pos;
      while (pos < src.length && _isIdentPart(src[pos])) {
        pos++;
      }
      final name = src.substring(start, pos);
      if (_eat('(')) {
        final args = <_Node>[];
        if (!_eat(')')) {
          do {
            args.add(_expr());
          } while (_eat(','));
          if (!_eat(')')) throw ExpressionException('Missing ")" after $name args');
        }
        return _Call(name, args);
      }
      return _Var(name);
    }
    throw ExpressionException('Unexpected "$ch" in "$src"');
  }

  _Node _number() {
    final start = pos;
    while (pos < src.length && (_isDigit(src[pos]) || src[pos] == '.')) {
      pos++;
    }
    if (pos < src.length && (src[pos] == 'e' || src[pos] == 'E')) {
      final save = pos;
      pos++;
      if (pos < src.length && (src[pos] == '+' || src[pos] == '-')) pos++;
      if (pos < src.length && _isDigit(src[pos])) {
        while (pos < src.length && _isDigit(src[pos])) {
          pos++;
        }
      } else {
        pos = save;
      }
    }
    final text = src.substring(start, pos);
    final v = double.tryParse(text);
    if (v == null) throw ExpressionException('Bad number "$text"');
    return _Num(v);
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  static bool _isIdentStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_';
  }

  static bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);
}
