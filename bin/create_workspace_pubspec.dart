import 'dart:convert';
import 'dart:io';
import 'package:pub/src/pubspec.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub/src/system_cache.dart';
import 'package:pub/src/package_name.dart';
import 'package:pub/src/language_version.dart';
import 'package:path/path.dart' as path;
import 'package:pub/src/source/path.dart'; 
import 'package:pub/src/source.dart';

void main() {
  if (File('pubspec.yaml').existsSync()) {
    fail(
      '❌ pubspec.yaml already exists. Run this in the root of a mono-repo without a pubspec.yaml.',
    );
  }

  final sdkVersion = Platform.version.split(' ').first;

  final pubspecs = Directory.current
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => path.basename(f.path) == 'pubspec.yaml')
      .toList();

  if (pubspecs.isEmpty) {
    fail('❌ Found no pubspec.yaml files in child directories.');
  }
    
  final parsedPubspecs = pubspecs
      .map((f) => (
            f.path,
            Pubspec.parse(
              f.readAsStringSync(),
              SystemCache().sources,
              containingDescription: ResolvedDescription(
                description: PathDescription(
                  path: path.absolute(path.dirname(f.path)),
                  relative: false,
                ),
                containingDir: path.absolute(path.dirname(f.path)),
              ),
              location: f.uri,
            )
          ))
      .toList();

  

  final devDependencies = parsedPubspecs
      .expand((pubspec) => pubspec.$2.devDependencies.entries)
      .toList();

  final mergedDevDependencies = <String, PackageRange>{};

  for (final entry in devDependencies) {
    final name = entry.key;
    final dep = entry.value;

    final existing = mergedDevDependencies[name];
    if (existing == null) {
      mergedDevDependencies[name] = dep;
    } else {
      if (existing.source != dep.source) {
        fail(
            '❌ Package $name has conflicting sources: ${existing.source} and ${dep.source}.');
      }
      mergedDevDependencies[name] = existing
          .toRef()
          .withConstraint(existing.constraint.intersect(dep.constraint));
    }
  }

  final devDepsYaml = mergedDevDependencies.entries.map((e) {
    final name = e.key;
    final d = e.value;
    final descJson = d.description.serializeForPubspec(
      containingDir: '.',
      languageVersion: LanguageVersion.parse('3.0'),
    );

    if (d.source is HostedSource && descJson == null) {
      return '  $name: ${d.constraint}';
    }

    final descMap = {
      'version': d.constraint.toString(),
      d.source.name: descJson,
    };

    final yamlEncoded = const JsonEncoder.withIndent('    ').convert(descMap);
    return '  $name: $yamlEncoded'.replaceAll('\n', '\n    ');
  }).join('\n');

  final overridesYaml = parsedPubspecs.map((p) {
    final relativePath = path.posix.joinAll(path.split(path.relative(path.dirname(p.$1))));
    return '  ${p.$2.name}: { path: ${json.encode(relativePath)} }';
  }).join('\n');

  final projectPubspec = '''
name: global_project
environment:
  sdk: ^$sdkVersion

dev_dependencies:
$devDepsYaml

dependency_overrides:
$overridesYaml
''';

  File('pubspec.yaml').writeAsStringSync(projectPubspec.trimRight());
  print('✅ Wrote project-wide `pubspec.yaml`. Run `dart pub get` to resolve.');
}

Never fail(String message) {
  stderr.writeln(message);
  exit(1);
}
