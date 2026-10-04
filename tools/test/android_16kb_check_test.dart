import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_bin.dart';
import 'support/tool_harness.dart';

/// `tools/android_compliance/16kb_check.sh` (and its `.bat` wrapper) — the
/// Android 15+ 16 KB page-size check.
///
/// The script reads the alignment of the first LOAD segment of every native
/// library with `objdump -p`. The fixtures are real, minimal ELF64 shared
/// objects written byte by byte here — one program header whose `p_align` is
/// the alignment under test — and stored (uncompressed) zip files for the
/// APK cases, so no NDK, no `zip` and no Android SDK is needed.
///
/// What the script itself requires (`bash`, `objdump`, `unzip`, `file`) is
/// checked first: the cases that run it are skipped, with the missing tool
/// named, when one is absent. `zipalign` is optional and never needed.
///
/// The script's own contract is exit 1 for every refusal (no exit 64), which
/// is what these cases assert.
void main() {
  final script = p.join(
    repoRoot,
    'tools',
    'android_compliance',
    '16kb_check.sh',
  );

  /// Names of the tools the script needs that are not on `PATH`.
  final missing = [
    for (final tool in const ['bash', 'objdump', 'unzip', 'file'])
      if (!_onPath(tool)) tool,
  ];
  final Object skipReason = missing.isEmpty
      ? false
      : 'needs ${missing.join(', ')} on PATH (the checker requires them too)';

  group('the files', () {
    test('the .sh is a bash script that parses', () {
      final text = File(script).readAsStringSync();
      expect(text, startsWith('#!/bin/bash'));
    });

    test(
      'bash accepts the syntax of the .sh',
      () {
        final result = Process.runSync('bash', ['-n', script]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      },
      skip: _onPath('bash') ? false : 'no bash on PATH',
    );

    test(
      'the .bat hands every argument to the .sh and returns its exit code',
      () {
        final bat = File(
          p.join(repoRoot, 'tools', 'android_compliance', '16kb_check.bat'),
        ).readAsStringSync();

        expect(bat, contains('16kb_check.sh" %*'));
        expect(bat, contains('exit /b %ERRORLEVEL%'));
        // Git Bash first: a WSL bash.exe on PATH cannot read Windows paths.
        expect(bat.indexOf('Program'), lessThan(bat.indexOf('where bash')));
      },
    );

    test('the .bat fails with exit 1 and a message when no bash exists', () {
      final bat = File(
        p.join(repoRoot, 'tools', 'android_compliance', '16kb_check.bat'),
      ).readAsStringSync();

      expect(bat, contains('Git Bash'));
      expect(bat, contains('exit /b 1'));
    });
  });

  group('arguments', () {
    test('no argument prints the usage to stderr and exits 1', () async {
      final run = await _check(script, const []);

      expect(run, exitsWith(1));
      expect(run.stderr, contains('USAGE:'));
      expect(run.stderr, contains('<input-path|input-APK|input-APEX>'));
    }, skip: skipReason);

    test('two arguments are refused like none', () async {
      final run = await _check(script, ['a.apk', 'b.apk']);

      expect(run, exitsWith(1));
      expect(run.stderr, contains('USAGE:'));
    }, skip: skipReason);

    for (final flag in const ['--help', '-h', '-?']) {
      test('$flag prints the usage to stdout and exits 0', () async {
        final run = await _check(script, [flag]);

        expect(run, exitsWith(0));
        expect(run.stdout, contains('DESCRIPTION:'));
        expect(run.stdout, contains('WHAT THIS TOOL CHECKS:'));
        expect(run.stdout, contains('flutter-apk/app-<flavor>-release.apk'));
        expect(run.stdout, contains('RESULT MEANINGS:'));
      }, skip: skipReason);
    }

    test('a path that does not exist exits 1', () async {
      final ws = TempWorkspace.create({});

      final run = await _check(script, [p.join(ws.root, 'nope.apk')]);

      expect(run, exitsWith(1));
      expect(run.output, contains('Invalid input'));
      expect(run.output, contains('valid APK file'));
    }, skip: skipReason);

    test(
      'a file of another kind is refused, not scanned as a directory',
      () async {
        // It used to find no library and report PASS.
        final ws = TempWorkspace.create({'notes.txt': 'hello'});

        final run = await _check(script, [p.join(ws.root, 'notes.txt')]);

        expect(run, exitsWith(1));
        expect(run.output, contains('Unsupported file'));
        expect(run.output, contains('Pass an .apk, an .apex, a single .so'));
      },
      skip: skipReason,
    );

    test('an .aab is refused and the message points at the APK', () async {
      final ws = TempWorkspace.create({'app.aab': 'PK'});

      final run = await _check(script, [p.join(ws.root, 'app.aab')]);

      expect(run, exitsWith(1));
      expect(run.output, contains('An .aab is not supported'));
    }, skip: skipReason);
  });

  group('a directory of libraries', () {
    test('every library 16 KB aligned passes with exit 0', () async {
      final ws = _workspace({
        'lib/arm64-v8a/libapp.so': _elf(1 << 14),
        'lib/x86_64/libapp.so': _elf(1 << 16),
      });

      final run = await _check(script, [ws.root]);

      expect(run, exitsWith(0));
      expect(run.output, contains('COMPATIBILITY CHECK PASSED'));
      expect(run.output, contains('Google Play Compliance: PASSED'));
      expect(run.output, contains('Total libraries scanned: 2'));
      expect(run.output, contains('2**14'));
      expect(run.output, contains('2**16'));
    }, skip: skipReason);

    test('a 4 KB aligned arm64-v8a library fails with exit 1', () async {
      final ws = _workspace({
        'lib/arm64-v8a/libold.so': _elf(1 << 12),
      });

      final run = await _check(script, [ws.root]);

      expect(run, exitsWith(1));
      expect(run.output, contains('COMPATIBILITY CHECK FAILED'));
      expect(run.output, contains('Google Play Compliance: FAILED'));
      expect(run.output, contains('2**12'));
      expect(run.output, contains('FAIL'));
      expect(run.output, contains('Critical failures: 1 (MUST FIX)'));
      expect(run.output, contains('libold.so'));
    }, skip: skipReason);

    test('2**13 fails and 2**14 passes: the boundary is 16 KB', () async {
      final below = _workspace({'lib/arm64-v8a/liba.so': _elf(1 << 13)});
      final at = _workspace({'lib/arm64-v8a/liba.so': _elf(1 << 14)});

      expect(await _check(script, [below.root]), exitsWith(1));
      expect(await _check(script, [at.root]), exitsWith(0));
    }, skip: skipReason);

    test('a larger alignment (2**20) passes', () async {
      final ws = _workspace({'lib/x86_64/libbig.so': _elf(1 << 20)});

      final run = await _check(script, [ws.root]);

      expect(run, exitsWith(0));
      expect(run.output, contains('2**20'));
    }, skip: skipReason);

    test(
      'one unaligned library among aligned ones fails and is counted',
      () async {
        final ws = _workspace({
          'lib/arm64-v8a/good.so': _elf(1 << 14),
          'lib/arm64-v8a/bad.so': _elf(1 << 12),
          'lib/x86_64/good.so': _elf(1 << 14),
        });

        final run = await _check(script, [ws.root]);

        expect(run, exitsWith(1));
        expect(run.output, contains('Total libraries scanned: 3'));
        expect(run.output, contains('Libraries aligned: 2'));
        expect(run.output, contains('Libraries UNALIGNED: 1'));
        expect(run.output, contains('bad.so'));
      },
      skip: skipReason,
    );

    test(
      'an unaligned 32-bit library is only a warning, but still exits 1',
      () async {
        final ws = _workspace({
          'lib/arm64-v8a/ok.so': _elf(1 << 14),
          'lib/armeabi-v7a/old.so': _elf(1 << 12),
        });

        final run = await _check(script, [ws.root]);

        expect(run, exitsWith(1));
        expect(run.output, contains('WARN'));
        expect(run.output, contains('Non-critical warnings: 1 (SHOULD FIX)'));
        expect(run.output, isNot(contains('Critical failures')));
        expect(
          run.output,
          contains('Non-Critical Libraries (Recommended to Fix)'),
        );
      },
      skip: skipReason,
    );

    test('an ELF library without the .so extension is still checked', () async {
      final ws = _workspace({'lib/arm64-v8a/libhidden': _elf(1 << 12)});

      final run = await _check(script, [ws.root]);

      expect(run, exitsWith(1));
      expect(run.output, contains('libhidden'));
    }, skip: skipReason);

    test('a .so that is not an ELF file is skipped', () async {
      final ws = _workspace({'lib/arm64-v8a/fake.so': 'not an elf file'});

      final run = await _check(script, [ws.root]);

      expect(run, exitsWith(0));
      expect(run.output, contains('Total libraries scanned: 0'));
    }, skip: skipReason);

    test('a directory with no native library passes', () async {
      final ws = TempWorkspace.create({'classes.dex': 'dex'});

      final run = await _check(script, [ws.root]);

      expect(run, exitsWith(0));
      expect(run.output, contains('NO NATIVE LIBRARIES DETECTED'));
    }, skip: skipReason);

    test('a single .so file can be checked', () async {
      final good = _workspace({'libgood.so': _elf(1 << 14)});
      final bad = _workspace({'libbad.so': _elf(1 << 12)});

      expect(
        await _check(script, [p.join(good.root, 'libgood.so')]),
        exitsWith(0),
      );
      final run = await _check(script, [p.join(bad.root, 'libbad.so')]);
      expect(run, exitsWith(1));
      expect(run.output, contains('libbad.so'));
    }, skip: skipReason);
  });

  group('an APK', () {
    test(
      'with 16 KB aligned libraries passes and leaves no temp files',
      () async {
        final ws = TempWorkspace.create({});
        final apk = _apk(ws, 'good.apk', {
          'lib/arm64-v8a/libapp.so': _elf(1 << 14),
          'lib/x86_64/libapp.so': _elf(1 << 14),
          'classes.dex': Uint8List.fromList([1, 2, 3]),
        });
        final tmp = _tmpDir();

        final run = await _check(script, [apk], tmpDir: tmp);

        expect(run, exitsWith(0));
        expect(run.output, contains('COMPATIBILITY CHECK PASSED'));
        expect(run.output, contains('Total libraries scanned: 2'));
        expect(Directory(tmp).listSync(), isEmpty);
      },
      skip: skipReason,
    );

    test(
      'with an unaligned library fails and still removes its temp files',
      () async {
        final ws = TempWorkspace.create({});
        final apk = _apk(ws, 'bad.apk', {
          'lib/arm64-v8a/libapp.so': _elf(1 << 14),
          'lib/x86_64/libold.so': _elf(1 << 12),
        });
        final tmp = _tmpDir();

        final run = await _check(script, [apk], tmpDir: tmp);

        expect(run, exitsWith(1));
        expect(run.output, contains('COMPATIBILITY CHECK FAILED'));
        expect(run.output, contains('libold.so'));
        expect(Directory(tmp).listSync(), isEmpty);
      },
      skip: skipReason,
    );

    group('zipalign', () {
      /// A fake `zipalign`: `--help` advertises 16 KB support (or not), and
      /// the verification run exits with [verifyExit].
      FakeBin zipalign({required int verifyExit, bool supports16kb = true}) =>
          FakeBin.create({
            'zipalign':
                '''
case "\$1" in
  --help) echo "zipalign ${supports16kb ? '[-P <pagesize_kb>] ' : ''}[-c] [-v]"; exit 0 ;;
esac
[ $verifyExit -ne 0 ] && echo "Verification FAILED: lib/arm64-v8a/libapp.so (BAD)"
exit $verifyExit
''',
          });

      String alignedApk() => _apk(TempWorkspace.create({}), 'good.apk', {
        'lib/arm64-v8a/libapp.so': _elf(1 << 14),
        'classes.dex': Uint8List.fromList([1, 2, 3]),
      });

      test(
        'a failed verification fails the check even when every ELF segment '
        'is aligned, and the temp files are still removed',
        () async {
          final tmp = _tmpDir();

          final run = await _check(
            script,
            [alignedApk()],
            tmpDir: tmp,
            bin: zipalign(verifyExit: 1),
          );

          expect(run, exitsWith(1));
          expect(run.output, contains('APK zip-alignment verification failed'));
          expect(run.output, contains('ZIP ALIGNMENT CHECK FAILED'));
          expect(run.output, isNot(contains('COMPATIBILITY CHECK PASSED')));
          expect(Directory(tmp).listSync(), isEmpty);
        },
        skip: skipReason == false ? skipWithoutPosixShell() : skipReason,
      );

      test(
        'a passing verification changes nothing: exit 0',
        () async {
          final run = await _check(
            script,
            [alignedApk()],
            tmpDir: _tmpDir(),
            bin: zipalign(verifyExit: 0),
          );

          expect(run, exitsWith(0));
          expect(run.output, contains('APK zip-alignment verification passed'));
          expect(run.output, contains('COMPATIBILITY CHECK PASSED'));
        },
        skip: skipReason == false ? skipWithoutPosixShell() : skipReason,
      );

      test(
        'a zipalign that cannot check 16 KB is a warning, not a failure',
        () async {
          final run = await _check(
            script,
            [alignedApk()],
            tmpDir: _tmpDir(),
            bin: zipalign(verifyExit: 1, supports16kb: false),
          );

          expect(run, exitsWith(0));
          expect(
            run.output,
            contains("zipalign version doesn't support 16KB alignment checks"),
          );
        },
        skip: skipReason == false ? skipWithoutPosixShell() : skipReason,
      );
    });

    test('without any lib/ entry is a pass: Java and Kotlin only', () async {
      final ws = TempWorkspace.create({});
      final apk = _apk(ws, 'java.apk', {
        'classes.dex': Uint8List.fromList([1, 2, 3]),
      });
      final tmp = _tmpDir();

      final run = await _check(script, [apk], tmpDir: tmp);

      expect(run, exitsWith(0));
      expect(run.output, contains('NO NATIVE LIBRARIES FOUND'));
      expect(Directory(tmp).listSync(), isEmpty);
    }, skip: skipReason);

    test(
      'that is not a zip archive fails: a truncated download is not a pass',
      () async {
        final ws = TempWorkspace.create({
          'broken.apk': 'this is not a zip file',
        });
        final tmp = _tmpDir();

        final run = await _check(script, [
          p.join(ws.root, 'broken.apk'),
        ], tmpDir: tmp);

        expect(run, exitsWith(1));
        expect(run.output, contains('Cannot read broken.apk as an APK'));
        expect(run.output, isNot(contains('PASSED')));
        expect(Directory(tmp).listSync(), isEmpty);
      },
      skip: skipReason,
    );
  });
}

/// Whether [tool] resolves on `PATH` (`which` / `where`); false when even
/// that lookup is unavailable.
bool _onPath(String tool) {
  try {
    return Process.runSync(Platform.isWindows ? 'where' : 'which', [
          tool,
        ]).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}

/// A workspace of [files]: a [String] is written as text, a [Uint8List] as
/// bytes.
TempWorkspace _workspace(Map<String, Object> files) {
  final ws = TempWorkspace.create({});
  for (final entry in files.entries) {
    final file = File(p.join(ws.root, entry.key));
    file.parent.createSync(recursive: true);
    final content = entry.value;
    if (content is Uint8List) {
      file.writeAsBytesSync(content);
    } else {
      file.writeAsStringSync(content as String);
    }
  }
  return ws;
}

/// A fresh empty directory for the script's `mktemp` (`TMPDIR`), removed at
/// the end of the test, so a leftover extraction directory is visible.
String _tmpDir() {
  final dir = Directory.systemTemp.createTempSync('check16_tmp_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir.resolveSymbolicLinksSync();
}

/// Runs the checker. Colours are off (stdout is a pipe) and `TMPDIR` points
/// at [tmpDir] when given.
Future<ToolRun> _check(
  String script,
  List<String> args, {
  String? tmpDir,
  FakeBin? bin,
}) async {
  final result = await Process.run(
    'bash',
    [script, ...args],
    environment: {...?bin?.environment, 'TMPDIR': ?tmpDir},
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return ToolRun(result.exitCode, '${result.stdout}', '${result.stderr}');
}

/// A minimal little-endian ELF64 shared object for aarch64: the file header
/// and one `PT_LOAD` program header whose `p_align` is [alignment].
/// `objdump -p` prints it as `align 2**<log2>`.
Uint8List _elf(int alignment) {
  final bytes = ByteData(64 + 56);
  // e_ident: magic, ELFCLASS64, little endian, EV_CURRENT.
  bytes.setUint8(0, 0x7f);
  bytes.setUint8(1, 0x45); // E
  bytes.setUint8(2, 0x4c); // L
  bytes.setUint8(3, 0x46); // F
  bytes.setUint8(4, 2);
  bytes.setUint8(5, 1);
  bytes.setUint8(6, 1);
  bytes.setUint16(16, 3, Endian.little); // e_type: ET_DYN
  bytes.setUint16(18, 183, Endian.little); // e_machine: EM_AARCH64
  bytes.setUint32(20, 1, Endian.little); // e_version
  bytes.setUint64(32, 64, Endian.little); // e_phoff
  bytes.setUint16(52, 64, Endian.little); // e_ehsize
  bytes.setUint16(54, 56, Endian.little); // e_phentsize
  bytes.setUint16(56, 1, Endian.little); // e_phnum
  // The program header.
  bytes.setUint32(64, 1, Endian.little); // p_type: PT_LOAD
  bytes.setUint32(68, 5, Endian.little); // p_flags: R+X
  bytes.setUint64(96, 120, Endian.little); // p_filesz
  bytes.setUint64(104, 120, Endian.little); // p_memsz
  bytes.setUint64(112, alignment, Endian.little); // p_align
  return bytes.buffer.asUint8List();
}

/// Writes [entries] as a stored (uncompressed) zip named [name] in [ws] and
/// returns its path.
String _apk(TempWorkspace ws, String name, Map<String, Uint8List> entries) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  for (final entry in entries.entries) {
    final fileName = utf8.encode(entry.key);
    final data = entry.value;
    final crc = _crc32(data);
    final offset = out.length;

    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 10, Endian.little) // version needed
      ..setUint16(8, 0, Endian.little) // method: stored
      ..setUint16(10, 0, Endian.little) // time
      ..setUint16(12, 0x21, Endian.little) // date: 1980-01-01
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, fileName.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(fileName)
      ..add(data);

    final header = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little) // version made by
      ..setUint16(6, 10, Endian.little) // version needed
      ..setUint16(14, 0x21, Endian.little) // date
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, fileName.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(header.buffer.asUint8List())
      ..add(fileName);
    count++;
  }
  final centralOffset = out.length;
  final centralBytes = central.toBytes();
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, count, Endian.little)
    ..setUint16(10, count, Endian.little)
    ..setUint32(12, centralBytes.length, Endian.little)
    ..setUint32(16, centralOffset, Endian.little);
  out
    ..add(centralBytes)
    ..add(end.buffer.asUint8List());
  final file = File(p.join(ws.root, name))..writeAsBytesSync(out.toBytes());
  return file.path;
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
