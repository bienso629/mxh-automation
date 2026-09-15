import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';
import 'tadu_dialog.dart';
import '../../providers/server_provider.dart';

class ModelPickerDialog extends StatefulWidget {
  final ServerProvider serverProvider;

  const ModelPickerDialog({
    super.key,
    required this.serverProvider,
  });

  static void show(BuildContext context) {
    final serverProvider = context.read<ServerProvider>();
    showDialog(
      context: context,
      builder: (ctx) => ModelPickerDialog(
        serverProvider: serverProvider,
      ),
    );
  }

  static void showCustomModelDialog(BuildContext context, ServerProvider serverProvider) {
    final ctrl = TextEditingController(text: serverProvider.currentAiModel);
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 440,
        maxWidth: 500,
        title: const Row(
          children: [
            Icon(Icons.tune_rounded, color: AppColors.primaryLight, size: 20),
            SizedBox(width: 8),
            Text('Nhập AI Model Tùy Biến'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập tên định danh của AI Model:',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'VD: glm-5.3, gpt-4o, deepseek-chat...',
              ),
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
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                serverProvider.setGlobalAiModel(val);
                Navigator.pop(ctx);
                AppToast.success(context, 'Đã đặt AI Model: $val');
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  @override
  State<ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<ModelPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.serverProvider.fetchMitomModels();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerProvider>(
      builder: (context, serverProvider, child) {
        final q = _searchQuery.toLowerCase();

        // Cloud Models: Lấy từ API https://api-vn-sg.mitom.ai/v1/models (fallback nếu chưa tải xong)
        final cloudModelsSource = serverProvider.mitomModels.isNotEmpty
            ? serverProvider.mitomModels
            : const ['glm-5.3', 'gpt-4o', 'deepseek-chat', 'claude-3-7-sonnet'];
        final filteredCloudModels = cloudModelsSource.where((m) {
          if (q.isEmpty) return true;
          return m.toLowerCase().contains(q);
        }).toList();

        return Dialog(
          backgroundColor: AppColors.cardBg,
          elevation: 24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.borderLight, width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 560,
            height: 600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF090F1E),
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderLight, width: 1.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.smart_toy_rounded, size: 20, color: AppColors.primaryLight),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text(
                                  'Chọn AI Model',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Lựa chọn model AI tự động',
                              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.primaryLight),
                        tooltip: 'Tải lại Models từ mitom.ai',
                        onPressed: () {
                          serverProvider.fetchMitomModels(forceRefresh: true);
                          AppToast.info(context, 'Đang làm mới danh sách Models...');
                        },
                      ),
                      const SizedBox(width: 4),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          hoverColor: AppColors.borderDark.withValues(alpha: 0.6),
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderDark, width: 1),
                            ),
                            child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textDim),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. MODAL BODY
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Column(
                      children: [
                        // Search Input
                        SizedBox(
                          height: 38,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (v) => setState(() => _searchQuery = v),
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                            decoration: InputDecoration(
                              hintText: 'Tìm kiếm AI Model (VD: glm-5.3, gpt-4o, deepseek)...',
                              hintStyle: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                              prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textDim),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      padding: EdgeInsets.zero,
                                      hoverColor: Colors.transparent,
                                      splashColor: Colors.transparent,
                                      icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textDim),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.inputBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(color: AppColors.borderDark),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(color: AppColors.borderDark),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(color: AppColors.primaryLight, width: 1),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // List of models
                        Expanded(
                          child: ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cloud_queue_rounded, size: 14, color: AppColors.primaryLight),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'DANH SÁCH AI MODELS (API-VN-SG.MITOM.AI)',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight, letterSpacing: 0.5),
                                    ),
                                    const Spacer(),
                                    if (serverProvider.isLoadingMitomModels) ...[
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      '${filteredCloudModels.length} models',
                                      style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                                    ),
                                  ],
                                ),
                              ),
                              if (serverProvider.isLoadingMitomModels && filteredCloudModels.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                                    ),
                                  ),
                                ),
                              if (filteredCloudModels.isNotEmpty)
                                ...filteredCloudModels.map((m) {
                                  final isSel = serverProvider.cloudAiModel == m;
                                  IconData icon = Icons.memory_rounded;
                                  if (m.contains('glm')) {
                                    icon = Icons.auto_awesome_rounded;
                                  } else if (m.contains('gpt')) {
                                    icon = Icons.psychology_rounded;
                                  } else if (m.contains('claude')) {
                                    icon = Icons.star_rounded;
                                  } else if (m.contains('gemini')) {
                                    icon = Icons.auto_awesome_rounded;
                                  } else if (m.contains('deepseek')) {
                                    icon = Icons.code_rounded;
                                  }

                                  return _buildModelCard(
                                    title: m,
                                    subtitle: 'Cloud API Model (mitom.ai)',
                                    icon: icon,
                                    isSelected: isSel,
                                    onTap: () {
                                      serverProvider.setCloudAiModel(m);
                                      Navigator.pop(context);
                                      AppToast.success(context, 'Đã chọn Cloud Model: $m');
                                    },
                                  );
                                })
                              else if (!serverProvider.isLoadingMitomModels)
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.search_off_rounded, size: 28, color: AppColors.textDim),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Không tìm thấy model nào khớp với "$_searchQuery"',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                      ),
                                      if (_searchQuery.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: AppColors.primaryLight),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                          icon: const Icon(Icons.add_rounded, size: 14, color: AppColors.primaryLight),
                                          label: Text('Chọn "$_searchQuery" làm model', style: const TextStyle(fontSize: 11.5, color: AppColors.primaryLight)),
                                          onPressed: () {
                                            serverProvider.setActiveAgent(_searchQuery);
                                            Navigator.pop(context);
                                            AppToast.success(context, 'Đã thiết lập model: $_searchQuery');
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

    // 3. Footer Action (Nền tách biệt và border-top)
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF070C18),
        border: Border(
          top: BorderSide(color: AppColors.borderLight, width: 1.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.textDim),
            label: const Text('Nhập model tùy biến khác...', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            onPressed: () {
              Navigator.pop(context);
              ModelPickerDialog.showCustomModelDialog(context, serverProvider);
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ],
      ),
    ),
  ],
),
),
);
      },
    );
  }

  Widget _buildModelCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : AppColors.inputBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppColors.primaryLight : AppColors.textWhite,
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'ĐANG DÙNG',
                                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primaryLight)
                else
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
