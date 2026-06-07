import 'dart:io';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart tool/extract_changelog.dart <version> <output>');
    exit(64);
  }

  final version = args[0].replaceFirst(RegExp(r'^v'), '');
  final output = args[1];
  final changelog = File('CHANGELOG.md').readAsStringSync();
  final heading = RegExp('^## v${RegExp.escape(version)}(?: |\\\$)', multiLine: true);
  final match = heading.firstMatch(changelog);
  if (match == null) {
    File(output).writeAsStringSync(changelog);
    return;
  }

  final start = match.start;
  final laterHeadings = RegExp(r'^## v', multiLine: true).allMatches(changelog, match.end);
  final nextStart = laterHeadings.isEmpty ? changelog.length : laterHeadings.first.start;
  final body = changelog.substring(start, nextStart).trim();
  File(output).writeAsStringSync('$body\n');
}
