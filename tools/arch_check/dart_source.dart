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
///   * [directives] — every `import` / `export` / `part` directive, with each
///     URI it names: the first one and every `if (...) 'uri'` configuration
///     (a conditional import names a package only in the configuration).
///     Found in the blanked [code], so a directive-looking line inside a
///     block comment or a triple-quoted string is not one, and `import'x';`
///     and two directives on one line both count.
///
/// Not a parser: it never fails. A string left open at the end of a line
/// (only triple-quoted strings may span lines) is closed there, so one
/// malformed literal cannot swallow the rest of the file.
class DartSource {
  DartSource._(this.code, this.lineComments, this.directives);

  factory DartSource.scan(String source) => _Scanner(source).run();

  final String code;
  final List<LineComment> lineComments;

  /// Every `import` / `export` / `part` directive, in source order.
  final List<Directive> directives;

  /// Offsets at which each line of [code] starts, built on first use.
  late final List<int> _lineStarts = () {
    final starts = [0];
    for (var i = 0; i < code.length; i++) {
      if (code.codeUnitAt(i) == 0x0A) starts.add(i + 1);
    }
    return starts;
  }();

  /// 1-based line of [offset] in [code] (equal to the original's).
  int lineOf(int offset) {
    var lo = 0;
    var hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  /// The URIs of every `import` and `export` directive — conditional
  /// configurations included — with the line of the directive.
  Iterable<DirectiveUri> get importedUris sync* {
    for (final d in directives) {
      if (d.keyword == 'part') continue;
      for (final uri in d.uris) {
        yield DirectiveUri(uri, d.line);
      }
    }
  }
}

/// One `import` / `export` / `part` directive.
class Directive {
  Directive(this.keyword, this.line, this.uris);

  /// `import`, `export` or `part`.
  final String keyword;

  /// 1-based line of the keyword.
  final int line;

  /// The directive's URI, then each `if (...) 'uri'` configuration's.
  final List<String> uris;
}

/// A URI named by a directive, with the line it was written on.
class DirectiveUri {
  const DirectiveUri(this.uri, this.line);

  final String uri;
  final int line;

  /// The package of a `package:<name>/...` URI, or null.
  String? get package {
    const prefix = 'package:';
    if (!uri.startsWith(prefix)) return null;
    final slash = uri.indexOf('/');
    return slash == -1
        ? uri.substring(prefix.length)
        : uri.substring(prefix.length, slash);
  }

  /// The library of a `dart:<name>` URI (`ui` for `dart:ui`), or null.
  String? get dartLibrary =>
      uri.startsWith('dart:') ? uri.substring('dart:'.length) : null;
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

  /// Every string literal that has no interpolation, by the offset of its
  /// opening quote: where it ends and what is between the quotes.
  final Map<int, ({int end, String value})> _strings = {};
  var _line = 1;
  var _i = 0;

  DartSource run() {
    _code(interpolation: false);
    final code = _out.toString();
    return DartSource._(code, _comments, _directives(code));
  }

  /// Every directive in [code] (comments and strings blanked), its URIs read
  /// back from [_strings].
  List<Directive> _directives(String code) {
    final out = <Directive>[];
    final starts = <int>[0];
    for (var i = 0; i < code.length; i++) {
      if (code.codeUnitAt(i) == 0x0A) starts.add(i + 1);
    }
    int lineAt(int offset) {
      var lo = 0;
      var hi = starts.length - 1;
      while (lo < hi) {
        final mid = (lo + hi + 1) >> 1;
        if (starts[mid] <= offset) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      return lo + 1;
    }

    for (final m in _directiveKeyword.allMatches(code)) {
      // A directive starts a statement: the file, or after `;` / `}`.
      var before = m.start - 1;
      while (before >= 0 && _isBlank(code.codeUnitAt(before))) {
        before--;
      }
      if (before >= 0 && code[before] != ';' && code[before] != '}') continue;

      final first = _stringAfter(code, m.end);
      if (first == null) continue; // `part of x;`, `import` as an identifier
      final uris = [_strings[first]!.value];
      final stop = code.indexOf(';', _strings[first]!.end);
      final tail = code.substring(
        _strings[first]!.end,
        stop == -1 ? code.length : stop,
      );
      for (final cond in _configuration.allMatches(tail)) {
        final open = _strings[first]!.end + cond.end - 1;
        final close = _closingParen(code, open);
        if (close == -1) continue;
        final uri = _stringAfter(code, close + 1);
        if (uri != null) uris.add(_strings[uri]!.value);
      }
      out.add(Directive(m.group(1)!, lineAt(m.start), uris));
    }
    return out;
  }

  static final RegExp _directiveKeyword = RegExp(
    r'(?<![\w.$])(import|export|part)(?![\w$])',
  );

  /// `if (` of a conditional configuration; the match ends after the `(`.
  static final RegExp _configuration = RegExp(r'(?<![\w$])if\s*\(');

  static bool _isBlank(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

  /// The offset of the string literal that starts after [from], skipping only
  /// blanks (which is what comments and the quotes of strings become), or null
  /// when something else comes first.
  int? _stringAfter(String code, int from) {
    for (var k = from; k < code.length; k++) {
      if (_strings.containsKey(k)) return k;
      if (!_isBlank(code.codeUnitAt(k))) return null;
    }
    return null;
  }

  static int _closingParen(String code, int open) {
    var depth = 0;
    for (var i = open; i < code.length; i++) {
      if (code[i] == '(') depth++;
      if (code[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
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
    final begin = _i;
    final quoteLength = triple ? 3 : 1;
    var interpolated = false;
    for (var k = 0; k < quoteLength; k++) {
      _blank();
    }
    void record({required bool closed}) {
      if (interpolated) return;
      final end = _i;
      final contentEnd = closed ? end - quoteLength : end;
      if (contentEnd < begin + quoteLength) return;
      _strings[begin] = (
        end: end,
        value: src.substring(begin + quoteLength, contentEnd),
      );
    }

    while (_i < src.length) {
      final c = src[_i];
      if (!frame.raw && c == r'\') {
        _blank();
        if (_i < src.length) _blank();
      } else if (!frame.raw && _at(r'${')) {
        interpolated = true;
        _blank();
        _blank();
        _code(interpolation: true);
      } else if (frame.triple && _at(frame.quote * 3)) {
        _blank();
        _blank();
        _blank();
        record(closed: true);
        return;
      } else if (!frame.triple && c == frame.quote) {
        _blank();
        record(closed: true);
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
