/// A minimal Dart lexer for the source-text rules (R13, R15).
///
/// A regex over raw source cannot tell code from text: `// ignore:` inside a
/// string literal, or `class IFoo` inside a code-generator template, would
/// both be reported. This walks the source once, tracking string literals
/// (single, double, triple-quoted, raw, and `${…}` interpolation nested to
/// any depth) and comments (line, and nestable block comments), and returns:
///
///   * [code] — the source with every comment and every string literal's
///     text replaced by spaces. Newlines are kept, so an offset into [code]
///     has the same line number as in the original. Interpolated expressions
///     stay: they are code.
///   * [lineComments] — each `//` comment (doc comments included) with its
///     1-based line and its text from the `//` onwards.
///
/// Not a parser: it never fails. A string left open at the end of a line
/// (only triple-quoted strings may span lines) is closed there, so one
/// malformed literal cannot swallow the rest of the file.
class DartSource {
  DartSource._(this.code, this.lineComments);

  factory DartSource.scan(String source) => _Scanner(source).run();

  final String code;
  final List<LineComment> lineComments;

  /// 1-based line of [offset] in [code] (equal to the original's).
  int lineOf(int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < code.length; i++) {
      if (code.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }
}

class LineComment {
  LineComment(this.line, this.text);

  final int line;

  /// From the leading `//` to the end of the line, untrimmed on the left.
  final String text;
}

/// One open string literal.
class _StringFrame {
  _StringFrame(this.quote, {required this.triple, required this.raw});

  final String quote;
  final bool triple;
  final bool raw;
}

class _Scanner {
  _Scanner(this.src);

  final String src;
  final StringBuffer _out = StringBuffer();
  final List<LineComment> _comments = [];
  var _line = 1;
  var _i = 0;

  DartSource run() {
    _code(interpolation: false);
    return DartSource._(_out.toString(), _comments);
  }

  bool _at(String s) => src.startsWith(s, _i);

  /// Emits the current character as-is and advances.
  void _keep() {
    final c = src[_i];
    if (c == '\n') _line++;
    _out.write(c);
    _i++;
  }

  /// Emits a blank for the current character (a newline stays a newline).
  void _blank() {
    final c = src[_i];
    if (c == '\n') {
      _line++;
      _out.write('\n');
    } else {
      _out.write(' ');
    }
    _i++;
  }

  static final _identChar = RegExp(r'[A-Za-z0-9_$]');

  static bool _isIdentChar(String c) => _identChar.hasMatch(c);

  /// Scans code until the end of input or, inside `${…}`, the closing brace
  /// (which is consumed and kept).
  void _code({required bool interpolation}) {
    var depth = 0;
    while (_i < src.length) {
      final c = src[_i];
      if (_at('//')) {
        _lineComment();
      } else if (_at('/*')) {
        _blockComment();
      } else if (c == "'" || c == '"') {
        final raw =
            _i > 0 &&
            src[_i - 1] == 'r' &&
            (_i < 2 || !_isIdentChar(src[_i - 2]));
        _string(raw: raw);
      } else if (c == '{') {
        depth++;
        _keep();
      } else if (c == '}') {
        if (interpolation && depth == 0) {
          _keep();
          return;
        }
        depth--;
        _keep();
      } else {
        _keep();
      }
    }
  }

  void _lineComment() {
    final end = src.indexOf('\n', _i);
    final stop = end == -1 ? src.length : end;
    _comments.add(LineComment(_line, src.substring(_i, stop)));
    while (_i < stop) {
      _blank();
    }
  }

  void _blockComment() {
    var depth = 0;
    while (_i < src.length) {
      if (_at('/*')) {
        depth++;
        _blank();
        _blank();
      } else if (_at('*/')) {
        depth--;
        _blank();
        _blank();
        if (depth == 0) return;
      } else {
        _blank();
      }
    }
  }

  void _string({required bool raw}) {
    final q = src[_i];
    final triple = _at(q * 3);
    final frame = _StringFrame(q, triple: triple, raw: raw);
    for (var k = 0; k < (triple ? 3 : 1); k++) {
      _blank();
    }
    while (_i < src.length) {
      final c = src[_i];
      if (!frame.raw && c == r'\') {
        _blank();
        if (_i < src.length) _blank();
      } else if (!frame.raw && _at(r'${')) {
        _blank();
        _blank();
        _code(interpolation: true);
      } else if (frame.triple && _at(frame.quote * 3)) {
        _blank();
        _blank();
        _blank();
        return;
      } else if (!frame.triple && c == frame.quote) {
        _blank();
        return;
      } else if (!frame.triple && c == '\n') {
        // Unterminated single-line literal: close it here.
        return;
      } else {
        _blank();
      }
    }
  }
}
