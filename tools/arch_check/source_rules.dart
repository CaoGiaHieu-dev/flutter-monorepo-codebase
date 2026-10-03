import 'dart_source.dart';

/// The source-text rules of `arch_check` that read hand-written Dart through
/// [DartSource] (comments and string literals already blanked): R8's throwing
/// DI lookups, R18's `on<Event>` handlers, R19's runtime diagnostics and R20's
/// raw layout numbers.
///
/// Lexical scans, not parsers — each one is deliberately generous about
/// whitespace and line breaks (a lookup split across lines is still a lookup)
/// and deliberately narrow about what it flags, so a hit is a real finding.

/// One finding in a source file: the 1-based line and what is wrong.
class SourceFinding {
  const SourceFinding(this.line, this.text);

  final int line;

  /// The matched type or token, used to build the message.
  final String text;
}

/// The index of the bracket closing the one at [open] in [code], or -1.
int matchingBracket(String code, int open) {
  const pairs = {'(': ')', '[': ']', '{': '}', '<': '>'};
  final openChar = code[open];
  final closeChar = pairs[openChar]!;
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == openChar) {
      depth++;
    } else if (c == closeChar) {
      // `=>` is not an angle bracket.
      if (closeChar == '>' && i > 0 && code[i - 1] == '=') continue;
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// One top-level argument of a call: its text and the offset where its first
/// character (not its leading whitespace) sits.
class _Argument {
  _Argument(this.text, int begin)
    : start = begin + (text.length - text.trimLeft().length);

  final String text;
  final int start;
}

/// The top-level arguments between the parenthesis at [open] and its match.
List<_Argument> _argumentsOf(String code, int open) {
  final close = matchingBracket(code, open);
  if (close == -1) return const [];
  final out = <_Argument>[];
  var depth = 0;
  var begin = open + 1;
  for (var i = open + 1; i < close; i++) {
    final c = code[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 0) {
      out.add(_Argument(code.substring(begin, i), begin));
      begin = i + 1;
    }
  }
  if (code.substring(begin, close).trim().isNotEmpty) {
    out.add(_Argument(code.substring(begin, close), begin));
  }
  return out;
}

// ---------------------------------------------------------------------------
// R8 — throwing DI lookups
// ---------------------------------------------------------------------------

/// The ways to name the service locator: the shared `getIt` global and the
/// `GetIt.I` / `GetIt.instance` singleton, optionally through `.get`, `.call`,
/// `.getAsync` or `.getAll`. `getAll<T>` stands alone as well — the lookup
/// extension `getAllOrEmpty` is its safe counterpart.
///
/// `getItOrNull<T>` and `getAllOrEmpty<T>` never match: after `getIt` the
/// pattern wants `<` (or one of the listed members), and those two continue
/// with more identifier characters.
final RegExp _throwingLookup = RegExp(
  r'(?:\b(?:getIt|GetIt\s*\.\s*(?:I|instance))'
  r'(?:\s*\.\s*(?:get|getAll|getAsync|call))?|\bgetAll)'
  r'\s*<\s*(?:\w+\s*\.\s*)?([A-Z]\w*)',
);

/// A typed declaration initialised by an untyped lookup —
/// `final IFoo foo = getIt();`, `IFoo foo = getIt.get();` — where the type
/// argument is inferred from the declared type. Group 1 is that type.
final RegExp _untypedLookup = RegExp(
  r'\b([A-Z]\w*)(?:\s*<[^;=()]*>)?\??\s+[a-z_]\w*\s*=\s*'
  r'(?:getIt|GetIt\s*\.\s*(?:I|instance))'
  r'(?:\s*\.\s*(?:get|getAsync|call))?\s*\(',
);

/// Every throwing lookup in [scanned], by the type it asks for: the generic
/// spellings (`getIt<T>()`, `getIt.get<T>()`, `getIt.getAll<T>()`,
/// `GetIt.I<T>()`, `GetIt.instance<T>()`, a type argument on the next line)
/// and an untyped `getIt()` assigned to a declared type.
List<SourceFinding> throwingLookupsIn(DartSource scanned) => [
  for (final m in _throwingLookup.allMatches(scanned.code))
    SourceFinding(scanned.lineOf(m.start), m.group(1)!),
  for (final m in _untypedLookup.allMatches(scanned.code))
    SourceFinding(scanned.lineOf(m.start), m.group(1)!),
];

/// A constructor parameter that DI must supply, whose type is [type].
class InjectedParameter {
  const InjectedParameter(this.type, this.line);

  final String type;
  final int line;
}

/// The registering annotations of injectable that build a class through its
/// constructor.
final RegExp _injectableClass = RegExp(
  r'@\s*(?:Injectable|injectable|LazySingleton|lazySingleton|Singleton|'
  r'singleton)\b(?:\s*\([^)]*\))?\s*'
  r'(?:@[\w.]+(?:\s*\([^)]*\))?\s*)*'
  r'(?:(?:abstract|base|final|interface)\s+)*class\s+([A-Z]\w*)',
);

/// The parameters injectable resolves from the container for every
/// `@injectable` / `@lazySingleton` / `@singleton` class in [scanned]: a
/// constructor parameter that is neither nullable nor `@factoryParam` is
/// resolved with a throwing `get`, whatever its spelling.
///
/// Reads the default constructor and a named one marked `@factoryMethod`;
/// `this.x` parameters take the type of the field `x` declared in the class.
/// Anything it cannot place is left out — the scan prefers a miss to a false
/// alarm.
List<InjectedParameter> injectedParametersIn(DartSource scanned) {
  final code = scanned.code;
  final out = <InjectedParameter>[];
  for (final head in _injectableClass.allMatches(code)) {
    final name = head.group(1)!;
    final bodyOpen = code.indexOf('{', head.end);
    if (bodyOpen == -1) continue;
    final bodyClose = matchingBracket(code, bodyOpen);
    if (bodyClose == -1) continue;
    final body = code.substring(bodyOpen, bodyClose + 1);

    for (final ctor in RegExp(
      '(?:@\\s*(?:factoryMethod|FactoryMethod)\\b(?:\\s*\\([^)]*\\))?\\s*)?'
      '(?:const\\s+|factory\\s+)?$name(?:\\s*\\.\\s*\\w+)?\\s*\\(',
    ).allMatches(body)) {
      final named = ctor.group(0)!.contains(RegExp('$name\\s*\\.'));
      final marked = ctor.group(0)!.startsWith('@');
      if (named && !marked) continue; // a plain named constructor: not DI's
      // A call such as `Foo(` inside a method body also matches: only a
      // declaration — at class-body depth — is a constructor.
      if (_depthAt(body, ctor.start) != 1) continue;
      final open = ctor.end - 1;
      for (final arg in _argumentsOf(body, open)) {
        final parameter = _injectedType(arg.text, body);
        if (parameter == null) continue;
        out.add(
          InjectedParameter(parameter, scanned.lineOf(bodyOpen + arg.start)),
        );
      }
    }
  }
  return out;
}

/// The brace depth of [offset] in [text] (the class body's own is 1).
int _depthAt(String text, int offset) {
  var depth = 0;
  for (var i = 0; i < offset; i++) {
    if (text[i] == '{') depth++;
    if (text[i] == '}') depth--;
  }
  return depth;
}

/// The type DI must resolve for one constructor parameter, or null when the
/// parameter is nullable, a `@factoryParam`, has a default or cannot be read.
String? _injectedType(String rawParameter, String classBody) {
  var p = rawParameter.trim();
  if (p.isEmpty) return null;
  if (p.startsWith('@factoryParam') || p.contains('@factoryParam')) return null;
  // Optional / named brackets around the whole list arrive as part of the
  // first and last argument.
  p = p.replaceAll(RegExp(r'^[\[{]|[\]}]$'), '').trim();
  p = p.replaceAll(RegExp(r'@\s*[\w.]+(?:\s*\([^)]*\))?\s*'), '').trim();
  p = p.replaceAll(RegExp(r'\b(?:required|covariant|final)\s+'), '').trim();
  if (p.contains('=')) return null; // a default value: not required
  final field = RegExp(r'^this\s*\.\s*(\w+)$').firstMatch(p);
  if (field != null) {
    final decl = RegExp(
      '(?:final|late\\s+final|var)\\s+([A-Z]\\w*)(?:\\s*<[^;=]*>)?(\\??)\\s+'
      '${field.group(1)}\\s*[;=]',
    ).firstMatch(classBody);
    if (decl == null || decl.group(2) == '?') return null;
    return decl.group(1);
  }
  final typed = RegExp(r'^([A-Z]\w*)(?:\s*<[^]*>)?(\??)\s+[a-z_]\w*$')
      .firstMatch(p);
  if (typed == null || typed.group(2) == '?') return null;
  return typed.group(1);
}

// ---------------------------------------------------------------------------
// R18 — Bloc event handlers are async
// ---------------------------------------------------------------------------

/// `on<Event>(` — a handler registration. A leading `.` (a method of some
/// other object) is not one, and `\b` keeps `extension<` and `on Type` out.
final RegExp _onRegistration = RegExp(r'(?<![\w.$])on\s*<');

/// Every `on<...>(handler)` in [scanned] whose handler is not `async`, with
/// what is wrong with it.
///
/// Two shapes: an inline closure (`(event, emit) { ... }` / `=> ...`) must be
/// followed by `async`; a method tear-off (`_onLoad`, `this._onLoad`) must
/// resolve — in the same file — to a method returning `Future<void>` and
/// declared `async`. A handler declared elsewhere (a `part` file, a mixin)
/// cannot be placed and is left alone.
List<SourceFinding> blocHandlerProblemsIn(DartSource scanned) {
  final code = scanned.code;
  final out = <SourceFinding>[];
  for (final m in _onRegistration.allMatches(code)) {
    final angleOpen = code.indexOf('<', m.start);
    final angleClose = matchingBracket(code, angleOpen);
    if (angleClose == -1) continue;
    var open = angleClose + 1;
    while (open < code.length && code[open].trim().isEmpty) {
      open++;
    }
    if (open >= code.length || code[open] != '(') continue;
    final args = _argumentsOf(code, open);
    if (args.isEmpty) continue;
    final handler = args.first.text.trim();
    final line = scanned.lineOf(m.start);

    if (handler.startsWith('(')) {
      final paramsOpen = open + 1 + args.first.text.indexOf('(');
      final paramsClose = matchingBracket(code, paramsOpen);
      if (paramsClose == -1) continue;
      final after = code.substring(paramsClose + 1);
      if (RegExp(r'^\s*async\b').hasMatch(after)) continue;
      out.add(SourceFinding(line, 'a closure that is not `async`'));
      continue;
    }

    final tearOff = RegExp(
      r'^(?:this\s*\.\s*)?([A-Za-z_]\w*)$',
    ).firstMatch(handler);
    if (tearOff == null) continue;
    final name = tearOff.group(1)!;
    final declaration = _methodDeclaration(code, name);
    if (declaration == null) continue;
    final returns = declaration.returnType.replaceAll(RegExp(r'\s+'), '');
    final asyncBody = RegExp(
      r'^\s*async\b',
    ).hasMatch(code.substring(declaration.paramsEnd + 1));
    if (returns.endsWith('Future<void>') && asyncBody) continue;
    out.add(
      SourceFinding(
        line,
        asyncBody
            ? '`$name` returns `$returns`, not `Future<void>`'
            : '`$name` is not declared `async`',
      ),
    );
  }
  return out;
}

/// A method declared in the file: its return type and where its parameter
/// list ends.
class _MethodDeclaration {
  const _MethodDeclaration(this.returnType, this.paramsEnd);

  final String returnType;
  final int paramsEnd;
}

/// Words that start a statement rather than naming a return type.
const _statementKeywords = {
  'return',
  'await',
  'else',
  'throw',
  'yield',
  'new',
  'case',
};

/// The declaration of method [name] in [code], or null when the file has none
/// (the handler is inherited, or lives in a `part` file). A hit is a
/// declaration when what stands between the previous `;`, `{` or `}` and the
/// name is a return type — a plain run of type characters, annotations aside
/// — rather than a statement.
_MethodDeclaration? _methodDeclaration(String code, String name) {
  for (final m in RegExp('\\b$name\\s*\\(').allMatches(code)) {
    var from = m.start;
    while (from > 0 && !';{}'.contains(code[from - 1])) {
      from--;
    }
    final head = code
        .substring(from, m.start)
        .replaceAll(RegExp(r'@\s*[\w.]+(?:\s*\([^)]*\))?'), '')
        .trim();
    if (head.isEmpty || !RegExp(r'^[\w<>?,\s]+$').hasMatch(head)) continue;
    if (_statementKeywords.contains(head.split(RegExp(r'\s+')).first)) continue;
    final open = m.end - 1;
    final close = matchingBracket(code, open);
    if (close == -1) return null;
    return _MethodDeclaration(head, close);
  }
  return null;
}

// ---------------------------------------------------------------------------
// R19 — runtime diagnostics go through DynamicLogger
// ---------------------------------------------------------------------------

final RegExp _diagnosticCall = RegExp(
  r'(?<![\w.$])(debugPrintStack|debugPrint|print)\s*\(',
);

/// Words that may precede a call without making it a declaration.
const _statementWords = {
  'return',
  'else',
  'do',
  'await',
  'throw',
  'yield',
  'case',
  'in',
};

/// Calls to `print` / `debugPrint` / `debugPrintStack` in [scanned]. A method
/// *declared* with one of those names (`void print(...)`) is not a call.
List<SourceFinding> diagnosticCallsIn(DartSource scanned) {
  final code = scanned.code;
  final out = <SourceFinding>[];
  for (final m in _diagnosticCall.allMatches(code)) {
    final before = code.substring(0, m.start).trimRight();
    final word = RegExp(r'([A-Za-z_$][\w$]*)$').firstMatch(before)?.group(1);
    if (word != null && !_statementWords.contains(word)) continue;
    out.add(SourceFinding(scanned.lineOf(m.start), m.group(1)!));
  }
  return out;
}

// ---------------------------------------------------------------------------
// R20 — no raw numeric literals for layout and paint
// ---------------------------------------------------------------------------

/// A value that starts with a number: `16`, `-4`, `.5`, `0.75`. A literal
/// wrapped in a call (`context.w(16)`) or a constant (`AppSpacing.md`) does
/// not start with one.
final RegExp _startsWithNumber = RegExp(r'^[-+]?\s*(?:\d|\.\d)');

/// A zero carries no magnitude to scale: `0`, `0.0`.
final RegExp _isZero = RegExp(r'^[-+]?\s*0(?:\.0+)?\s*$');

bool _isRawNumber(String value) {
  final v = value.trim();
  return _startsWithNumber.hasMatch(v) && !_isZero.hasMatch(v);
}

/// What follows `name:` in a named argument, or the whole text when positional.
String _valueOf(String argument, {String? only}) {
  final m = RegExp(r'^\s*(\w+)\s*:(.*)$', dotAll: true).firstMatch(argument);
  if (m == null) return only == null ? argument : '';
  if (only != null && m.group(1) != only) return '';
  return m.group(2)!;
}

/// Constructors whose every positional or named numeric argument is a layout
/// or paint magnitude.
final RegExp _numericConstructor = RegExp(
  r'\b(EdgeInsets(?:Directional)?\s*\.\s*(?:all|symmetric|only|fromLTRB|fromSTEB)'
  r'|BorderRadius\s*\.\s*circular|Radius\s*\.\s*circular|Offset)\s*\(',
);

/// `SizedBox(width: 8)` and friends: only the sized arguments count.
final RegExp _sizedBox = RegExp(
  r'\bSizedBox\s*(?:\.\s*(?:square|fromSize))?\s*\(',
);

/// A named argument whose value is a magnitude wherever it is written.
final RegExp _numericNamed = RegExp(
  r'(?<![\w.$])(fontSize|blurRadius|strokeWidth)\s*:\s*([-+]?\s*(?:\d|\.\d)[\w.]*)',
);

/// Raw layout and paint numbers in [scanned]: a number literal where a value
/// comes from `BuildContext` (`context.w/h/sp/r`) or a design token.
List<SourceFinding> rawLayoutNumbersIn(DartSource scanned) {
  final code = scanned.code;
  final out = <SourceFinding>[];

  for (final m in _numericConstructor.allMatches(code)) {
    final name = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
    for (final arg in _argumentsOf(code, m.end - 1)) {
      if (!_isRawNumber(_valueOf(arg.text))) continue;
      out.add(SourceFinding(scanned.lineOf(arg.start), name));
    }
  }

  for (final m in _sizedBox.allMatches(code)) {
    for (final arg in _argumentsOf(code, m.end - 1)) {
      final width = _valueOf(arg.text, only: 'width');
      final height = _valueOf(arg.text, only: 'height');
      final dimension = _valueOf(arg.text, only: 'dimension');
      if (_isRawNumber(width) ||
          _isRawNumber(height) ||
          _isRawNumber(dimension)) {
        out.add(SourceFinding(scanned.lineOf(arg.start), 'SizedBox'));
      }
    }
  }

  for (final m in _numericNamed.allMatches(code)) {
    if (_isZero.hasMatch(m.group(2)!.trim())) continue;
    out.add(SourceFinding(scanned.lineOf(m.start), '${m.group(1)}:'));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Which files
// ---------------------------------------------------------------------------

/// Whether [rel] (repo-relative, POSIX) is hand-written Dart in a package's
/// `lib/` under `platform/` or `modules/` — where R19 and R20 apply. Test
/// code is a different `lib`-less folder; tools have their own output rule.
bool isProductLib(String rel) {
  if (!rel.endsWith('.dart')) return false;
  final segments = rel.split('/');
  if (segments.length < 3) return false;
  if (segments.first != 'platform' && segments.first != 'modules') {
    return false;
  }
  return segments.contains('lib');
}

/// Whether [rel] lives under a `styles/` or `utils/` folder, where constants
/// (design tokens, raw values) are meant to be declared.
bool isConstantsHome(String rel) {
  final segments = rel.split('/');
  return segments.contains('styles') || segments.contains('utils');
}
