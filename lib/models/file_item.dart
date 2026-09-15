class FileItemModel {
  final String name;
  final String path;
  final bool isDirectory;
  final String size;
  final String permissions;
  final String modifiedAt;

  FileItemModel({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = '',
    this.permissions = '',
    this.modifiedAt = '',
  });

  factory FileItemModel.fromPath(String fullPath, {bool isDir = true}) {
    final parts = fullPath.split('/');
    final name = parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : fullPath;
    return FileItemModel(
      name: name,
      path: fullPath,
      isDirectory: isDir,
    );
  }
}
