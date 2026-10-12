import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TaduDialog extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget>? actions;
  final List<Widget>? leadingActions;
  final double minWidth;
  final double maxWidth;
  final double? maxHeight;
  final VoidCallback? onClose;

  final EdgeInsetsGeometry? contentPadding;

  const TaduDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.leadingActions,
    this.minWidth = 500,
    this.maxWidth = 620,
    this.maxHeight,
    this.contentPadding,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderLight, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. MODAL HEADER (Phân tách rõ rệt với nền riêng và border-bottom sắc nét)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF090F1E), // Nền xanh đen sâu riêng biệt cho header
                border: Border(
                  bottom: BorderSide(color: AppColors.borderLight, width: 1.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textWhite,
                      ),
                      child: title,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      hoverColor: AppColors.borderDark.withValues(alpha: 0.6),
                      onTap: onClose ?? () => Navigator.pop(context),
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

            // 2. MODAL BODY (Scrollable if needed)
            Flexible(
              child: Builder(
                builder: (context) {
                  final scrollCtrl = ScrollController();
                  return Scrollbar(
                    controller: scrollCtrl,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    radius: const Radius.circular(4),
                    thickness: 6,
                    child: SingleChildScrollView(
                      controller: scrollCtrl,
                      padding: contentPadding ?? const EdgeInsets.all(20),
                      child: content,
                    ),
                  );
                },
              ),
            ),

            // 3. MODAL FOOTER (Phân tách rõ rệt với nền sidebarBg và border-top)
            if ((actions != null && actions!.isNotEmpty) || (leadingActions != null && leadingActions!.isNotEmpty))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF070C18), // Nền tối phân cách cho footer
                  border: Border(
                    top: BorderSide(color: AppColors.borderLight, width: 1.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Bên trái: leadingActions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (leadingActions != null)
                          for (int i = 0; i < leadingActions!.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            leadingActions![i],
                          ],
                      ],
                    ),
                    // Bên phải: actions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (actions != null)
                          for (int i = 0; i < actions!.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            actions![i],
                          ],
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
