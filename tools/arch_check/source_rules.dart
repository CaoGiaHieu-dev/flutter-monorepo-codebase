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
// R7 — responsive sizing goes through BuildContext
// ---------------------------------------------------------------------------

/// The sizing extension names `core_responsive` once offered on `num`.
const _sizingNames = r'spMin|sp|dg|dm|w|h|r';

/// A number literal followed by a sizing extension: `16.w`, `1.5.h`,
/// `16\n    .w` (the receiver and the dot on different lines). The receiver may
/// not continue an identifier (`a2.w`) or a member chain (`x.5.w`).
final RegExp _numberReceiver = RegExp(
  r'(?<![\w.$])(?:\d[\d_]*(?:\.\d[\d_]*)?|\.\d[\d_]*)\s*\.\s*(' +
      _sizingNames +
      r')\b(?!\s*\()',
);

/// `)` followed by a sizing extension; whether it is a sum or a call is decided
/// by [_isArithmeticGroup].
final RegExp _parenReceiver = RegExp(
  r'\)\s*\.\s*(' + _sizingNames + r')\b(?!\s*\()',
);

/// Words after which a `(` is a grouping parenthesis, not a call.
const _beforeGroup = {
  'return',
  'await',
  'in',
  'else',
  'case',
  'yield',
  'throw',
  'is',
  'as',
  'assert',
};

/// Whether the `)` at [close] closes a parenthesised arithmetic expression —
/// `(4 + 4)`, `(spacing * 2)` — and not the argument list of a call
/// (`Color.fromARGB(255, 0, 0, 0).r`, `c.withValues(alpha: .5).r`,
/// `Size(1, 2).h`), where `.r` / `.h` are members of the result and nothing
/// to do with sizing. Needs an arithmetic operator inside and nothing that
/// makes it a Dart expression of another kind (`?`, `:`, `,`, `=`, `<`).
bool _isArithmeticGroup(String code, int close) {
  var depth = 0;
  var open = -1;
  for (var i = close; i >= 0; i--) {
    final c = code[i];
    if (c == ')') depth++;
    if (c == '(') {
      depth--;
      if (depth == 0) {
        open = i;
        break;
      }
    }
  }
  if (open == -1) return false;
  var before = open - 1;
  while (before >= 0 && code[before].trim().isEmpty) {
    before--;
  }
  if (before >= 0 && RegExp(r'[\w$>)\]]').hasMatch(code[before])) {
    final word = RegExp(r'([A-Za-z_$][\w$]*)$')
        .firstMatch(code.substring(0, before + 1))
        ?.group(1);
    if (word == null || !_beforeGroup.contains(word)) return false; // a call
  }
  final inner = code.substring(open + 1, close);
  return RegExp(r'^[\w\s.+\-*/%~()$]+$').hasMatch(inner) &&
      RegExp(r'[+\-*/%]').hasMatch(inner);
}

/// Bare sizing extensions in [scanned]: a number literal (the receiver may sit
/// on the line above the dot) or a parenthesised sum followed by `.w`, `.h`,
/// `.r`, `.sp`, `.spMin`, `.dg` or `.dm`. Finding text is the extension name.
///
/// What it does not follow: a *variable* receiver (`final p = 8; p.w`, a
/// `Pad.md.w` constant) — without types a `.r` on an identifier may be
/// `Color.r`, which exists. The declaration check
/// ([sizingExtensionDeclarationsIn]) covers the other side: a workspace
/// extension that would make any of these compile.
List<SourceFinding> bareSizingExtensionsIn(DartSource scanned) {
  final code = scanned.code;
  return [
    for (final m in _numberReceiver.allMatches(code))
      SourceFinding(scanned.lineOf(m.start), m.group(1)!),
    for (final m in _parenReceiver.allMatches(code))
      if (_isArithmeticGroup(code, m.start))
        SourceFinding(scanned.lineOf(m.start), m.group(1)!),
  ]..sort((a, b) => a.line.compareTo(b.line));
}

/// `extension … on num | int | double { … }` — the head of an extension a bare
/// sizing getter could live in.
final RegExp _numExtension = RegExp(
  r'\bextension\b[^{;]*?\bon\s+(?:num|int|double)\b[^{;]*\{',
);

