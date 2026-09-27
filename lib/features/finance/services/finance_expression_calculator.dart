/// Errors produced while parsing a finance amount expression.
class FinanceExpressionException implements Exception {
  final String message;

  const FinanceExpressionException(this.message);

  @override
  String toString() => message;
}

/// An exact result produced by the finance expression calculator.
///
/// Values are kept as a reduced fraction until they are rounded to cents.
/// This prevents binary floating point errors from changing a money result or
/// turning an exact zero denominator into a tiny non-zero value.
class FinanceExpressionValue {
  const FinanceExpressionValue._(this._numerator, this._denominator);

  final BigInt _numerator;
  final BigInt _denominator;

  bool get isZero => _numerator == BigInt.zero;

  /// True when the exact result is less than zero.
  bool get isNegative => _numerator.isNegative;

  /// Rounds the exact result to the nearest cent, half away from zero.
  BigInt get roundedCents => _roundFraction(_numerator * _cents, _denominator);

  @override
  String toString() => FinanceExpressionCalculator.formatResult(this);
}

/// Evaluates the small expression language used by the finance amount editor.
///
/// The calculator deliberately accepts only numbers, parentheses, and the
/// four basic operators. It keeps operator precedence and supports unary plus
/// and minus so an expression can be edited naturally from the custom keypad.
class FinanceExpressionCalculator {
  const FinanceExpressionCalculator._();

  static FinanceExpressionValue evaluate(String expression) {
    final parser = _FinanceExpressionParser(expression);
    final value = parser.parse();
    return FinanceExpressionValue._(value.numerator, value.denominator);
  }

  /// Rounds a result to the precision accepted by [parseFinanceAmount].
  static BigInt roundToCents(FinanceExpressionValue value) {
    return value.roundedCents;
  }

  /// Formats a result without a currency symbol and without unnecessary zeroes.
  static String formatResult(FinanceExpressionValue value) {
    return _formatCents(value.roundedCents);
  }
}

final BigInt _cents = BigInt.from(100);

class _ExactFraction {
  _ExactFraction._(this.numerator, this.denominator);

  factory _ExactFraction(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw const FinanceExpressionException('不能除以 0');
    }
    if (numerator == BigInt.zero) {
      return _ExactFraction._(BigInt.zero, BigInt.one);
    }

    if (denominator.isNegative) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final divisor = _greatestCommonDivisor(numerator, denominator);
    return _ExactFraction._(numerator ~/ divisor, denominator ~/ divisor);
  }

  factory _ExactFraction.fromDecimal(String literal) {
    final parts = literal.split('.');
    final whole = parts.first.isEmpty ? '0' : parts.first;
    final fraction = parts.length == 1 ? '' : parts[1];
    final digits = '$whole$fraction';
    final numerator = BigInt.parse(digits);
    final denominator = BigInt.from(10).pow(fraction.length);
    return _ExactFraction(numerator, denominator);
  }

  final BigInt numerator;
  final BigInt denominator;

  bool get isZero => numerator == BigInt.zero;

  _ExactFraction operator +(_ExactFraction other) {
    return _ExactFraction(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator,
    );
  }

  _ExactFraction operator -(_ExactFraction other) {
    return _ExactFraction(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator,
    );
  }

  _ExactFraction operator *(_ExactFraction other) {
    return _ExactFraction(
      numerator * other.numerator,
      denominator * other.denominator,
    );
  }

  _ExactFraction operator /(_ExactFraction other) {
    if (other.isZero) {
      throw const FinanceExpressionException('不能除以 0');
    }
    return _ExactFraction(
      numerator * other.denominator,
      denominator * other.numerator,
    );
  }
}

BigInt _greatestCommonDivisor(BigInt left, BigInt right) {
  var a = left.abs();
  var b = right.abs();
  while (b != BigInt.zero) {
    final remainder = a.remainder(b);
    a = b;
    b = remainder;
  }
  return a;
}

