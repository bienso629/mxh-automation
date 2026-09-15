import 'dart:io';
import 'package:path/path.dart' as p;

class LocalCliAgent {
  final String id;
  final String binary;
  final String path;
  final String label;
  final String? version;

  const LocalCliAgent({
    required this.id,
    required this.binary,
    required this.path,
    required this.label,
    this.version,
  });
}

class CliScannerService {
  static final CliScannerService _instance = CliScannerService._internal();
  factory CliScannerService() => _instance;
  CliScannerService._internal();

  static const List<Map<String, dynamic>> _candidateAgents = [
    {
      'id': 'antigravity-cli',
      'binaries': ['agy', 'antigravity'],
      'label': 'Google Antigravity CLI',
    },
    {
      'id': 'claude-cli',
      'binaries': ['claude'],
      'label': 'Anthropic Claude Code CLI',
    },
    {
      'id': 'gemini-cli',
      'binaries': ['gemini'],
      'label': 'Google Gemini CLI',
    },
    {
      'id': 'ollama',
      'binaries': ['ollama'],
      'label': 'Ollama Local LLM',
    },
    {
      'id': 'sgpt-cli',
      'binaries': ['sgpt'],
      'label': 'ShellGPT CLI',
    },
    {
      'id': 'aichat-cli',
      'binaries': ['aichat'],
      'label': 'AIChat CLI',
    },
  ];

  List<String> _getSearchPaths() {
    final searchDirs = <String>[];
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

    if (home.isNotEmpty) {
      searchDirs.add(p.join(home, '.local', 'bin'));
      searchDirs.add(p.join(home, '.cargo', 'bin'));
      searchDirs.add(p.join(home, 'bin'));

      // Check nvm node bin paths
      final nvmNodeDir = Directory(p.join(home, '.nvm', 'versions', 'node'));
      if (nvmNodeDir.existsSync()) {
        try {
          for (final entity in nvmNodeDir.listSync()) {
            if (entity is Directory) {
              final binDir = p.join(entity.path, 'bin');
              if (Directory(binDir).existsSync()) {
                searchDirs.add(binDir);
              }
            }
          }
        } catch (_) {}
      }
    }

    // Common system paths
    searchDirs.addAll([
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/snap/bin',
      '/opt/homebrew/bin',
      '/usr/local/opt',
    ]);

    // Add PATH env variable dirs
    final envPath = Platform.environment['PATH'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';
    for (final part in envPath.split(separator)) {
      if (part.trim().isNotEmpty && !searchDirs.contains(part.trim())) {
        searchDirs.add(part.trim());
      }
    }

    return searchDirs;
  }

  Future<List<LocalCliAgent>> scanInstalledAgents() async {
    final installed = <LocalCliAgent>[];
    final searchPaths = _getSearchPaths();

    for (final candidate in _candidateAgents) {
      final id = candidate['id'] as String;
      final binaries = candidate['binaries'] as List<String>;
      final label = candidate['label'] as String;

      String? foundPath;
      String? foundBinary;

      for (final bin in binaries) {
        // 1. Check direct file existence in search paths
        for (final dirPath in searchPaths) {
          final candidateFile = File(p.join(dirPath, bin));
          final candidateExe = Platform.isWindows ? File(p.join(dirPath, '$bin.exe')) : null;

          if (candidateFile.existsSync()) {
            foundPath = candidateFile.path;
            foundBinary = bin;
            break;
          } else if (candidateExe != null && candidateExe.existsSync()) {
            foundPath = candidateExe.path;
            foundBinary = '$bin.exe';
            break;
          }
        }

        // 2. Try which/where if not found yet
        if (foundPath == null) {
          try {
            final cmd = Platform.isWindows ? 'where' : 'which';
            final res = await Process.run(cmd, [bin]).timeout(const Duration(milliseconds: 600));
            if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
              final lines = res.stdout.toString().trim().split('\n');
              if (lines.isNotEmpty && File(lines.first.trim()).existsSync()) {
                foundPath = lines.first.trim();
                foundBinary = bin;
              }
            }
          } catch (_) {}
        }

        if (foundPath != null) break;
      }

      if (foundPath != null && foundBinary != null) {
        String? ver;
        try {
          final verRes = await Process.run(foundPath, ['--version']).timeout(const Duration(milliseconds: 800));
          if (verRes.exitCode == 0) {
            final output = verRes.stdout.toString().trim();
            if (output.isNotEmpty) {
              final firstLine = output.split('\n').first.trim();
              if (firstLine.length < 30) {
                ver = firstLine;
              }
            }
          }
        } catch (_) {}

        installed.add(LocalCliAgent(
          id: id,
          binary: foundBinary,
          path: foundPath,
          label: label,
          version: ver,
        ));
      }
    }

    return installed;
  }
}