/// A member of an extension named like a sizing extension: `double get w =>`,
/// `double h(BuildContext c)`.
final RegExp _sizingMember = RegExp(
  r'(?:\bget\s+|[\w>?]\s+)(' + _sizingNames + r')\s*(?:=>|\(|\{)',
);

/// Declarations, in [scanned], of an extension on `num` / `int` / `double`
/// with a member named `w`, `h`, `r`, `sp`, `spMin`, `dg` or `dm` — what would
/// make `16.w` type-check. `core_responsive` ships none, and a workspace file
/// that declares one is reported at the declaration.
List<SourceFinding> sizingExtensionDeclarationsIn(DartSource scanned) {
  final code = scanned.code;
  final out = <SourceFinding>[];
  for (final head in _numExtension.allMatches(code)) {
    final open = head.end - 1;
    final close = matchingBracket(code, open);
    if (close == -1) continue;
    final body = code.substring(open + 1, close);
    for (final m in _sizingMember.allMatches(body)) {
      out.add(SourceFinding(scanned.lineOf(open + 1 + m.start), m.group(1)!));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// R8 — throwing DI lookups
// ---------------------------------------------------------------------------

/// Words that follow `GetIt get` as an accessor, not a name: `GetIt get sl =>
/// ...` names `sl`, never `get`.
const _notLocatorNames = {'get', 'set', 'operator'};

/// The identifiers in [code] that hold a `GetIt`: the shared `getIt` global
/// and anything declared with type `GetIt` (a field, a parameter, a local, an
/// accessor) or initialised from `GetIt.I` / `GetIt.instance` /
/// `GetIt.asNewInstance()` / `getIt`. A private field (`_getIt`), a local alias
/// (`final sl = GetIt.instance;`) and an injected `GetIt locator` parameter are
/// spelled differently from `getIt` and resolve exactly the same way.
///
/// Per file: an alias that crosses files (a `locator` inherited from a base
/// class in another file) cannot be placed.
Set<String> locatorNamesIn(String code) {
  final names = <String>{'getIt'};
  for (final m in RegExp(
    r'\bGetIt\s*\??\s+(?:get\s+)?([A-Za-z_]\w*)',
  ).allMatches(code)) {
    final name = m.group(1)!;
    if (!_notLocatorNames.contains(name)) names.add(name);
  }
  for (final m in RegExp(
    r'(?:\bfinal|\bvar|\blate(?:\s+final)?|\bconst)\s+(?:[A-Z]\w*\??\s+)?'
    r'([A-Za-z_]\w*)\s*=\s*'
    r'(?:GetIt\s*\.\s*(?:I|instance|asNewInstance\s*\(\s*\))|getIt)\b',
  ).allMatches(code)) {
    names.add(m.group(1)!);
  }
  return names;
}

/// The ways to call a locator in [names]: the name itself, or `GetIt.I` /
/// `GetIt.instance`, optionally through `.get`, `.call`, `.getAsync` or
/// `.getAll`, optionally behind `this.`. `getAll<T>` stands alone as well —
/// the lookup extension `getAllOrEmpty` is its safe counterpart.
///
/// `getItOrNull<T>` and `getAllOrEmpty<T>` never match: after `getIt` the
/// pattern wants `<` (or one of the listed members), and those two continue
/// with more identifier characters. The receiver may follow a `.`
/// (`widget.getIt<T>()`, `this._getIt.get<T>()`) but not an identifier
/// character, so `forgetIt<T>` is not `getIt<T>`.
String _receiver(Set<String> names) =>
    '(?<![\\w\$])(?:(?:${[for (final n in names) RegExp.escape(n)].join('|')})'
    r'|GetIt\s*\.\s*(?:I|instance))';

/// Every throwing lookup in [scanned], by the type it asks for: the generic
/// spellings (`getIt<T>()`, `getIt.get<T>()`, `getIt.getAll<T>()`,
/// `GetIt.I<T>()`, `GetIt.instance<T>()`, the same through any alias of a
/// `GetIt` — `_getIt`, `locator`, `sl` — and a type argument on the next line)
/// and an untyped lookup assigned to a declared type.
List<SourceFinding> throwingLookupsIn(DartSource scanned) {
  final code = scanned.code;
  final receiver = _receiver(locatorNamesIn(code));
  final throwing = RegExp(
    '(?:$receiver'
    r'(?:\s*[!?]?\s*\.\s*(?:get|getAll|getAsync|call))?|(?<![\w$])getAll)'
    // `>` then `(`: a call with a type argument, not a comparison.
    r'\s*<\s*(?:\w+\s*\.\s*)?([A-Z]\w*)(?=[\w\s<>?,.]*>\s*\()',
  );
  // A typed declaration initialised by an untyped lookup —
  // `final IFoo foo = getIt();`, `IFoo foo = getIt.get();` — where the type
  // argument is inferred from the declared type.
  final untyped = RegExp(
    r'\b([A-Z]\w*)(?:\s*<[^;=()]*>)?\??\s+[a-z_]\w*\s*=\s*'
    '$receiver'
    r'(?:\s*[!?]?\s*\.\s*(?:get|getAsync|call))?\s*\(',
  );
  return [
    for (final m in throwing.allMatches(code))
      SourceFinding(scanned.lineOf(m.start), m.group(1)!),
    for (final m in untyped.allMatches(code))
      SourceFinding(scanned.lineOf(m.start), m.group(1)!),
  ];
}

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
  r'(?<![\w.$])(EdgeInsets(?:Directional)?\s*\.\s*(?:all|symmetric|only|fromLTRB|fromSTEB)'
  r'|BorderRadius\s*\.\s*circular|Radius\s*\.\s*(?:circular|elliptical)'
  r'|Size(?:\s*\.\s*(?:square|fromWidth|fromHeight|fromRadius))?'
  r'|Rect\s*\.\s*(?:fromLTWH|fromLTRB|fromCircle|fromPoints))\s*\(',
);

/// `Offset(x, y)`: a number is a pixel distance, except a fraction of the
/// widget's own size — `Offset(0, 1)` for a `SlideTransition`, `Offset(.5, .5)`
/// — which no layout scale applies to. Only an argument whose magnitude is
/// above 1 is flagged.
final RegExp _offset = RegExp(r'(?<![\w.$])Offset\s*\(');

/// `SizedBox(width: 8)` and friends: only the sized arguments count.
final RegExp _sizedBox = RegExp(
  r'\bSizedBox\s*(?:\.\s*(?:square|fromSize))?\s*\(',
);

/// Widgets and value types whose named arguments are layout or paint
/// magnitudes, with those arguments. `Container(width: 100)`, `Icon(size: 24)`,
/// `Positioned(top: 8)`, `BorderSide(width: 1)`, `Divider(thickness: 1)`,
/// `BoxConstraints(maxWidth: 300)`.
///
/// A list of known widgets, not "any argument called `width`": a data class
/// can have a `width` field that is a pixel count from the server, and
/// `TextStyle(height: 1.2)` is a ratio, not a size.
const Map<String, Set<String>> _magnitudeArguments = {
  'Container': {'width', 'height'},
  'AnimatedContainer': {'width', 'height'},
  'BoxConstraints': {
    'minWidth',
    'maxWidth',
    'minHeight',
    'maxHeight',
    'width',
    'height',
  },
  'Icon': {'size'},
  'IconButton': {'iconSize', 'splashRadius'},
  'Positioned': {
    'left',
    'top',
    'right',
    'bottom',
    'width',
    'height',
    'start',
    'end',
  },
  'PositionedDirectional': {'start', 'top', 'end', 'bottom', 'width', 'height'},
  'BorderSide': {'width'},
  'Border': {'width'},
  'Divider': {'height', 'thickness', 'indent', 'endIndent'},
  'VerticalDivider': {'width', 'thickness', 'indent', 'endIndent'},
  'CircleAvatar': {'radius', 'minRadius', 'maxRadius'},
  'Image': {'width', 'height'},
  'SvgPicture': {'width', 'height'},
  'LinearProgressIndicator': {'minHeight'},
};

final RegExp _magnitudeWidget = RegExp(
  '(?<![\\w.\$])(${_magnitudeArguments.keys.join('|')})'
  r'(?:\s*\.\s*\w+)?\s*\(',
);

/// A named argument whose value is a magnitude wherever it is written.
final RegExp _numericNamed = RegExp(
  r'(?<![\w.$])(fontSize|blurRadius|spreadRadius|strokeWidth)\s*:\s*([-+]?\s*(?:\d|\.\d)[\w.]*)',
);

/// `paint.strokeWidth = 2;` — the same magnitude, assigned.
final RegExp _strokeWidthAssignment = RegExp(
  r'\.\s*strokeWidth\s*=(?!=)\s*([-+]?\s*(?:\d|\.\d)[\w.]*)',
);

/// The magnitude of the number a [value] starts with (`-.5` -> 0.5), or null.
double? _leadingNumber(String value) {
  final m = RegExp(r'^[-+]?\s*(\d+(?:\.\d+)?|\.\d+)').firstMatch(value.trim());
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// Raw layout and paint numbers in [scanned]: a number literal where a value
/// comes from `BuildContext` (`context.w/h/sp/r`) or a design token.
///
/// Partial by design — a lexical scan over the constructors and arguments
/// listed here, not a type check: an identifier that holds a raw `double`
/// (`final w = 100.0; Container(width: w)`) is not followed. What it names is
/// what a review would flag first.
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

  for (final m in _offset.allMatches(code)) {
    for (final arg in _argumentsOf(code, m.end - 1)) {
      final value = _valueOf(arg.text);
      if (!_isRawNumber(value)) continue;
      final magnitude = _leadingNumber(value);
      if (magnitude != null && magnitude <= 1) continue; // a fraction
      out.add(SourceFinding(scanned.lineOf(arg.start), 'Offset'));
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

  for (final m in _magnitudeWidget.allMatches(code)) {
    final widget = m.group(1)!;
    final names = _magnitudeArguments[widget]!;
    for (final arg in _argumentsOf(code, m.end - 1)) {
      final named = RegExp(
        r'^\s*(\w+)\s*:(.*)$',
        dotAll: true,
      ).firstMatch(arg.text);
      if (named == null || !names.contains(named.group(1))) continue;
      if (!_isRawNumber(named.group(2)!)) continue;
      out.add(
        SourceFinding(scanned.lineOf(arg.start), '$widget(${named.group(1)}:)'),
      );
    }
  }

  for (final m in _numericNamed.allMatches(code)) {
    if (_isZero.hasMatch(m.group(2)!.trim())) continue;
    out.add(SourceFinding(scanned.lineOf(m.start), '${m.group(1)}:'));
  }

  for (final m in _strokeWidthAssignment.allMatches(code)) {
    if (_isZero.hasMatch(m.group(1)!.trim())) continue;
    out.add(SourceFinding(scanned.lineOf(m.start), '.strokeWidth ='));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Which files
// ---------------------------------------------------------------------------

/// Whether [rel] (repo-relative, POSIX) is Dart in a package's `lib/` under
/// `platform/` or `modules/`, or in an app's `lib/` (`apps/<id>/lib`) — where
/// R19 and R20 apply, the same scope as R17 and R18. An app is not exempt from
/// "never `print`" (RULE-65) or "no raw doubles in layout" (RULE-30): the
/// analyzer's `avoid_print` covers `print` only, and nothing else reads an
/// app's widgets. Test code is a different `lib`-less folder; tools have their
/// own output rule.
bool isProductLib(String rel) {
  if (!rel.endsWith('.dart')) return false;
  final segments = rel.split('/');
  if (segments.length < 3) return false;
  return switch (segments.first) {
    'platform' || 'modules' => segments.contains('lib'),
    'apps' => segments[2] == 'lib',
    _ => false,
  };
}

/// Whether [rel] lives under a `styles/` or `utils/` folder, where constants
/// (design tokens, raw values) are meant to be declared.
bool isConstantsHome(String rel) {
  final segments = rel.split('/');
  return segments.contains('styles') || segments.contains('utils');
}