BigInt _roundFraction(BigInt numerator, BigInt denominator) {
  final quotient = numerator ~/ denominator;
  final remainder = numerator.remainder(denominator);
  if (remainder.abs() * BigInt.two < denominator) return quotient;
  return quotient + (numerator.isNegative ? -BigInt.one : BigInt.one);
}

String _formatCents(BigInt cents) {
  final isNegative = cents.isNegative;
  final absolute = cents.abs();
  final whole = absolute ~/ _cents;
  final fraction = (absolute % _cents).toString().padLeft(2, '0');
  if (fraction == '00') {
    return isNegative && absolute != BigInt.zero ? '-$whole' : '$whole';
  }
  final trimmedFraction = fraction.endsWith('0')
      ? fraction.substring(0, fraction.length - 1)
      : fraction;
  final result = '$whole.$trimmedFraction';
  return isNegative ? '-$result' : result;
}

class _FinanceExpressionParser {
  _FinanceExpressionParser(String source)
      : _source = source
            .replaceAll('×', '*')
            .replaceAll('÷', '/')
            .replaceAll('−', '-')
            .replaceAll(',', '');

  final String _source;
  var _index = 0;

  _ExactFraction parse() {
    _skipWhitespace();
    if (_index >= _source.length) {
      throw const FinanceExpressionException('请输入计算式');
    }

    final value = _parseAddSubtract();
    _skipWhitespace();
    if (_index != _source.length) {
      throw FinanceExpressionException(
        '请检查“${_source.substring(_index, _index + 1)}”附近的运算符',
      );
    }
    return value;
  }

  _ExactFraction _parseAddSubtract() {
    var value = _parseMultiplyDivide();
    while (true) {
      _skipWhitespace();
      if (_match('+')) {
        value += _parseMultiplyDivide();
      } else if (_match('-')) {
        value -= _parseMultiplyDivide();
      } else {
        return value;
      }
    }
  }

  _ExactFraction _parseMultiplyDivide() {
    var value = _parseUnary();
    while (true) {
      _skipWhitespace();
      if (_match('*')) {
        value *= _parseUnary();
      } else if (_match('/')) {
        final divisor = _parseUnary();
        if (divisor.isZero) {
          throw const FinanceExpressionException('不能除以 0');
        }
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  _ExactFraction _parseUnary() {
    _skipWhitespace();
    if (_match('+')) return _parseUnary();
    if (_match('-')) {
      final value = _parseUnary();
      return _ExactFraction(-value.numerator, value.denominator);
    }
    return _parsePrimary();
  }

  _ExactFraction _parsePrimary() {
    _skipWhitespace();
    if (_match('(')) {
      _skipWhitespace();
      if (_peek(')')) {
        throw const FinanceExpressionException('括号内需要填写计算式');
      }
      final value = _parseAddSubtract();
      _skipWhitespace();
      if (!_match(')')) {
        throw const FinanceExpressionException('缺少右括号 “)”');
      }
      return value;
    }
    return _parseNumber();
  }

  _ExactFraction _parseNumber() {
    _skipWhitespace();
    final start = _index;
    var digitCount = 0;
    while (_index < _source.length && _isDigit(_source.codeUnitAt(_index))) {
      _index++;
      digitCount++;
    }
    if (_index < _source.length && _source[_index] == '.') {
      _index++;
      while (_index < _source.length && _isDigit(_source.codeUnitAt(_index))) {
        _index++;
        digitCount++;
      }
    }
    if (digitCount == 0) {
      final near = _index < _source.length ? '“${_source[_index]}”' : '末尾';
      throw FinanceExpressionException('这里需要填写数字（$near）');
    }

    return _ExactFraction.fromDecimal(_source.substring(start, _index));
  }

  bool _match(String value) {
    if (_peek(value)) {
      _index += value.length;
      return true;
    }
    return false;
  }

  bool _peek(String value) {
    return _source.startsWith(value, _index);
  }

  void _skipWhitespace() {
    while (_index < _source.length && _source[_index].trim().isEmpty) {
      _index++;
    }
  }

  bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;
}
