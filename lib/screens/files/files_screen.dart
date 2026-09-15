import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/server_provider.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final ApiService _api = ApiService();
  String _currentPath = '/';
  List<String> _directories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _currentPath = path;
    });

    try {
      final dirs = await _api.listRemoteDirectories(prefix: path);
      setState(() {
        _directories = dirs;
      });
    } catch (_) {}

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quản Lý Tệp (SFTP)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              serverProvider.selectedServer != null
                  ? '${serverProvider.selectedServer!.name} (${serverProvider.selectedServer!.serverIp})'
                  : 'Chưa chọn máy chủ',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDirectory(_currentPath),
          ),
        ],
      ),
      body: Column(
        children: [
          // Path Breadcrumb Navigation
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surfaceDark,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  tooltip: 'Thư mục cha',
                  onPressed: _currentPath == '/'
                      ? null
                      : () {
                          final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
                          if (parts.isNotEmpty) {
                            parts.removeLast();
                            final newPath = parts.isEmpty ? '/' : '/${parts.join('/')}';
                            _loadDirectory(newPath);
                          }
                        },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _currentPath,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // File / Directory List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _directories.isEmpty
                    ? const Center(child: Text('Thư mục trống', style: TextStyle(color: AppColors.textMuted)))
                    : ListView.builder(
                        itemCount: _directories.length,
                        itemBuilder: (context, index) {
                          final dir = _directories[index];
                          final name = dir.split('/').where((p) => p.isNotEmpty).isNotEmpty
                              ? dir.split('/').where((p) => p.isNotEmpty).last
                              : dir;

                          return ListTile(
                            leading: const Icon(Icons.folder_rounded, color: AppColors.primaryLight),
                            title: Text(
                              name,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              dir,
                              style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textDim),
                            onTap: () => _loadDirectory(dir),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
