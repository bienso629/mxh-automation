import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/services/persona_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/persona_profile_model.dart';
import '../../models/schedule_task_model.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/server_provider.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _viewMode = 'month'; // 'month' | 'day'
  final PersonaService _personaService = PersonaService();
  Map<String, PersonaProfile> _personasMap = {};

  @override
  void initState() {
    super.initState();
    _loadPersonas();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScheduleProvider>().loadTasks();
    });
  }

  Future<void> _loadPersonas() async {
    final list = await _personaService.loadSavedPersonas();
    if (mounted) {
      setState(() {
        _personasMap = list;
      });
    }
  }

  void _prevPeriod() {
    final provider = context.read<ScheduleProvider>();
    if (_viewMode == 'month') {
      setState(() {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
      });
    } else if (_viewMode == 'week') {
      final prevWeek = provider.selectedDate.subtract(const Duration(days: 7));
      provider.setSelectedDate(prevWeek);
      setState(() {
        _currentMonth = DateTime(prevWeek.year, prevWeek.month, 1);
      });
    } else {
      final prevDay = provider.selectedDate.subtract(const Duration(days: 1));
      provider.setSelectedDate(prevDay);
      setState(() {
        _currentMonth = DateTime(prevDay.year, prevDay.month, 1);
      });
    }
  }

  void _nextPeriod() {
    final provider = context.read<ScheduleProvider>();
    if (_viewMode == 'month') {
      setState(() {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
      });
    } else if (_viewMode == 'week') {
      final nextWeek = provider.selectedDate.add(const Duration(days: 7));
      provider.setSelectedDate(nextWeek);
      setState(() {
        _currentMonth = DateTime(nextWeek.year, nextWeek.month, 1);
      });
    } else {
      final nextDay = provider.selectedDate.add(const Duration(days: 1));
      provider.setSelectedDate(nextDay);
      setState(() {
        _currentMonth = DateTime(nextDay.year, nextDay.month, 1);
      });
    }
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _currentMonth = DateTime(now.year, now.month, 1);
    });
    context.read<ScheduleProvider>().setSelectedDate(DateTime(now.year, now.month, now.day));
  }

  String _formatFullDateVN(DateTime date) {
    const weekdayNames = {
      1: 'Thứ 2',
      2: 'Thứ 3',
      3: 'Thứ 4',
      4: 'Thứ 5',
      5: 'Thứ 6',
      6: 'Thứ 7',
      7: 'Chủ Nhật',
    };
    final dayName = weekdayNames[date.weekday] ?? 'Thứ ${date.weekday}';
    final formattedDate = DateFormat('dd/MM/yyyy').format(date);
    return '$dayName, $formattedDate';
  }

  void _showCreateTaskDialog(BuildContext context, {DateTime? initialDate, ScheduleTaskModel? editingTask}) {
    final scheduleProvider = context.read<ScheduleProvider>();
    final isEdit = editingTask != null;
    final targetDate = editingTask?.scheduledTime ?? initialDate ?? scheduleProvider.selectedDate;

    final titleCtrl = TextEditingController(text: editingTask?.title ?? '');
    final urlCtrl = TextEditingController(text: editingTask?.targetUrl ?? '');
    final commentCtrl = TextEditingController(text: editingTask?.commentContent ?? '');
    String taskType = editingTask?.taskType ?? 'like';
    final rawExecutionMode = editingTask?.executionMode.trim() ?? '';
    String executionMode = rawExecutionMode.isNotEmpty ? rawExecutionMode : 'device'; // 'device' | 'browser'
    TimeOfDay selectedTime = editingTask != null
        ? TimeOfDay(hour: editingTask.scheduledTime.hour, minute: editingTask.scheduledTime.minute)
        : (initialDate != null && (initialDate.hour != 0 || initialDate.minute != 0)
            ? TimeOfDay(hour: initialDate.hour, minute: initialDate.minute)
            : TimeOfDay.now());
    DateTime chosenDate = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final selectedIps = <String>{if (editingTask != null) ...editingTask.personaIps};
    bool resetProgressOnSave = false;
    int personaCurrentPage = 1;
    const int personaPageSize = 10;
    final searchPersonaCtrl = TextEditingController();
    String searchPersonaQuery = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final allPersonasRaw = _personasMap.values.toList();
          final allPersonas = searchPersonaQuery.trim().isEmpty
              ? allPersonasRaw
              : allPersonasRaw.where((p) {
                  final q = searchPersonaQuery.trim().toLowerCase();
                  return p.name.toLowerCase().contains(q) || p.ip.toLowerCase().contains(q);
                }).toList();

          return TaduDialog(
            minWidth: 560,
            maxWidth: 680,
            title: Row(
              children: [
                Icon(isEdit ? Icons.edit_calendar_rounded : Icons.add_task_rounded, color: AppColors.primaryLight, size: 22),
                const SizedBox(width: 8),
                Text(isEdit ? 'Chỉnh Sửa Kế Hoạch Tác Vụ' : 'Lên Kế Hoạch Tác Vụ Cho Nhân Vật'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tiêu đề
                  const Text('Tiêu đề kế hoạch:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Ví dụ: Tương tác clip review sản phẩm mới',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Hình thức thực thi: Mở trình duyệt hoặc Mở thiết bị
                  const Text('Phương thức chạy tác vụ:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _buildExecutionModeRadio(
                          'device',
                          'Mở thiết bị',
                          Icons.phone_android_rounded,
                          'Máy ảo AVD hoặc ngoại vi WiFi',
                          executionMode,
                          (v) => setDialogState(() => executionMode = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildExecutionModeRadio(
                          'browser',
                          'Mở trình duyệt',
                          Icons.open_in_browser_rounded,
                          'Chrome profile riêng theo IP',
                          executionMode,
                          (v) => setDialogState(() => executionMode = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Loại tác vụ
                  const Text('Loại hành động tự động:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildTypeRadio('like', 'Bấm Like / Tim', Icons.favorite_rounded, taskType, (v) => setDialogState(() => taskType = v)),
                      _buildTypeRadio('comment', 'Bình luận kịch bản', Icons.mode_comment_rounded, taskType, (v) => setDialogState(() => taskType = v)),
                      _buildTypeRadio('livestream', 'Xem Livestream', Icons.live_tv_rounded, taskType, (v) => setDialogState(() => taskType = v)),
                      _buildTypeRadio('post', 'Đăng bài viết', Icons.post_add_rounded, taskType, (v) => setDialogState(() => taskType = v)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Đường link mục tiêu
                  const Text('Đường dẫn bài viết / video / livestream:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: urlCtrl,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: 'https://www.tiktok.com/@user/video/... hoặc Facebook/Youtube',
                      prefixIcon: Icon(Icons.link_rounded, size: 18),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Nội dung comment / bài viết nếu chọn comment hoặc post
                  if (taskType == 'comment' || taskType == 'post') ...[
                    Text(
                      taskType == 'post'
                          ? 'Nội dung bài viết / caption (tùy chọn):'
                          : 'Nội dung comment (hoặc gợi ý cho AI tự sinh):',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: commentCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: taskType == 'post'
                            ? 'Nhập nội dung bài viết hoặc mô tả video...'
                            : 'Nhập nội dung mẫu hoặc chỉ định phong cách bình luận...',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Thời gian thực thi
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ngày thực hiện:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: dialogCtx,
                                  initialDate: chosenDate,
                                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setDialogState(() => chosenDate = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.inputBg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.borderDark),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.primaryLight),
                                    const SizedBox(width: 8),
                                    Text(DateFormat('dd/MM/yyyy').format(chosenDate), style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Khung giờ bắt đầu:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: dialogCtx,
                                  initialTime: selectedTime,
                                );
                                if (picked != null) {
                                  setDialogState(() => selectedTime = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.inputBg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.borderDark),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primaryLight),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Chọn nhân vật thực hiện kèm phân trang dạng số và multi-select theo trang
                  Builder(
                    builder: (context) {
                      final totalPersonas = allPersonas.length;
                      final totalPages = (totalPersonas / personaPageSize).ceil();
                      final safePage = totalPages == 0 ? 1 : personaCurrentPage.clamp(1, totalPages);
                      final startIndex = (safePage - 1) * personaPageSize;
                      final pagePersonas = allPersonas.skip(startIndex).take(personaPageSize).toList();
                      final allInPageSelected = pagePersonas.isNotEmpty && pagePersonas.every((p) => selectedIps.contains(p.effectiveEntryKey));

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hàng tiêu đề & Công cụ chọn
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Phân bổ nhân vật thực hiện (${selectedIps.length}/$totalPersonas):',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (pagePersonas.isNotEmpty) ...[
                                    InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () {
                                        setDialogState(() {
                                          if (allInPageSelected) {
                                            for (final p in pagePersonas) {
                                              selectedIps.remove(p.effectiveEntryKey);
                                            }
                                          } else {
                                            for (final p in pagePersonas) {
                                              selectedIps.add(p.effectiveEntryKey);
                                            }
                                          }
                                        });
                                      },
                                      child: Container(
                                        height: 28,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: allInPageSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.cardBg,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: allInPageSelected ? AppColors.primaryLight : AppColors.borderDark,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Icon(
                                              allInPageSelected ? Icons.check_box_outlined : Icons.library_add_check_outlined,
                                              size: 14,
                                              color: allInPageSelected ? AppColors.primaryLight : AppColors.textBody,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              allInPageSelected ? 'Bỏ chọn trang này' : 'Chọn trang này',
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.2,
                                                fontWeight: FontWeight.bold,
                                                color: allInPageSelected ? AppColors.primaryLight : AppColors.textBody,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        if (selectedIps.length == totalPersonas) {
                                          selectedIps.clear();
                                        } else {
                                          selectedIps.addAll(allPersonas.map((p) => p.effectiveEntryKey));
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      height: 28,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.6), width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            selectedIps.length == totalPersonas ? Icons.clear_all_rounded : Icons.done_all_rounded,
                                            size: 14,
                                            color: AppColors.primaryLight,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            selectedIps.length == totalPersonas ? 'Bỏ chọn hết' : 'Chọn tất cả',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.2,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primaryLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Ô tìm kiếm nhân vật theo tên hoặc IP
                          Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.inputBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: TextField(
                              controller: searchPersonaCtrl,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: InputDecoration(
                                hintText: 'Tìm kiếm nhân vật theo tên hoặc IP...',
                                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textDim),
                                prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.primaryLight),
                                suffixIcon: searchPersonaQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 14, color: AppColors.textDim),
                                        padding: EdgeInsets.zero,
                                        onPressed: () {
                                          searchPersonaCtrl.clear();
                                          setDialogState(() {
                                            searchPersonaQuery = '';
                                            personaCurrentPage = 1;
                                          });
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                isDense: true,
                              ),
                              onChanged: (val) {
                                setDialogState(() {
                                  searchPersonaQuery = val;
                                  personaCurrentPage = 1;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Bảng danh sách row nhân vật rộng rãi & avatar to
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.inputBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: allPersonas.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.search_off_rounded, size: 28, color: AppColors.textDim.withValues(alpha: 0.6)),
                                          const SizedBox(height: 6),
                                          Text(
                                            searchPersonaQuery.isNotEmpty
                                                ? 'Không tìm thấy nhân vật nào khớp với "$searchPersonaQuery"'
                                                : 'Chưa có nhân vật nào trong hệ thống',
                                            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: pagePersonas.length,
                                    separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.borderDark),
                                    itemBuilder: (context, idx) {
                                      final p = pagePersonas[idx];
                                      final isSelected = selectedIps.contains(p.effectiveEntryKey);
                                      final hasAvatar = p.avatarUrl != null && p.avatarUrl!.isNotEmpty;

                                      return InkWell(
                                        onTap: () {
                                          setDialogState(() {
                                            if (isSelected) {
                                              selectedIps.remove(p.effectiveEntryKey);
                                            } else {
                                              selectedIps.add(p.effectiveEntryKey);
                                            }
                                          });
                                        },
                                        hoverColor: AppColors.primary.withValues(alpha: 0.06),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                                size: 19,
                                                color: isSelected ? AppColors.primaryLight : AppColors.textDim,
                                              ),
                                              const SizedBox(width: 12),

                                              // Avatar to rõ nét (38x38)
                                              Container(
                                                width: 38,
                                                height: 38,
                                                decoration: BoxDecoration(
                                                  color: AppColors.cardBg,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? AppColors.primaryLight
                                                        : (p.gender.toLowerCase() == 'nữ'
                                                            ? Colors.pinkAccent.withValues(alpha: 0.5)
                                                            : AppColors.accentCyan.withValues(alpha: 0.5)),
                                                    width: isSelected ? 1.5 : 1.0,
                                                  ),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(7),
                                                  child: hasAvatar
                                                      ? (p.avatarUrl!.startsWith('http')
                                                          ? Image.network(
                                                              p.avatarUrl!,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (ctx, err, stack) => _buildFallbackAvatar(p),
                                                            )
                                                          : Image.file(
                                                              File(p.avatarUrl!),
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (ctx, err, stack) => _buildFallbackAvatar(p),
                                                            ))
                                                      : _buildFallbackAvatar(p),
                                                ),
                                              ),
                                              const SizedBox(width: 12),

                                              // Thông tin tên, giới tính, tuổi và IP
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            p.name,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                              color: isSelected ? AppColors.textWhite : AppColors.textBody,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                          decoration: BoxDecoration(
                                                            color: p.gender.toLowerCase() == 'nữ'
                                                                ? Colors.pinkAccent.withValues(alpha: 0.15)
                                                                : AppColors.accentCyan.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(3),
                                                          ),
                                                          child: Text(
                                                            '${p.gender} • ${p.age}t',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w600,
                                                              color: p.gender.toLowerCase() == 'nữ'
                                                                  ? Colors.pinkAccent
                                                                  : AppColors.accentCyan,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.public_rounded, size: 12, color: AppColors.textDim),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          p.ip,
                                                          style: const TextStyle(
                                                            fontSize: 11,
                                                            fontFamily: 'monospace',
                                                            color: AppColors.textDim,
                                                          ),
                                                        ),
                                                        if (p.bio.isNotEmpty) ...[
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              p.bio,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 10.5,
                                                                color: AppColors.textMuted,
                                                                fontStyle: FontStyle.italic,
                                                              ),
                                                            ),
                                                          ),
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
                                    },
                                  ),
                          ),

                          // Phân trang
                          if (totalPages > 1) ...[
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                InkWell(
                                  onTap: safePage > 1
                                      ? () => setDialogState(() => personaCurrentPage = safePage - 1)
                                      : null,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: safePage > 1 ? AppColors.cardBg : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: safePage > 1 ? AppColors.borderDark : AppColors.borderDark.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.chevron_left_rounded,
                                          size: 15,
                                          color: safePage > 1 ? AppColors.textBody : AppColors.textDim,
                                        ),
                                        const SizedBox(width: 2),
                                        Text('Trước', style: TextStyle(fontSize: 11, color: safePage > 1 ? AppColors.textBody : AppColors.textDim)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Wrap(
                                  spacing: 4,
                                  children: List.generate(totalPages, (index) {
                                    final pNum = index + 1;
                                    final isCur = pNum == safePage;
                                    return InkWell(
                                      onTap: () => setDialogState(() => personaCurrentPage = pNum),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isCur ? AppColors.primaryLight : AppColors.cardBg,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isCur ? AppColors.primaryLight : AppColors.borderDark,
                                          ),
                                        ),
                                        child: Text(
                                          '$pNum',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: isCur ? FontWeight.bold : FontWeight.w500,
                                            color: isCur ? const Color(0xFF070B14) : AppColors.textBody,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: safePage < totalPages
                                      ? () => setDialogState(() => personaCurrentPage = safePage + 1)
                                      : null,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: safePage < totalPages ? AppColors.cardBg : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: safePage < totalPages ? AppColors.borderDark : AppColors.borderDark.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Sau', style: TextStyle(fontSize: 11, color: safePage < totalPages ? AppColors.textBody : AppColors.textDim)),
                                        const SizedBox(width: 2),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          size: 15,
                                          color: safePage < totalPages ? AppColors.textBody : AppColors.textDim,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  if (isEdit && editingTask.status != 'pending') ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => setDialogState(() => resetProgressOnSave = !resetProgressOnSave),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: resetProgressOnSave ? AppColors.primaryLight : AppColors.borderDark,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              resetProgressOnSave ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              size: 18,
                              color: resetProgressOnSave ? AppColors.primaryLight : AppColors.textDim,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Đặt lại trạng thái về "Đang chờ" và xóa tiến độ cũ để tự chạy lại toàn bộ theo giờ mới',
                                style: TextStyle(fontSize: 11.5, color: AppColors.textBody),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  final url = urlCtrl.text.trim();
                  if (title.isEmpty) {
                    AppToast.warning(dialogCtx, 'Vui lòng nhập tiêu đề kế hoạch');
                    return;
                  }
                  if (url.isEmpty) {
                    AppToast.warning(dialogCtx, 'Vui lòng nhập link bài viết / video');
                    return;
                  }
                  if (selectedIps.isEmpty) {
                    AppToast.warning(dialogCtx, 'Vui lòng chọn ít nhất 1 nhân vật');
                    return;
                  }

                  final scheduledDateTime = DateTime(
                    chosenDate.year,
                    chosenDate.month,
                    chosenDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  );

                  final ok = isEdit
                      ? await scheduleProvider.updateTask(
                          existing: editingTask,
                          title: title,
                          taskType: taskType,
                          executionMode: executionMode,
                          targetUrl: url,
                          commentContent: commentCtrl.text.trim(),
                          personaIps: selectedIps.toList(),
                          scheduledTime: scheduledDateTime,
                          resetToPending: resetProgressOnSave,
                        )
                      : await scheduleProvider.createTask(
                          title: title,
                          taskType: taskType,
                          executionMode: executionMode,
                          targetUrl: url,
                          commentContent: commentCtrl.text.trim(),
                          personaIps: selectedIps.toList(),
                          scheduledTime: scheduledDateTime,
                        );

                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                    if (ok) {
                      setState(() {
                        _currentMonth = DateTime(chosenDate.year, chosenDate.month, 1);
                      });
                      scheduleProvider.setSelectedDate(DateTime(chosenDate.year, chosenDate.month, chosenDate.day));
                      AppToast.success(
                        context,
                        isEdit
                            ? 'Đã cập nhật kế hoạch "$title" thành công'
                            : 'Đã lên lịch thành công cho ${selectedIps.length} nhân vật',
                      );
                    } else {
                      AppToast.error(context, isEdit ? 'Không thể cập nhật kế hoạch' : 'Không thể lưu lịch trình');
                    }
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: Text(isEdit ? 'Lưu Thay Đổi' : 'Lưu Kế Hoạch', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExecutionModeRadio(
    String mode,
    String label,
    IconData icon,
    String subtitle,
    String currentMode,
    Function(String) onSelect,
  ) {
    final isSelected = currentMode == mode;
    return InkWell(
      onTap: () => onSelect(mode),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.cardBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? AppColors.textWhite : AppColors.textBody,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 16,
              color: isSelected ? AppColors.primaryLight : AppColors.textDim,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeRadio(String type, String label, IconData icon, String currentType, Function(String) onSelect) {
    final isSelected = currentType == type;
    return InkWell(
      onTap: () => onSelect(type),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.cardBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? AppColors.primaryLight : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primaryLight : AppColors.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = context.watch<ScheduleProvider>();
    final serverProvider = context.watch<ServerProvider>();

    String headerTitle = '';
    if (_viewMode == 'month') {
      headerTitle = 'Lịch Kế Hoạch MXH (Tháng ${DateFormat('MM/yyyy').format(_currentMonth)})';
    } else if (_viewMode == 'week') {
      final monday = scheduleProvider.selectedDate.subtract(Duration(days: scheduleProvider.selectedDate.weekday - 1));
      final sunday = monday.add(const Duration(days: 6));
      headerTitle = 'Lịch Tuần: ${DateFormat('dd/MM').format(monday)} - ${DateFormat('dd/MM/yyyy').format(sunday)}';
    } else {
      headerTitle = 'Lịch Trình Chi Tiết: ${_formatFullDateVN(scheduleProvider.selectedDate)}';
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Lịch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _viewMode == 'month'
                          ? Icons.calendar_month_rounded
                          : (_viewMode == 'week' ? Icons.view_week_rounded : Icons.view_day_rounded),
                      color: AppColors.primaryLight,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      headerTitle,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Nút chuyển đổi 3 chế độ: Tháng, Tuần, Ngày
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: Row(
                        children: [
                          _buildViewModeButton('month', 'Tháng', Icons.calendar_view_month_rounded),
                          const SizedBox(width: 2),
                          _buildViewModeButton('week', 'Tuần', Icons.view_week_rounded),
                          const SizedBox(width: 2),
                          _buildViewModeButton('day', 'Ngày', Icons.view_day_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textBody),
                      onPressed: _prevPeriod,
                      tooltip: _viewMode == 'month' ? 'Tháng trước' : (_viewMode == 'week' ? 'Tuần trước' : 'Ngày trước'),
                    ),
                    OutlinedButton(
                      onPressed: _goToToday,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: const Text('Hôm nay', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textBody),
                      onPressed: _nextPeriod,
                      tooltip: _viewMode == 'month' ? 'Tháng sau' : (_viewMode == 'week' ? 'Tuần sau' : 'Ngày sau'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateTaskDialog(context, initialDate: scheduleProvider.selectedDate),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Tạo Kế Hoạch Mới', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Banner cảnh báo & khôi phục nhanh khi có tác vụ hẹn giờ bị lỗi / hoàn thành 1 phần / đang chờ thử lại
            if (scheduleProvider.attentionTasks.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Có ${scheduleProvider.attentionTasks.length} tác vụ hẹn giờ chưa hoàn thành 100% (lỗi / hoàn thành 1 phần / đang chờ tự thử lại). '
                        'Hệ thống đã giữ checkpoint các nhân vật đã xong để chạy tiếp phần còn lại.',
                        style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        AppToast.info(context, 'Đang chạy tiếp phần chưa hoàn thành của các tác vụ lỗi...');
                        final count = await scheduleProvider.retryAllFailedOrPartialTasks(
                          defaultServer: serverProvider.selectedServer,
                        );
                        if (context.mounted) {
                          AppToast.info(context, 'Đã xử lý chạy tiếp $count tác vụ.');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: const Color(0xFF070B14),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 15),
                      label: const Text('Chạy tiếp phần lỗi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],

            if (_viewMode == 'month') ...[
              // Bảng ngày trong tuần (T2 - CN)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: Row(
                  children: ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ Nhật'].map((dayName) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          dayName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              // Lưới ngày (Month Days Grid full width)
              Expanded(
                child: _buildMonthCalendarGrid(scheduleProvider),
              ),
            ] else if (_viewMode == 'week') ...[
              // Chế độ xem theo Tuần (Week View Timeline)
              Expanded(
                child: _buildWeekCalendarView(scheduleProvider),
              ),
            ] else ...[
              // Chế độ xem theo ngày với Timeline 24h
              Expanded(
                child: _buildDayTimelineView(scheduleProvider, serverProvider),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeButton(String mode, String label, IconData icon) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () => setState(() => _viewMode = mode),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isSelected ? Border.all(color: AppColors.primaryLight) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? AppColors.primaryLight : AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthCalendarGrid(ScheduleProvider provider) {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    // Thứ trong tuần: DateTime.weekday (1: Monday ... 7: Sunday)
    final startingWeekday = firstDayOfMonth.weekday; // 1 = T2, 7 = CN

    final leadingOffset = startingWeekday - 1;
    final totalDaysWithOffset = leadingOffset + daysInMonth;
    final totalWeeks = (totalDaysWithOffset / 7).ceil();
    final totalSlots = totalWeeks * 7;
    final today = DateTime.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        const double crossAxisSpacing = 6.0;
        const double mainAxisSpacing = 6.0;
        const int crossAxisCount = 7;

        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        // Tính chiều rộng thực của mỗi cột (7 ngày)
        final cellWidth = (availableWidth - (crossAxisSpacing * (crossAxisCount - 1))) / crossAxisCount;

        // Tính chiều cao thực của mỗi hàng (totalWeeks hàng) để vừa khít 100% không cuộn
        final totalMainSpacing = mainAxisSpacing * (totalWeeks - 1);
        final rawCellHeight = (availableHeight - totalMainSpacing) / totalWeeks;
        final cellHeight = rawCellHeight > 0 ? rawCellHeight : 1.0;
        final dynamicAspectRatio = (cellWidth > 0 && cellHeight > 0) ? (cellWidth / cellHeight) : 1.0;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            childAspectRatio: dynamicAspectRatio,
          ),
          itemCount: totalSlots,
          itemBuilder: (context, index) {
        final dayOffset = index - (startingWeekday - 1);
        if (dayOffset < 0 || dayOffset >= daysInMonth) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }

        final dayNumber = dayOffset + 1;
        final cellDate = DateTime(_currentMonth.year, _currentMonth.month, dayNumber);
        final isToday = cellDate.year == today.year && cellDate.month == today.month && cellDate.day == today.day;
        final isSelected = cellDate.year == provider.selectedDate.year &&
            cellDate.month == provider.selectedDate.month &&
            cellDate.day == provider.selectedDate.day;

        // Đếm số tác vụ trong ngày này
        final dayTasks = provider.tasks.where((t) {
          return t.scheduledTime.year == cellDate.year &&
              t.scheduledTime.month == cellDate.month &&
              t.scheduledTime.day == cellDate.day;
        }).toList();

        return InkWell(
          onTap: () {
            provider.setSelectedDate(cellDate);
            _showDayTasksDialog(context, cellDate);
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : (isToday ? AppColors.primaryLight.withValues(alpha: 0.05) : AppColors.cardBg),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : (isToday ? AppColors.primaryLight.withValues(alpha: 0.4) : AppColors.borderDark),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? AppColors.primaryLight
                            : (isToday ? AppColors.primaryLight : AppColors.textWhite),
                      ),
                    ),
                    if (dayTasks.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${dayTasks.length}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (dayTasks.isNotEmpty) ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...dayTasks.take(2).map((t) {
                          Color tagColor = AppColors.primaryLight;
                          if (t.taskType == 'comment') tagColor = AppColors.accentCyan;
                          if (t.taskType == 'livestream') tagColor = Colors.purpleAccent;
                          if (t.taskType == 'post') tagColor = AppColors.accent;

                          final timeStr = DateFormat('HH:mm').format(t.scheduledTime);
                          final taskLabel = t.title.trim().isNotEmpty ? t.title.trim() : t.taskType;

                          return InkWell(
                            onTap: () => _showTaskDetailDialog(context, t),
                            borderRadius: BorderRadius.circular(3),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: tagColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: tagColor.withValues(alpha: 0.35), width: 0.5),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      color: tagColor,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      taskLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textWhite.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _statusDotColor(t.status),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (dayTasks.length > 2)
                          Padding(
                            padding: const EdgeInsets.only(left: 2, top: 1),
                            child: Text(
                              '+${dayTasks.length - 2} tác vụ khác',
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: AppColors.textMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        );
      },
    );
      },
    );
  }

  Widget _buildDayTimelineView(ScheduleProvider provider, ServerProvider serverProvider) {
    final selectedDate = provider.selectedDate;
    final allDayTasks = provider.tasks.where((t) {
      return t.scheduledTime.year == selectedDate.year &&
          t.scheduledTime.month == selectedDate.month &&
          t.scheduledTime.day == selectedDate.day;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        children: [
          // Header tóm tắt ngày
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderDark)),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 18, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Text(
                  'Dòng thời gian 24 giờ (${allDayTasks.length} tác vụ)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
                const Spacer(),
                Text(
                  'Nhấp vào khung giờ bất kỳ để tạo tác vụ mới',
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ],
            ),
          ),

          // Danh sách 24 khung giờ
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: 24,
              itemBuilder: (context, hour) {
                final hourTasks = allDayTasks.where((t) => t.scheduledTime.hour == hour).toList();
                final hourStr = '${hour.toString().padLeft(2, '0')}:00';
                final isCurrentHour = DateTime.now().year == selectedDate.year &&
                    DateTime.now().month == selectedDate.month &&
                    DateTime.now().day == selectedDate.day &&
                    DateTime.now().hour == hour;

                return InkWell(
                  onTap: () {
                    _showCreateTaskDialog(
                      context,
                      initialDate: DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        hour,
                        0,
                      ),
                    );
                  },
                  hoverColor: AppColors.primary.withValues(alpha: 0.05),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrentHour ? AppColors.primary.withValues(alpha: 0.05) : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.borderDark.withValues(alpha: 0.5),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cột mốc giờ
                        SizedBox(
                          width: 55,
                          child: Text(
                            hourStr,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: isCurrentHour ? FontWeight.bold : FontWeight.w500,
                              color: isCurrentHour ? AppColors.primaryLight : AppColors.textMuted,
                            ),
                          ),
                        ),

                        // Cột hiển thị tác vụ trong khung giờ
                        Expanded(
                          child: hourTasks.isEmpty
                              ? const SizedBox(
                                  height: 24,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '-- trống --',
                                      style: TextStyle(fontSize: 11, color: AppColors.textDim),
                                    ),
                                  ),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: hourTasks.map((t) {
                                    Color tagColor = AppColors.primaryLight;
                                    IconData iconData = Icons.favorite_rounded;
                                    if (t.taskType == 'comment') {
                                      tagColor = AppColors.accentCyan;
                                      iconData = Icons.mode_comment_rounded;
                                    } else if (t.taskType == 'livestream') {
                                      tagColor = Colors.purpleAccent;
                                      iconData = Icons.live_tv_rounded;
                                    } else if (t.taskType == 'post') {
                                      tagColor = AppColors.accent;
                                      iconData = Icons.post_add_rounded;
                                    }

                                    final timeStr = DateFormat('HH:mm').format(t.scheduledTime);
                                    final isRunning = t.status == 'running';

                                    return InkWell(
                                      onTap: () => _showTaskDetailDialog(context, t),
                                      borderRadius: BorderRadius.circular(5),
                                      child: Container(
                                        constraints: const BoxConstraints(maxWidth: 280),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: tagColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(
                                            color: isRunning ? AppColors.primaryLight : tagColor.withValues(alpha: 0.4),
                                            width: isRunning ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(iconData, size: 14, color: tagColor),
                                            const SizedBox(width: 6),
                                            Text(
                                              timeStr,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                                color: tagColor,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                t.title.trim().isNotEmpty ? t.title.trim() : t.taskType,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textWhite,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: (t.executionMode == 'device' ? Colors.purpleAccent : AppColors.accentCyan).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Icon(
                                                t.executionMode == 'device' ? Icons.phone_android_rounded : Icons.open_in_browser_rounded,
                                                size: 11,
                                                color: t.executionMode == 'device' ? Colors.purpleAccent : AppColors.accentCyan,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            _buildStatusBadge(t.status),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekCalendarView(ScheduleProvider provider) {
    final selectedDate = provider.selectedDate;
    // Tính ngày Thứ 2 đầu tuần (weekday: 1=Mon, 7=Sun)
    final monday = selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));
    final today = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        children: [
          // Header các ngày trong tuần (T2 - CN kèm ngày tháng)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderDark)),
            ),
            child: Row(
              children: [
                // Khoảng trống căn chỉnh cột giờ
                const SizedBox(width: 60),
                ...weekDays.map((day) {
                  const dayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
                  final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
                  final isSelected = day.year == selectedDate.year && day.month == selectedDate.month && day.day == selectedDate.day;

                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        provider.setSelectedDate(day);
                        _showDayTasksDialog(context, day);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: isSelected ? Border.all(color: AppColors.primaryLight, width: 1) : null,
                        ),
                        child: Column(
                          children: [
                            Text(
                              dayNames[day.weekday - 1],
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isToday ? AppColors.primaryLight : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('dd/MM').format(day),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: (isToday || isSelected) ? FontWeight.bold : FontWeight.w500,
                                color: (isToday || isSelected) ? AppColors.primaryLight : AppColors.textWhite,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // Lưới timeline 24 giờ của 7 ngày trong tuần
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: 24,
              itemBuilder: (context, hour) {
                final hourStr = '${hour.toString().padLeft(2, '0')}:00';

                return Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.borderDark.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cột mốc giờ
                      SizedBox(
                        width: 60,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10, top: 8),
                          child: Text(
                            hourStr,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                      // 7 cột tương ứng 7 ngày
                      ...weekDays.map((day) {
                        final cellTasks = provider.tasks.where((t) {
                          return t.scheduledTime.year == day.year &&
                              t.scheduledTime.month == day.month &&
                              t.scheduledTime.day == day.day &&
                              t.scheduledTime.hour == hour;
                        }).toList();

                        final isTodayCell = day.year == today.year &&
                            day.month == today.month &&
                            day.day == today.day &&
                            today.hour == hour;

                        return Expanded(
                          child: InkWell(
                            onTap: () {
                              _showCreateTaskDialog(
                                context,
                                initialDate: DateTime(day.year, day.month, day.day, hour, 0),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isTodayCell ? AppColors.primary.withValues(alpha: 0.05) : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: AppColors.borderDark.withValues(alpha: 0.3),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: cellTasks.map((t) {
                                  Color tagColor = AppColors.primaryLight;
                                  if (t.taskType == 'comment') tagColor = AppColors.accentCyan;
                                  if (t.taskType == 'livestream') tagColor = Colors.purpleAccent;
                                  if (t.taskType == 'post') tagColor = AppColors.accent;

                                  final timeStr = DateFormat('HH:mm').format(t.scheduledTime);
                                  final label = t.title.trim().isNotEmpty ? t.title.trim() : t.taskType;

                                  return InkWell(
                                    onTap: () => _showTaskDetailDialog(context, t),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 3),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: tagColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: tagColor.withValues(alpha: 0.4), width: 0.5),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.bold,
                                              color: tagColor,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: AppColors.textWhite,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _statusDotColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.accent;
      case 'running':
        return AppColors.primaryLight;
      case 'retrying':
      case 'partial':
        return AppColors.warning;
      case 'failed':
        return AppColors.danger;
      case 'cancelled':
        return AppColors.textDim;
      default:
        return AppColors.textMuted;
    }
  }

  void _showTaskOutcomeToast(BuildContext context, ScheduleTaskModel? result) {
    if (!context.mounted || result == null) return;
    if (result.status == 'completed') {
      AppToast.success(context, 'Tác vụ đã hoàn tất 100% (${result.completedIps.length}/${result.personaIps.length} nhân vật)');
    } else if (result.status == 'retrying') {
      AppToast.warning(context, 'Còn ${result.remainingIps.length} nhân vật lỗi. Hệ thống đã hẹn tự thử lại.');
    } else if (result.status == 'partial') {
      AppToast.warning(context, 'Hoàn thành 1 phần (${result.completedIps.length}/${result.personaIps.length}). Đã gửi cảnh báo.');
    } else if (result.status == 'failed') {
      AppToast.error(context, 'Tác vụ thất bại. Đã gửi cảnh báo.');
    }
  }

  /// Bật dialog chi tiết danh sách công việc trong một ngày cụ thể để xem, tinh chỉnh, chạy tiếp, chạy lại hoặc xóa
  void _showDayTasksDialog(BuildContext context, DateTime date) {
    final serverProvider = context.read<ServerProvider>();
    final dayLabel = _formatFullDateVN(date);

    showDialog(
      context: context,
      builder: (ctx) => Consumer<ScheduleProvider>(
        builder: (dialogCtx, scheduleProvider, _) {
          final dayTasks = scheduleProvider.tasks.where((t) {
            return t.scheduledTime.year == date.year &&
                t.scheduledTime.month == date.month &&
                t.scheduledTime.day == date.day;
          }).toList()
            ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

          final attentionCount = dayTasks.where((t) => t.needsAttention).length;

          return TaduDialog(
            minWidth: 620,
            maxWidth: 760,
            title: Row(
              children: [
                const Icon(Icons.event_note_rounded, color: AppColors.primaryLight, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Công Việc Ngày $dayLabel (${dayTasks.length})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: dayTasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_available_rounded,
                            size: 38,
                            color: AppColors.textDim.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Chưa có công việc nào được lên lịch cho $dayLabel.',
                            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              _showCreateTaskDialog(context, initialDate: date);
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Tạo Kế Hoạch Cho Ngày Này', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (attentionCount > 0) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Có $attentionCount công việc chưa xong 100% trong ngày này.',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  AppToast.info(context, 'Đang chạy tiếp phần lỗi trong ngày $dayLabel...');
                                  for (final t in dayTasks.where((e) => e.needsAttention)) {
                                    await scheduleProvider.resumeTask(t, defaultServer: serverProvider.selectedServer);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: const Color(0xFF070B14),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                                icon: const Icon(Icons.play_arrow_rounded, size: 15),
                                label: const Text('Chạy tiếp tất cả lỗi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      ...dayTasks.map((t) => _buildDayDialogTaskItem(context, dialogCtx, t, scheduleProvider, serverProvider)),
                    ],
                  ),
            leadingActions: [
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _showCreateTaskDialog(context, initialDate: date);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  backgroundColor: AppColors.cardBg,
                  side: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('Thêm công việc', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Đóng', style: TextStyle(color: AppColors.textMuted)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDayDialogTaskItem(
    BuildContext rootContext,
    BuildContext dialogCtx,
    ScheduleTaskModel task,
    ScheduleProvider scheduleProvider,
    ServerProvider serverProvider,
  ) {
    final isRunning = task.status == 'running';
    final isQueued = scheduleProvider.isTaskQueuedForResource(task.id);
    final isRetrying = task.status == 'retrying';
    final isCompleted = task.status == 'completed';
    final hasResumeWork =
        (task.status == 'partial' || task.status == 'failed' || task.status == 'retrying' || task.status == 'cancelled') &&
            task.hasCheckpointProgress;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.sidebarBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isRunning
              ? AppColors.primaryLight
              : (task.needsAttention ? AppColors.warning.withValues(alpha: 0.5) : AppColors.borderDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTaskCard(dialogCtx, task),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.borderDark),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: isRunning
                    ? null
                    : () => _showCreateTaskDialog(rootContext, editingTask: task),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textWhite,
                  backgroundColor: AppColors.cardBg,
                  side: const BorderSide(color: AppColors.borderLight),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: isRunning ? AppColors.textDim : AppColors.primaryLight,
                ),
                label: const Text('Chỉnh sửa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (hasResumeWork && !isRunning)
                ElevatedButton.icon(
                  onPressed: () async {
                    AppToast.info(rootContext, 'Đang chạy tiếp ${task.remainingIps.length} nhân vật chưa xong...');
                    final res = await scheduleProvider.resumeTask(
                      task,
                      defaultServer: serverProvider.selectedServer,
                    );
                    if (rootContext.mounted) {
                      _showTaskOutcomeToast(rootContext, res);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF070B14),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 15),
                  label: Text(
                    'Chạy tiếp (${task.remainingIps.length} lỗi)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: isRunning
                    ? null
                    : () async {
                        AppToast.info(rootContext, 'Bắt đầu thực thi "${task.title}"...');
                        final res = (isCompleted || hasResumeWork)
                            ? await scheduleProvider.restartTaskFromScratch(
                                task,
                                defaultServer: serverProvider.selectedServer,
                              )
                            : await scheduleProvider.executeTaskNow(
                                task,
                                defaultServer: serverProvider.selectedServer,
                              );
                        if (rootContext.mounted) {
                          _showTaskOutcomeToast(rootContext, res);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (isCompleted || hasResumeWork) ? AppColors.cardBg : AppColors.primary,
                  foregroundColor: (isCompleted || hasResumeWork) ? AppColors.textWhite : const Color(0xFF070B14),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: (isCompleted || hasResumeWork) ? const BorderSide(color: AppColors.borderLight) : BorderSide.none,
                  ),
                ),
                icon: isRunning
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                    : Icon((isCompleted || hasResumeWork) ? Icons.replay_rounded : Icons.play_arrow_rounded, size: 15),
                label: Text(
                  isRunning
                      ? (isQueued ? 'Đang xếp hàng...' : 'Đang chạy...')
                      : ((isCompleted || hasResumeWork) ? 'Chạy lại toàn bộ' : 'Chạy ngay'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              if (isRunning || isRetrying)
                OutlinedButton.icon(
                  onPressed: () async {
                    await scheduleProvider.cancelOrResetStuckTask(task, resetToPending: false);
                    if (rootContext.mounted) {
                      AppToast.warning(rootContext, 'Đã dừng / gỡ kẹt "${task.title}".');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    backgroundColor: AppColors.danger.withValues(alpha: 0.08),
                    side: BorderSide(color: AppColors.danger.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 14),
                  label: const Text('Gỡ kẹt / Dừng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (task.id != null) {
                    await scheduleProvider.deleteTask(task.id!);
                    if (rootContext.mounted) {
                      AppToast.info(rootContext, 'Đã xóa công việc "${task.title}"');
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  backgroundColor: AppColors.danger.withValues(alpha: 0.06),
                  side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.danger),
                label: const Text('Xóa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTaskDetailDialog(BuildContext context, ScheduleTaskModel initialTask) {
    final serverProvider = context.read<ServerProvider>();

    showDialog(
      context: context,
      builder: (ctx) => Consumer<ScheduleProvider>(
        builder: (dialogCtx, scheduleProvider, _) {
          final task = scheduleProvider.getTaskById(initialTask.id) ?? initialTask;
          final isCompleted = task.status == 'completed';
          final isRunning = task.status == 'running';
          final isQueued = scheduleProvider.isTaskQueuedForResource(task.id);
          final isRetrying = task.status == 'retrying';
          final hasResumeWork = (task.status == 'partial' || task.status == 'failed' || task.status == 'retrying' || task.status == 'cancelled') &&
              task.hasCheckpointProgress;

          return TaduDialog(
            minWidth: 560,
            maxWidth: 680,
            title: const Row(
              children: [
                Icon(Icons.assignment_rounded, color: AppColors.primaryLight, size: 22),
                SizedBox(width: 8),
                Text('Chi Tiết Tác Vụ Lịch Trình'),
              ],
            ),
            content: _buildTaskCard(dialogCtx, task),
            leadingActions: [
              Tooltip(
                message: 'Xóa tác vụ',
                child: OutlinedButton(
                  onPressed: () async {
                    if (task.id != null) {
                      await scheduleProvider.deleteTask(task.id!);
                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                      }
                      if (context.mounted) {
                        AppToast.info(context, 'Đã xóa tác vụ lịch trình');
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    backgroundColor: AppColors.danger.withValues(alpha: 0.06),
                    side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    minimumSize: const Size(40, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                ),
              ),
              if (!isRunning)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _showCreateTaskDialog(context, editingTask: task);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textWhite,
                    backgroundColor: AppColors.cardBg,
                    side: const BorderSide(color: AppColors.borderLight),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 14, color: AppColors.primaryLight),
                  label: const Text('Chỉnh sửa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              if (isRunning || isRetrying)
                OutlinedButton.icon(
                  onPressed: () async {
                    await scheduleProvider.cancelOrResetStuckTask(task, resetToPending: false);
                    if (context.mounted) {
                      AppToast.warning(context, 'Đã dừng / gỡ kẹt tác vụ.');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    backgroundColor: AppColors.danger.withValues(alpha: 0.08),
                    side: BorderSide(color: AppColors.danger.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 14),
                  label: const Text('Gỡ kẹt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Đóng', style: TextStyle(color: AppColors.textMuted)),
              ),
              if (hasResumeWork && !isRunning)
                ElevatedButton.icon(
                  onPressed: () async {
                    AppToast.info(context, 'Đang chạy tiếp ${task.remainingIps.length} nhân vật chưa xong...');
                    final res = await scheduleProvider.resumeTask(
                      task,
                      defaultServer: serverProvider.selectedServer,
                    );
                    if (context.mounted) {
                      _showTaskOutcomeToast(context, res);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF070B14),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 15),
                  label: Text(
                    'Chạy tiếp (${task.remainingIps.length})',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: isRunning
                    ? null
                    : () async {
                        AppToast.info(context, 'Bắt đầu thực thi tác vụ cho các nhân vật...');
                        final res = (isCompleted || hasResumeWork)
                            ? await scheduleProvider.restartTaskFromScratch(
                                task,
                                defaultServer: serverProvider.selectedServer,
                              )
                            : await scheduleProvider.executeTaskNow(
                                task,
                                defaultServer: serverProvider.selectedServer,
                              );
                        if (context.mounted) {
                          _showTaskOutcomeToast(context, res);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (isCompleted || hasResumeWork) ? AppColors.cardBg : AppColors.primary,
                  foregroundColor: (isCompleted || hasResumeWork) ? AppColors.textWhite : const Color(0xFF070B14),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: (isCompleted || hasResumeWork) ? const BorderSide(color: AppColors.borderLight) : BorderSide.none,
                  ),
                ),
                icon: isRunning
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                    : Icon((isCompleted || hasResumeWork) ? Icons.replay_rounded : Icons.play_arrow_rounded, size: 15),
                label: Text(
                  isRunning
                      ? (isQueued ? 'Đang xếp hàng...' : 'Đang chạy...')
                      : ((isCompleted || hasResumeWork) ? 'Chạy lại' : 'Kích hoạt ngay'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    ScheduleTaskModel task,
  ) {
    Color typeColor = AppColors.primaryLight;
    IconData typeIcon = Icons.favorite_rounded;
    String typeLabel = 'Like / Tim';

    if (task.taskType == 'comment') {
      typeColor = AppColors.accentCyan;
      typeIcon = Icons.mode_comment_rounded;
      typeLabel = 'Bình luận';
    } else if (task.taskType == 'livestream') {
      typeColor = Colors.purpleAccent;
      typeIcon = Icons.live_tv_rounded;
      typeLabel = 'Xem Livestream';
    } else if (task.taskType == 'post') {
      typeColor = AppColors.accent;
      typeIcon = Icons.post_add_rounded;
      typeLabel = 'Đăng bài';
    }

    final isCompleted = task.status == 'completed';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: typeColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(typeIcon, size: 12, color: typeColor),
                  const SizedBox(width: 4),
                  Text(typeLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: typeColor)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: (task.executionMode == 'device' ? Colors.purpleAccent : AppColors.accentCyan).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: (task.executionMode == 'device' ? Colors.purpleAccent : AppColors.accentCyan).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    task.executionMode == 'device' ? Icons.phone_android_rounded : Icons.open_in_browser_rounded,
                    size: 11,
                    color: task.executionMode == 'device' ? Colors.purpleAccent : AppColors.accentCyan,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    task.executionMode == 'device' ? 'Thiết bị' : 'Trình duyệt',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: task.executionMode == 'device' ? Colors.purpleAccent : AppColors.accentCyan,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('HH:mm').format(task.scheduledTime),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.textWhite),
            ),
            const Spacer(),
            _buildStatusBadge(
              task.status,
              isQueued: context.read<ScheduleProvider>().isTaskQueuedForResource(task.id),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Text(
          task.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
        ),
        const SizedBox(height: 6),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.borderDark),
          ),
          child: Row(
            children: [
              const Icon(Icons.link_rounded, size: 14, color: AppColors.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  task.targetUrl,
                  style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.primaryLight),
                ),
              ),
            ],
          ),
        ),

        if (task.commentContent != null && task.commentContent!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.sidebarBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nội dung bình luận:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  task.commentContent!,
                  style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),
        // Tiến độ checkpoint & danh sách nhân vật (xanh = xong, đỏ = lỗi, xám = chờ)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tiến độ: ${task.completedIps.length}/${task.personaIps.length} nhân vật hoàn thành'
              '${task.failedIps.isNotEmpty ? ' • ${task.failedIps.length} lỗi' : ''}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
            ),
            if (task.retryCount > 0 || task.status == 'retrying')
              Text(
                'Thử lại: ${task.retryCount}/${task.maxRetries}'
                '${task.nextRetryAt != null ? ' (lúc ${DateFormat('HH:mm').format(task.nextRetryAt!)})' : ''}',
                style: const TextStyle(fontSize: 10.5, color: AppColors.warning, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        if (task.personaIps.isNotEmpty) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (task.completedIps.length / task.personaIps.length).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.inputBg,
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted
                    ? AppColors.accent
                    : (task.status == 'failed' ? AppColors.danger : AppColors.warning),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${task.personaIps.length} nhân vật tham gia: ',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            Expanded(
              child: SizedBox(
                height: 24,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: task.personaIps.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 5),
                  itemBuilder: (context, pIdx) {
                    final key = task.personaIps[pIdx];
                    final p = _personasMap[key] ?? _personasMap[key.split('##').first];
                    final initial = (p != null && p.name.isNotEmpty) ? p.name[0].toUpperCase() : '?';
                    final isDoneP = task.completedIps.contains(key);
                    final isFailP = task.failedIps.contains(key);
                    final statusLabel = isDoneP ? 'Đã xong' : (isFailP ? 'Lỗi' : 'Chưa chạy');
                    final badgeColor = isDoneP
                        ? AppColors.accent
                        : (isFailP ? AppColors.danger : AppColors.primaryLight);
                    return Tooltip(
                      message: '${p != null ? '${p.name} (${p.ip})' : key} — $statusLabel',
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: badgeColor.withValues(alpha: 0.2),
                        child: Text(initial, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),

        if (task.resultNote != null && task.resultNote!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isCompleted
                      ? AppColors.accent
                      : (task.status == 'failed' ? AppColors.danger : AppColors.warning))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (isCompleted
                        ? AppColors.accent
                        : (task.status == 'failed' ? AppColors.danger : AppColors.warning))
                    .withValues(alpha: 0.3),
              ),
            ),
            child: SelectableText(
              task.resultNote!,
              style: TextStyle(
                fontSize: 11.5,
                color: isCompleted
                    ? AppColors.accent
                    : (task.status == 'failed' ? AppColors.danger : AppColors.warning),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusBadge(String status, {bool isQueued = false}) {
    Color bg = AppColors.bgDark;
    Color fg = AppColors.textMuted;
    String label = 'Đang chờ';

    if (isQueued && status == 'running') {
      bg = AppColors.accentCyan.withValues(alpha: 0.16);
      fg = AppColors.accentCyan;
      label = 'Đang xếp hàng';
    } else if (status == 'running') {
      bg = AppColors.primary.withValues(alpha: 0.2);
      fg = AppColors.primaryLight;
      label = 'Đang chạy';
    } else if (status == 'retrying') {
      bg = AppColors.warning.withValues(alpha: 0.18);
      fg = AppColors.warning;
      label = 'Chờ thử lại';
    } else if (status == 'partial') {
      bg = AppColors.warning.withValues(alpha: 0.18);
      fg = AppColors.warning;
      label = 'Xong 1 phần';
    } else if (status == 'completed') {
      bg = AppColors.accent.withValues(alpha: 0.15);
      fg = AppColors.accent;
      label = 'Hoàn tất';
    } else if (status == 'failed') {
      bg = AppColors.danger.withValues(alpha: 0.15);
      fg = AppColors.danger;
      label = 'Thất bại';
    } else if (status == 'cancelled') {
      bg = AppColors.textDim.withValues(alpha: 0.15);
      fg = AppColors.textDim;
      label = 'Đã hủy';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildFallbackAvatar(PersonaProfile p) {
    final isFemale = p.gender.toLowerCase() == 'nữ';
    return Container(
      color: isFemale
          ? Colors.pinkAccent.withValues(alpha: 0.25)
          : AppColors.accentCyan.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: Text(
        p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isFemale ? Colors.pinkAccent : AppColors.accentCyan,
        ),
      ),
    );
  }
}

