import 'dart:convert';
import 'dart:io';

import 'package:ssh_agent_core/ssh_agent_core.dart';
import 'package:test/test.dart';

/// Runs [word] through a real POSIX shell and returns what it expands to.
Future<String> expand(String word, {Map<String, String>? env}) async {
  final result = await Process.run('sh', [
    '-c',
    'printf "%s" $word',
  ], environment: env);
  return result.stdout as String;
}

void main() {
  group('shQuote', () {
    test('quotes single quotes', () {
      expect(shQuote("it's"), r"'it'\''s'");
    });

    test('survives a real shell unchanged', () async {
      const nasty = r"""a'b"c $(touch x) `id` ; | & > < \ * ? ~ $HOME""";
      expect(await expand(shQuote(nasty)), nasty);
    }, testOn: 'posix');
  });

  group('shPath', () {
    test('plain paths are quoted', () {
      expect(shPath('/etc/passwd'), "'/etc/passwd'");
    });

    test('a leading dash cannot become an option', () {
      expect(shPath('-rf'), "'./-rf'");
    });

    test('home and user home are expanded', () async {
      expect(shPath('~'), r'"$HOME"');
      expect(
        shPath('~/x y'),
        r'"$HOME"/'
        "'x y'",
      );
      expect(shPath('~root/.ssh'), "~root/'.ssh'");
      expect(
        await expand(shPath('~/a b'), env: {'HOME': '/home/t'}),
        '/home/t/a b',
      );
    }, testOn: 'posix');

    test('globs stay active, everything else is quoted', () {
      expect(shPath('/var/log/*.log'), "'/var/log/'*'.log'");
      expect(shPath('/x/\$(id)*'), "'/x/\$(id)'*");
      expect(shPath('/var/log/*.log', allowGlob: false), "'/var/log/*.log'");
    });

    test('rejects control characters and empty paths', () {
      expect(
        () => shPath('/etc\npasswd'),
        throwsA(isA<ToolArgumentException>()),
      );
      expect(() => shPath('a\u0000b'), throwsA(isA<ToolArgumentException>()));
      expect(() => shPath('  '), throwsA(isA<ToolArgumentException>()));
    });
  });

  test('limitLines reports cut lines', () async {
    final result = await Process.run('sh', [
      '-c',
      'seq 1 10 | ${limitLines(3)}',
    ]);
    expect(result.stdout, '1\n2\n3\n... [7 more lines not shown]\n');
  }, testOn: 'posix');

  test('limitLines passes each line on at once', () async {
    final process = await Process.start('sh', [
      '-c',
      '$awkLinewiseSetup\n'
          '{ echo first; sleep 3; echo second; } | ${limitLines(5)}',
    ]);
    // Arrives while the command is still running, not after it ends.
    final firstLine = await process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 2));
    expect(firstLine, 'first');
    process.kill();
    await process.exitCode;
  }, testOn: 'posix');
}
