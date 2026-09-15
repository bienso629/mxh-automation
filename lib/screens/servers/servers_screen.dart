import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/server_model.dart';
import '../../providers/server_provider.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  void _showAddServerDialog(BuildContext context, [ServerModel? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ipCtrl = TextEditingController(text: existing?.serverIp ?? '');
    final portCtrl = TextEditingController(text: existing?.sshPort.toString() ?? '22');
    final userCtrl = TextEditingController(text: existing?.sshUser ?? 'root');
    final passCtrl = TextEditingController(text: existing?.sshPass ?? '');

    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 500,
        maxWidth: 620,
        title: Row(
          children: [
            const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 22),
            const SizedBox(width: 8),
            Text(existing != null ? 'Chỉnh Sửa Máy Chủ' : 'Thêm Máy Chủ Mới'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên Máy Chủ (Ví dụ: Web Production)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ipCtrl,
              decoration: const InputDecoration(labelText: 'Địa Chỉ IP / Hostname'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: portCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'SSH Port'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(labelText: 'SSH User'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật Khẩu SSH (hoặc sudo pass)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final newServer = ServerModel(
                id: existing?.id ?? 'srv_${DateTime.now().millisecondsSinceEpoch}',
                name: nameCtrl.text.trim().isEmpty ? ipCtrl.text.trim() : nameCtrl.text.trim(),
                serverIp: ipCtrl.text.trim(),
                sshPort: int.tryParse(portCtrl.text.trim()) ?? 22,
                sshUser: userCtrl.text.trim(),
                sshPass: passCtrl.text.trim(),
                isSelected: existing?.isSelected ?? false,
              );
              context.read<ServerProvider>().addOrUpdateServer(newServer);
              Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh Sách Máy Chủ VPS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Thêm Server',
            onPressed: () => _showAddServerDialog(context),
          ),
        ],
      ),
      body: serverProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : serverProvider.servers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.dns_outlined, size: 54, color: AppColors.textDim),
                      const SizedBox(height: 12),
                      const Text('Chưa có máy chủ nào', style: TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm Máy Chủ VPS'),
                        onPressed: () => _showAddServerDialog(context),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: serverProvider.servers.length,
                  itemBuilder: (context, index) {
                    final s = serverProvider.servers[index];
                    final isSelected = serverProvider.selectedServer != null &&
                        (s.id == serverProvider.selectedServer!.id || s.serverIp == serverProvider.selectedServer!.serverIp);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.surfaceDark : AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.borderDark,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.storage_rounded,
                            color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              s.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'ĐANG CHỌN',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${s.sshUser}@${s.serverIp}:${s.sshPort}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _showAddServerDialog(context, s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => TaduDialog(
                                    minWidth: 420,
                                    maxWidth: 500,
                                    title: const Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 22),
                                        SizedBox(width: 8),
                                        Text('Xóa Máy Chủ?'),
                                      ],
                                    ),
                                    content: Text('Bạn có chắc muốn xóa "${s.name}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                        onPressed: () {
                                          serverProvider.deleteServer(s.id);
                                          Navigator.pop(ctx);
                                        },
                                        child: const Text('Xóa'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        onTap: () => serverProvider.selectServer(s),
                      ),
                    ),
                    );
                  },
                ),
    );
  }
}
