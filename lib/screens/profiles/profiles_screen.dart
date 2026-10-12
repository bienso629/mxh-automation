import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../core/services/persona_service.dart';
import '../../core/services/socks5_proxy_service.dart';
import '../../core/services/smspool_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/persona_profile_model.dart';
import '../../models/server_model.dart';
import '../../providers/server_provider.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final Set<String> _openingIps = {};
  final Set<String> _closingIps = {};
  final Set<String> _openingDeviceIps = {};
  final Set<String> _closingDeviceIps = {};
  final Set<String> _generatingAvatarIps = {};
  final Set<String> _generatingSingleProfileIps = {};
  final Socks5ProxyService _socks5Service = Socks5ProxyService();
  final PersonaService _personaService = PersonaService();

  Map<String, PersonaProfile> _personas = {};
  bool _isGeneratingPersonas = false;
  bool _isRepairing = false;
  Set<String> _availableAvds = {};

  @override
  void initState() {
    super.initState();
    _loadPersonas();
  }

  Future<void> _loadPersonas({bool forceReload = false}) async {
    final saved = await _personaService.loadSavedPersonas(forceReload: forceReload);
    List<String> avdList = [];
    try {
      avdList = await _socks5Service.getAvailableAvds();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _personas = Map.from(saved);
        _availableAvds = avdList.toSet();
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success(context, 'Đã sao chép $label: $text');
  }

  Future<void> _handleGeneratePersonas(List<String> targetIps) async {
    if (targetIps.isEmpty) {
      AppToast.warning(context, 'Không có địa chỉ IP nào để tạo profiles');
      return;
    }

    setState(() {
      _isGeneratingPersonas = true;
    });
    AppToast.info(context, 'AI Agent đang phân tích và tạo hồ sơ nhân vật cho ${targetIps.length} IP...');

    try {
      final newPersonas = await _personaService.generatePersonas(ips: targetIps);
      if (mounted) {
        setState(() {
          _personas.addAll(newPersonas);
        });
        AppToast.success(context, 'AI đã tạo thành công hồ sơ cho ${newPersonas.length} IP');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi tạo profiles bằng AI: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPersonas = false;
        });
      }
    }
  }

  Future<void> _handleGenerateSinglePersona(String ip) async {
    if (_generatingSingleProfileIps.contains(ip) || _isGeneratingPersonas) return;

    setState(() {
      _generatingSingleProfileIps.add(ip);
    });
    AppToast.info(context, 'AI đang tạo hồ sơ nhân vật cho IP $ip...');

    try {
      final newPersonas = await _personaService.generatePersonas(ips: [ip]);
      if (mounted && newPersonas.isNotEmpty) {
        setState(() {
          _personas.addAll(newPersonas);
        });
        final created = newPersonas[ip];
        final name = created?.name ?? ip;
        AppToast.success(context, 'AI đã tạo thành công nhân vật "$name" cho IP $ip');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi tạo profile cho IP $ip: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingSingleProfileIps.remove(ip);
        });
      }
    }
  }

  Future<void> _handleGenerateAvatar(PersonaProfile persona, {void Function(void Function())? setModalState}) async {
    if (_generatingAvatarIps.contains(persona.ip)) return;

    setState(() {
      _generatingAvatarIps.add(persona.ip);
    });
    setModalState?.call(() {});
    AppToast.info(context, 'AI đang vẽ avatar cho nhân vật ${persona.name} (${persona.ip})...');

    try {
      final avatarPathOrUrl = await _personaService.generateAvatarImage(persona);
      if (mounted) {
        final current = _personas[persona.ip] ?? persona;
        final updated = current.copyWith(avatarUrl: avatarPathOrUrl);
        setState(() {
          _personas[persona.ip] = updated;
        });
        setModalState?.call(() {});
        AppToast.success(context, 'Đã tạo xong avatar AI cho ${persona.name}!');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi khi tạo avatar AI: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingAvatarIps.remove(persona.ip);
        });
        setModalState?.call(() {});
      }
    }
  }

  void _showAvatarPreviewDialog(PersonaProfile persona, {void Function(void Function())? setModalState}) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setPreviewState) {
            final currentP = _personas[persona.ip] ?? persona;
            final hasAvatar = currentP.avatarUrl != null && currentP.avatarUrl!.isNotEmpty;
            final isGenerating = _generatingAvatarIps.contains(currentP.ip);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderDark, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header dialog
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: const BoxDecoration(
                        color: AppColors.sidebarBg,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                        border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.account_box_rounded, size: 18, color: AppColors.primaryLight),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentP.name,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${currentP.gender} • ${currentP.age} tuổi • IP: ${currentP.ip}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textDim),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            tooltip: 'Đóng',
                          ),
                        ],
                      ),
                    ),

                    // Body: Avatar Preview phóng to rõ nét
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 500,
                              height: 500,
                              color: AppColors.inputBg,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (hasAvatar)
                                    InteractiveViewer(
                                      maxScale: 4.0,
                                      minScale: 1.0,
                                      child: currentP.avatarUrl!.startsWith('http')
                                          ? Image.network(
                                              currentP.avatarUrl!,
                                              key: ValueKey(currentP.avatarUrl),
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => Center(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.broken_image_rounded, size: 48, color: AppColors.textDim),
                                                    const SizedBox(height: 8),
                                                    Text('Không thể tải ảnh: $e', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : Image.file(
                                              File(currentP.avatarUrl!),
                                              key: ValueKey(currentP.avatarUrl),
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => Center(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.broken_image_rounded, size: 48, color: AppColors.textDim),
                                                    const SizedBox(height: 8),
                                                    Text('Không tìm thấy tệp ảnh', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                    )
                                  else
                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            currentP.gender.toLowerCase() == 'nữ' ? Icons.face_3_rounded : Icons.face_rounded,
                                            size: 72,
                                            color: AppColors.primaryLight.withValues(alpha: 0.6),
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Chưa có ảnh chân dung avatar',
                                            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (isGenerating)
                                    Container(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      child: const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primaryLight),
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              'AI đang tạo ảnh avatar mới...',
                                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Footer actions
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        color: AppColors.sidebarBg,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
                        border: Border(top: BorderSide(color: AppColors.borderDark, width: 0.8)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isGenerating
                                ? null
                                : () async {
                                    await _handleGenerateAvatar(
                                      currentP,
                                      setModalState: (fn) {
                                        setPreviewState(fn);
                                        setModalState?.call(fn);
                                      },
                                    );
                                  },
                            icon: isGenerating
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF070B14)),
                                  )
                                : const Icon(Icons.auto_awesome_rounded, size: 15),
                            label: Text(
                              isGenerating ? 'Đang vẽ ảnh...' : 'AI vẽ lại avatar',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: const Color(0xFF070B14),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textWhite,
                              side: const BorderSide(color: AppColors.borderDark),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Text('Đóng', style: TextStyle(fontSize: 12)),
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
      },
    );
  }

  void _showPersonaDetails(PersonaProfile persona) {
    final nameCtrl = TextEditingController(text: persona.name);
    final ageCtrl = TextEditingController(text: persona.age.toString());
    String selectedGender = persona.gender;
    final bioCtrl = TextEditingController(text: persona.bio);
    final promptCtrl = TextEditingController(text: persona.avatarPrompt);
    final externalDeviceCtrl = TextEditingController(text: persona.externalDeviceAddress ?? '192.168.1.227:38233');
    bool useExternalDevice = persona.useExternalDevice;
    final phoneCtrl = TextEditingController(text: persona.phoneNumber ?? '');
    final emailCtrl = TextEditingController(text: persona.email ?? '');
    bool autoSyncPhoneToDevice = persona.autoSyncPhoneToDevice;
    bool isPurchasingPhone = false;
    bool isReordering = false;
    bool isRefunding = false;
    bool isTestingDevice = false;
    Timer? otpTimer;
    String? latestOtpCode;
    int selectedSmsService = 924; // 924: TikTok, 395: Gmail/Google, 329: Facebook
    int detectCountryIdFromPhone(String? phone) {
      if (phone == null || phone.trim().isEmpty) return 11;
      final clean = phone.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
      if (clean.startsWith('+1') || (clean.startsWith('1') && clean.length == 11)) return 1;
      if (clean.startsWith('+84') || (clean.startsWith('84') && clean.length >= 11) || clean.startsWith('0')) return 11;
      for (final c in SmsPoolService.popularCountries) {
        if (clean.startsWith('+${c.cc}') || clean.startsWith(c.cc)) {
          return c.id;
        }
      }
      return 11;
    }
    int selectedSmsCountry = detectCountryIdFromPhone(persona.phoneNumber);
    String? currentOrderId = persona.smsOrderId;
    String selectedDeviceType = persona.deviceType; // 'mobile' | 'tablet'
    String? selectedAvd = persona.avdName;
    final agentInfoCtrl = TextEditingController(text: persona.agentInfo ?? '');
    List<String> availableAvds = [];
    bool isLoadingAvds = true;
    bool didFetchAvds = false;
    bool hasPersonaAvd = false;
    bool isCreatingPersonaAvd = false;
    bool isImportingPersonaAvd = false;
    bool isBackingUpPersonaAvd = false;
    bool isRestoringPersonaAvd = false;
    bool isDeletingPersonaAvd = false;
    bool isSaving = false;

    void startOtpPolling(String orderId, StateSetter setDialogState, BuildContext dialogCtx) {
      otpTimer?.cancel();
      otpTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        try {
          final res = await SmsPoolService().checkSms(orderId: orderId);
          final code = res['sms']?.toString() ?? res['code']?.toString() ?? '';
          if (code.isNotEmpty && code != '0') {
            timer.cancel();
            otpTimer = null;
            if (dialogCtx.mounted) {
              setDialogState(() {
                latestOtpCode = code;
              });
              // Tự động copy mã OTP vào Clipboard máy tính
              Clipboard.setData(ClipboardData(text: code));
              // Tự động bắn mã OTP vào Clipboard điện thoại ngoại vi nếu đang kết nối
              if (useExternalDevice && externalDeviceCtrl.text.trim().isNotEmpty) {
                try {
                  final devAddr = externalDeviceCtrl.text.trim();
                  _socks5Service.syncPhoneNumberToDevice(devAddr, code, ownerName: 'Mã OTP');
                } catch (_) {}
              }
              AppToast.success(dialogCtx, 'Đã nhận mã OTP: $code (Đã copy vào bộ nhớ tạm)!');
            }
          }
        } catch (_) {}
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          if (!didFetchAvds) {
            didFetchAvds = true;
            if (currentOrderId != null && currentOrderId!.isNotEmpty && latestOtpCode == null) {
              startOtpPolling(currentOrderId!, setDialogState, dialogCtx);
            }
            Future.wait([
              _socks5Service.getAvailableAvds(),
              _socks5Service.hasDeviceForPersona(ip: persona.ip, personaName: persona.name, avdName: persona.avdName),
            ]).then((results) {
              if (dialogCtx.mounted) {
                final avds = results[0] as List<String>;
                final hasDev = results[1] as bool;
                final expectedPersonaAvd = generatePersonaAvdName(ip: persona.ip, personaName: persona.name);
                final legacyPersonaClone = 'Pixel_10_Pro_persona_${persona.ip.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), "_")}';
                setDialogState(() {
                  availableAvds = avds;
                  hasPersonaAvd = hasDev || avds.contains(expectedPersonaAvd) || avds.contains(legacyPersonaClone);
                  isLoadingAvds = false;
                  if (selectedAvd == null && avds.isNotEmpty) {
                    if (avds.contains(expectedPersonaAvd)) {
                      selectedAvd = expectedPersonaAvd;
                    } else if (avds.contains(legacyPersonaClone)) {
                      selectedAvd = legacyPersonaClone;
                    }
                  }
                });
              }
            }).catchError((_) {
              if (dialogCtx.mounted) {
                setDialogState(() {
                  isLoadingAvds = false;
                });
              }
            });
          }
          return Dialog(
            backgroundColor: AppColors.cardBg,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.borderLight, width: 1.2),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. MODAL HEADER (Nền tối riêng biệt và border bottom sắc nét)
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
                        () {
                          final currentP = _personas[persona.ip] ?? persona;
                          final isGen = _generatingAvatarIps.contains(currentP.ip);
                          final hasImg = currentP.avatarUrl != null && currentP.avatarUrl!.isNotEmpty;

                          return Tooltip(
                            message: 'Bấm để phóng to xem rõ nét ảnh avatar',
                            child: InkWell(
                              onTap: () {
                                final currentPWithForm = currentP.copyWith(
                                  name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : currentP.name,
                                  age: int.tryParse(ageCtrl.text.trim()) ?? currentP.age,
                                  gender: selectedGender,
                                  bio: bioCtrl.text.trim(),
                                  avatarPrompt: promptCtrl.text.trim(),
                                  agentInfo: agentInfoCtrl.text.trim(),
                                );
                                _showAvatarPreviewDialog(currentPWithForm, setModalState: setDialogState);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isGen ? AppColors.primaryLight : AppColors.primary.withValues(alpha: 0.4),
                                        width: 1.3,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: hasImg
                                          ? (currentP.avatarUrl!.startsWith('http')
                                              ? Image.network(
                                                  currentP.avatarUrl!,
                                                  key: ValueKey(currentP.avatarUrl),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (ctx, err, stack) => const Icon(Icons.person_rounded, color: AppColors.primaryLight, size: 22),
                                                )
                                              : Image.file(
                                                  File(currentP.avatarUrl!),
                                                  key: ValueKey(currentP.avatarUrl),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (ctx, err, stack) => const Icon(Icons.person_rounded, color: AppColors.primaryLight, size: 22),
                                                ))
                                          : const Icon(Icons.person_rounded, color: AppColors.primaryLight, size: 22),
                                    ),
                                  ),
                                  if (isGen)
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Center(
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Positioned(
                                      right: -3,
                                      bottom: -3,
                                      child: Tooltip(
                                        message: 'Bấm để AI tạo lại avatar',
                                        child: InkWell(
                                          onTap: () {
                                            final currentPWithForm = currentP.copyWith(
                                              name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : currentP.name,
                                              age: int.tryParse(ageCtrl.text.trim()) ?? currentP.age,
                                              gender: selectedGender,
                                              bio: bioCtrl.text.trim(),
                                              avatarPrompt: promptCtrl.text.trim(),
                                              agentInfo: agentInfoCtrl.text.trim(),
                                            );
                                            _handleGenerateAvatar(currentPWithForm, setModalState: setDialogState);
                                          },
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                              color: AppColors.cardBg,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(2.5),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.95),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.auto_awesome_rounded, size: 9, color: Color(0xFF070B14)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hồ sơ nhân vật AI',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                              ),
                              Text(
                                'IP: ${persona.ip}',
                                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.primaryLight),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(dialogCtx).pop(),
                            borderRadius: BorderRadius.circular(6),
                            hoverColor: AppColors.borderDark.withValues(alpha: 0.6),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.borderDark, width: 1),
                              ),
                              child: const Center(
                                child: Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. MODAL BODY (Scrollable with distinct padding)
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row Tên + Tuổi + Giới tính
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Tên nhân vật', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                      const SizedBox(height: 5),
                                      SizedBox(
                                        height: 36,
                                        child: TextField(
                                          controller: nameCtrl,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            hintText: 'Nhập tên...',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 65,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Tuổi', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                      const SizedBox(height: 5),
                                      SizedBox(
                                        height: 36,
                                        child: TextField(
                                          controller: ageCtrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            hintText: '25',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 85,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Giới tính', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                      const SizedBox(height: 5),
                                      Container(
                                        height: 36,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.inputBg,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.borderDark),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: (selectedGender == 'Nữ' || selectedGender == 'Female') ? 'Nữ' : 'Nam',
                                            dropdownColor: AppColors.sidebarBg,
                                            icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textDim),
                                            isExpanded: true,
                                            style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                                            items: const [
                                              DropdownMenuItem(value: 'Nam', child: Text('Nam')),
                                              DropdownMenuItem(value: 'Nữ', child: Text('Nữ')),
                                            ],
                                            onChanged: (val) {
                                              if (val != null) {
                                                setDialogState(() {
                                                  selectedGender = val;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Bio cá tính
                            const Text('Cá tính & Tiểu sử (Bio)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                            const SizedBox(height: 5),
                            TextField(
                              controller: bioCtrl,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.3),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.all(10),
                                hintText: 'Mô tả nghề nghiệp, sở thích, tính cách...',
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Email nhân vật
                            const Text('Email', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                            const SizedBox(height: 5),
                            SizedBox(
                              height: 36,
                              child: TextField(
                                controller: emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  hintText: 'vidu@gmail.com',
                                  prefixIcon: Icon(Icons.email_outlined, size: 14, color: AppColors.textDim),
                                  prefixIconConstraints: BoxConstraints(minWidth: 30, minHeight: 30),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Prompt tạo Avatar AI
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Prompt tạo Avatar AI', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        final currentP = _personas[persona.ip] ?? persona;
                                        if (_generatingAvatarIps.contains(currentP.ip)) return;
                                        final currentPWithForm = currentP.copyWith(
                                          name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : currentP.name,
                                          age: int.tryParse(ageCtrl.text.trim()) ?? currentP.age,
                                          gender: selectedGender,
                                          bio: bioCtrl.text.trim(),
                                          avatarPrompt: promptCtrl.text.trim(),
                                          agentInfo: agentInfoCtrl.text.trim(),
                                        );
                                        _handleGenerateAvatar(currentPWithForm, setModalState: setDialogState);
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentCyan.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.35), width: 0.8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.accentCyan),
                                            SizedBox(width: 5),
                                            Text(
                                              'Vẽ lại ảnh theo prompt này',
                                              style: TextStyle(fontSize: 11, color: AppColors.accentCyan, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _copyToClipboard(promptCtrl.text, 'Avatar Prompt'),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 0.8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.copy_rounded, size: 12, color: AppColors.primaryLight),
                                            SizedBox(width: 5),
                                            Text(
                                              'Sao chép prompt',
                                              style: TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            TextField(
                              controller: promptCtrl,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.primaryLight, height: 1.35),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.all(10),
                                hintText: 'Prompt tiếng Anh tạo chân dung...',
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Thông tin Agent (System Role / Nhiệm vụ)
                            const Text('Thông tin Agent (Vai trò / Nhiệm vụ)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                            const SizedBox(height: 5),
                            TextField(
                              controller: agentInfoCtrl,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 12, color: AppColors.accent, height: 1.3),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.all(10),
                                hintText: 'Ví dụ: Seeding bài viết Facebook, tương tác nhóm, trả lời tin nhắn...',
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Cấu hình Thiết bị (Local AVD vs Ngoại vi)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.sidebarBg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: useExternalDevice ? AppColors.accent.withValues(alpha: 0.5) : AppColors.primaryLight.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            useExternalDevice ? Icons.cell_wifi_rounded : Icons.phone_android_rounded,
                                            size: 16,
                                            color: useExternalDevice ? AppColors.accent : AppColors.primaryLight,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            useExternalDevice ? 'Thiết bị ngoại vi (WiFi ADB)' : 'Máy ảo Local AVD',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                          ),
                                        ],
                                      ),
                                      SizedBox(
                                        height: 24,
                                        child: Switch(
                                          value: useExternalDevice,
                                          activeThumbColor: AppColors.accent,
                                          onChanged: (val) {
                                            setDialogState(() {
                                              useExternalDevice = val;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),

                                  if (useExternalDevice) ...[
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Địa chỉ thiết bị ngoại vi (IP:Port):',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: SizedBox(
                                            height: 36,
                                            child: TextField(
                                              controller: externalDeviceCtrl,
                                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.accent),
                                              decoration: const InputDecoration(
                                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                prefixIcon: Icon(Icons.settings_ethernet_rounded, size: 16),
                                                hintText: '192.168.1.227:38233',
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message: 'Kiểm tra kết nối ADB WiFi tới thiết bị ngoại vi',
                                          child: ElevatedButton.icon(
                                            onPressed: isTestingDevice
                                                ? null
                                                : () async {
                                                    final devAddr = externalDeviceCtrl.text.trim();
                                                    if (devAddr.isEmpty) {
                                                      AppToast.warning(dialogCtx, 'Vui lòng nhập địa chỉ thiết bị ngoại vi (IP:Port)');
                                                      return;
                                                    }
                                                    setDialogState(() {
                                                      isTestingDevice = true;
                                                    });
                                                    try {
                                                      await _socks5Service.connectRemoteDevice(devAddr);
                                                      if (dialogCtx.mounted) {
                                                        AppToast.success(dialogCtx, 'Kết nối thành công tới thiết bị ngoại vi ($devAddr)!');
                                                      }
                                                    } catch (e) {
                                                      if (dialogCtx.mounted) {
                                                        AppToast.error(dialogCtx, 'Không thể kết nối tới $devAddr: $e');
                                                      }
                                                    } finally {
                                                      setDialogState(() {
                                                        isTestingDevice = false;
                                                      });
                                                    }
                                                  },
                                            icon: isTestingDevice
                                                ? const SizedBox(
                                                    width: 12,
                                                    height: 12,
                                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF070B14)),
                                                  )
                                                : const Icon(Icons.network_check_rounded, size: 14),
                                            label: Text(
                                              isTestingDevice ? 'Đang test...' : 'Test kết nối',
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.primary,
                                              foregroundColor: const Color(0xFF070B14),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 12),
                                    // Tùy chọn Loại thiết bị: Mobile hoặc Tablet
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Loại thiết bị AVD',
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: InkWell(
                                                onTap: () {
                                                  setDialogState(() {
                                                    selectedDeviceType = 'mobile';
                                                  });
                                                },
                                                borderRadius: BorderRadius.circular(6),
                                                child: Container(
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: selectedDeviceType == 'mobile'
                                                        ? AppColors.primary.withValues(alpha: 0.2)
                                                        : AppColors.inputBg,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: selectedDeviceType == 'mobile'
                                                          ? AppColors.primaryLight
                                                          : AppColors.borderDark,
                                                      width: selectedDeviceType == 'mobile' ? 1.5 : 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(
                                                        Icons.phone_android_rounded,
                                                        size: 14,
                                                        color: selectedDeviceType == 'mobile'
                                                            ? AppColors.primaryLight
                                                            : AppColors.textDim,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        'Mobile',
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight: selectedDeviceType == 'mobile'
                                                              ? FontWeight.bold
                                                              : FontWeight.normal,
                                                          color: selectedDeviceType == 'mobile'
                                                              ? AppColors.textWhite
                                                              : AppColors.textDim,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: InkWell(
                                                onTap: () {
                                                  setDialogState(() {
                                                    selectedDeviceType = 'tablet';
                                                  });
                                                },
                                                borderRadius: BorderRadius.circular(6),
                                                child: Container(
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: selectedDeviceType == 'tablet'
                                                        ? AppColors.accent.withValues(alpha: 0.2)
                                                        : AppColors.inputBg,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: selectedDeviceType == 'tablet'
                                                          ? AppColors.accent
                                                          : AppColors.borderDark,
                                                      width: selectedDeviceType == 'tablet' ? 1.5 : 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(
                                                        Icons.tablet_android_rounded,
                                                        size: 14,
                                                        color: selectedDeviceType == 'tablet'
                                                            ? AppColors.accent
                                                            : AppColors.textDim,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        'Tablet',
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight: selectedDeviceType == 'tablet'
                                                              ? FontWeight.bold
                                                              : FontWeight.normal,
                                                          color: selectedDeviceType == 'tablet'
                                                              ? AppColors.textWhite
                                                              : AppColors.textDim,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Chọn máy ảo AVD & Hành động tạo mới/import
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text(
                                                  'Chọn máy ảo (AVD)',
                                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: hasPersonaAvd ? AppColors.accent.withValues(alpha: 0.15) : AppColors.danger.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(3),
                                                    border: Border.all(
                                                      color: hasPersonaAvd ? AppColors.accent.withValues(alpha: 0.5) : AppColors.danger.withValues(alpha: 0.5),
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    hasPersonaAvd ? 'Đã có máy ảo' : 'Chưa cài đặt',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: hasPersonaAvd ? AppColors.accent : AppColors.danger,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (!hasPersonaAvd) ...[
                                                  // NÚT TẠO MỚI (chỉ hiện khi chưa có máy ảo)
                                                  InkWell(
                                                    onTap: (isCreatingPersonaAvd || isImportingPersonaAvd || isDeletingPersonaAvd)
                                                        ? null
                                                        : () async {
                                                            setDialogState(() {
                                                              isCreatingPersonaAvd = true;
                                                            });
                                                            try {
                                                              AppToast.info(dialogCtx, 'Đang tạo máy ảo AVD độc lập cho IP ${persona.ip}...');
                                                              final createdAvd = await _socks5Service.createPersonaDeviceAvd(
                                                                ip: persona.ip,
                                                                personaName: persona.name,
                                                                baseAvd: selectedAvd ?? persona.avdName,
                                                              );
                                                              final currentP = _personas[persona.ip] ?? persona;
                                                              final updated = currentP.copyWith(avdName: createdAvd);
                                                              await _personaService.updatePersona(updated);
                                                              final freshAvds = await _socks5Service.getAvailableAvds();
                                                              if (mounted) {
                                                                setState(() {
                                                                  _personas[persona.ip] = updated;
                                                                  _availableAvds = freshAvds.toSet();
                                                                });
                                                              }
                                                              if (dialogCtx.mounted) {
                                                                setDialogState(() {
                                                                  availableAvds = freshAvds;
                                                                  selectedAvd = createdAvd;
                                                                  hasPersonaAvd = true;
                                                                });
                                                                AppToast.success(dialogCtx, 'Đã tạo máy ảo AVD thành công: $createdAvd');
                                                              }
                                                            } catch (e) {
                                                              if (dialogCtx.mounted) {
                                                                AppToast.error(dialogCtx, 'Lỗi tạo máy ảo: $e');
                                                              }
                                                            } finally {
                                                              if (dialogCtx.mounted) {
                                                                setDialogState(() {
                                                                  isCreatingPersonaAvd = false;
                                                                });
                                                              }
                                                            }
                                                          },
                                                    borderRadius: BorderRadius.circular(4),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          if (isCreatingPersonaAvd)
                                                            const SizedBox(
                                                              width: 10,
                                                              height: 10,
                                                              child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.accent),
                                                            )
                                                          else
                                                            const Icon(Icons.add_circle_outline_rounded, size: 12, color: AppColors.accent),
                                                          const SizedBox(width: 3),
                                                          Text(
                                                            isCreatingPersonaAvd ? 'Đang tạo...' : 'Tạo mới',
                                                            style: const TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.bold),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),

                                                  // NÚT IMPORT (chỉ hiện khi chưa có máy ảo)
                                                  InkWell(
                                                    onTap: (isCreatingPersonaAvd || isImportingPersonaAvd || isDeletingPersonaAvd)
                                                        ? null
                                                        : () async {
                                                            String? chosenPath;
                                                            try {
                                                              const defaultBackupDir = '/home/yenai/Documents/Devices bk';
                                                              final initialDir = Directory(defaultBackupDir).existsSync() ? defaultBackupDir : null;
                                                              final res = await FilePicker.platform.pickFiles(
                                                                dialogTitle: 'Chọn file backup máy ảo Android (.tar.gz, .zip)',
                                                                initialDirectory: initialDir,
                                                                type: FileType.custom,
                                                                allowedExtensions: ['tar.gz', 'gz', 'tgz', 'zip', 'tar'],
                                                              );
                                                              if (res != null && res.files.single.path != null) {
                                                                chosenPath = res.files.single.path;
                                                              }
                                                            } catch (e) {
                                                              if (dialogCtx.mounted) {
                                                                AppToast.error(dialogCtx, 'Không thể mở trình chọn file: $e');
                                                              }
                                                              return;
                                                            }

                                                            if (chosenPath == null) {
                                                              if (dialogCtx.mounted) {
                                                                AppToast.warning(dialogCtx, 'Chưa chọn file backup để import');
                                                              }
                                                              return;
                                                            }

                                                            setDialogState(() {
                                                              isImportingPersonaAvd = true;
                                                            });
                                                            try {
                                                              if (dialogCtx.mounted) {
                                                                AppToast.info(dialogCtx, 'Đang giải nén backup và nạp ứng dụng (Facebook, TikTok)...');
                                                              }
                                                              final importedAvd = await _socks5Service.importPersonaDeviceBackup(
                                                                ip: persona.ip,
                                                                personaName: persona.name,
                                                                archivePath: chosenPath,
                                                              );
                                                              final currentP = _personas[persona.ip] ?? persona;
                                                              final updated = currentP.copyWith(avdName: importedAvd);
                                                              await _personaService.updatePersona(updated);
                                                              final freshAvds = await _socks5Service.getAvailableAvds();
                                                              if (mounted) {
                                                                setState(() {
                                                                  _personas[persona.ip] = updated;
                                                                  _availableAvds = freshAvds.toSet();
                                                                });
                                                              }
                                                              if (dialogCtx.mounted) {
                                                                setDialogState(() {
                                                                  availableAvds = freshAvds;
                                                                  selectedAvd = importedAvd;
                                                                  hasPersonaAvd = true;
                                                                });
                                                                AppToast.success(dialogCtx, 'Import backup thành công! Đã nạp đầy đủ app cho $importedAvd');
                                                              }
                                                            } catch (e) {
                                                              if (dialogCtx.mounted) {
                                                                AppToast.error(dialogCtx, 'Lỗi import backup: $e');
                                                              }
                                                            } finally {
                                                              if (dialogCtx.mounted) {
                                                                setDialogState(() {
                                                                  isImportingPersonaAvd = false;
                                                                });
                                                              }
                                                            }
                                                          },
                                                    borderRadius: BorderRadius.circular(4),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          if (isImportingPersonaAvd)
                                                            const SizedBox(
                                                              width: 10,
                                                              height: 10,
                                                              child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.primaryLight),
                                                            )
                                                          else
                                                            const Icon(Icons.cloud_download_rounded, size: 12, color: AppColors.primaryLight),
                                                          const SizedBox(width: 3),
                                                          Text(
                                                            isImportingPersonaAvd ? 'Đang nạp...' : 'Import',
                                                            style: const TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ] else ...[
                                                // NÚT BACKUP (Sao lưu máy ảo)
                                                InkWell(
                                                  onTap: (selectedAvd == null || isBackingUpPersonaAvd || isRestoringPersonaAvd || isDeletingPersonaAvd)
                                                      ? null
                                                      : () async {
                                                          setDialogState(() {
                                                            isBackingUpPersonaAvd = true;
                                                          });
                                                          try {
                                                            if (dialogCtx.mounted) {
                                                              AppToast.info(dialogCtx, 'Đang tiến hành sao lưu máy ảo $selectedAvd...');
                                                            }
                                                            final backupPath = await _socks5Service.backupPersonaDeviceAvd(
                                                              avdName: selectedAvd!,
                                                              onProgress: (msg) {
                                                                if (dialogCtx.mounted) {
                                                                  AppToast.info(dialogCtx, msg);
                                                                }
                                                              },
                                                            );
                                                            if (dialogCtx.mounted) {
                                                              AppToast.success(dialogCtx, 'Sao lưu thành công! File lưu tại: $backupPath');
                                                            }
                                                          } catch (e) {
                                                            if (dialogCtx.mounted) {
                                                              AppToast.error(dialogCtx, 'Lỗi sao lưu máy ảo: $e');
                                                            }
                                                          } finally {
                                                            if (dialogCtx.mounted) {
                                                              setDialogState(() {
                                                                isBackingUpPersonaAvd = false;
                                                              });
                                                            }
                                                          }
                                                        },
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        if (isBackingUpPersonaAvd)
                                                          const SizedBox(
                                                            width: 10,
                                                            height: 10,
                                                            child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.accent),
                                                          )
                                                        else
                                                          const Icon(Icons.backup_rounded, size: 12, color: AppColors.accent),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          isBackingUpPersonaAvd ? 'Đang lưu...' : 'Backup',
                                                          style: const TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.bold),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // NÚT RESTORE (Khôi phục / Nạp đè máy ảo từ backup)
                                                InkWell(
                                                  onTap: (isBackingUpPersonaAvd || isRestoringPersonaAvd || isDeletingPersonaAvd)
                                                      ? null
                                                      : () async {
                                                          String? chosenPath;
                                                          try {
                                                            const defaultBackupDir = '/home/yenai/Documents/Devices bk';
                                                            final initialDir = Directory(defaultBackupDir).existsSync() ? defaultBackupDir : null;
                                                            final res = await FilePicker.platform.pickFiles(
                                                              dialogTitle: 'Chọn file backup để khôi phục máy ảo (.tar.gz, .zip)',
                                                              initialDirectory: initialDir,
                                                              type: FileType.custom,
                                                              allowedExtensions: ['tar.gz', 'gz', 'tgz', 'zip', 'tar'],
                                                            );
                                                            if (res != null && res.files.single.path != null) {
                                                              chosenPath = res.files.single.path;
                                                            }
                                                          } catch (e) {
                                                            if (dialogCtx.mounted) {
                                                              AppToast.error(dialogCtx, 'Không thể mở trình chọn file: $e');
                                                            }
                                                            return;
                                                          }

                                                          if (chosenPath == null) {
                                                            if (dialogCtx.mounted) {
                                                              AppToast.warning(dialogCtx, 'Chưa chọn file backup để khôi phục');
                                                            }
                                                            return;
                                                          }

                                                          if (!dialogCtx.mounted) return;
                                                          final confirm = await showDialog<bool>(
                                                            context: dialogCtx,
                                                            builder: (c) => AlertDialog(
                                                              backgroundColor: const Color(0xFF0C1322),
                                                              title: const Text('Xác nhận khôi phục máy ảo', style: TextStyle(color: AppColors.warning, fontSize: 14)),
                                                              content: Text('Khôi phục sẽ ghi đè toàn bộ dữ liệu hiện tại của máy ảo "$selectedAvd". Bạn có chắc chắn muốn tiếp tục không?', style: const TextStyle(color: AppColors.textWhite, fontSize: 12)),
                                                              actions: [
                                                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy', style: TextStyle(color: AppColors.textDim))),
                                                                ElevatedButton(
                                                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
                                                                  onPressed: () => Navigator.pop(c, true),
                                                                  child: const Text('Đồng ý khôi phục', style: TextStyle(color: Colors.black)),
                                                                ),
                                                              ],
                                                            ),
                                                          );

                                                          if (confirm != true) return;

                                                          setDialogState(() {
                                                            isRestoringPersonaAvd = true;
                                                          });
                                                          try {
                                                            if (dialogCtx.mounted) {
                                                              AppToast.info(dialogCtx, 'Đang khôi phục dữ liệu máy ảo từ backup...');
                                                            }
                                                            final importedAvd = await _socks5Service.importPersonaDeviceBackup(
                                                              ip: persona.ip,
                                                              personaName: persona.name,
                                                              archivePath: chosenPath,
                                                            );
                                                            final currentP = _personas[persona.ip] ?? persona;
                                                            final updated = currentP.copyWith(avdName: importedAvd);
                                                            await _personaService.updatePersona(updated);
                                                            final freshAvds = await _socks5Service.getAvailableAvds();
                                                            if (mounted) {
                                                              setState(() {
                                                                _personas[persona.ip] = updated;
                                                                _availableAvds = freshAvds.toSet();
                                                              });
                                                            }
                                                            if (dialogCtx.mounted) {
                                                              setDialogState(() {
                                                                availableAvds = freshAvds;
                                                                selectedAvd = importedAvd;
                                                                hasPersonaAvd = true;
                                                              });
                                                              AppToast.success(dialogCtx, 'Khôi phục máy ảo thành công: $importedAvd');
                                                            }
                                                          } catch (e) {
                                                            if (dialogCtx.mounted) {
                                                              AppToast.error(dialogCtx, 'Lỗi khôi phục máy ảo: $e');
                                                            }
                                                          } finally {
                                                            if (dialogCtx.mounted) {
                                                              setDialogState(() {
                                                                isRestoringPersonaAvd = false;
                                                              });
                                                            }
                                                          }
                                                        },
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        if (isRestoringPersonaAvd)
                                                          const SizedBox(
                                                            width: 10,
                                                            height: 10,
                                                            child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.primaryLight),
                                                          )
                                                        else
                                                          const Icon(Icons.settings_backup_restore_rounded, size: 12, color: AppColors.primaryLight),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          isRestoringPersonaAvd ? 'Đang khôi phục...' : 'Restore',
                                                          style: const TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // NÚT XÓA
                                                InkWell(
                                                  onTap: (selectedAvd == null || isDeletingPersonaAvd)
                                                      ? null
                                                      : () async {
                                                          final avdToDelete = selectedAvd!;
                                                          final confirm = await showDialog<bool>(
                                                            context: dialogCtx,
                                                            builder: (c) => AlertDialog(
                                                              backgroundColor: const Color(0xFF0C1322),
                                                              title: const Text('Xác nhận xóa máy ảo', style: TextStyle(color: AppColors.danger, fontSize: 14)),
                                                              content: Text('Bạn có chắc chắn muốn xóa máy ảo "$avdToDelete" khỏi ổ cứng không? Thao tác này không thể hoàn tác.', style: const TextStyle(color: AppColors.textWhite, fontSize: 12)),
                                                              actions: [
                                                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy', style: TextStyle(color: AppColors.textDim))),
                                                                ElevatedButton(
                                                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                                                  onPressed: () => Navigator.pop(c, true),
                                                                  child: const Text('Xóa vĩnh viễn', style: TextStyle(color: Colors.white)),
                                                                ),
                                                              ],
                                                            ),
                                                          );

                                                          if (confirm != true) return;

                                                          setDialogState(() {
                                                            isDeletingPersonaAvd = true;
                                                          });
                                                          try {
                                                            await _socks5Service.deleteAvd(avdToDelete, ip: persona.ip);
                                                            final freshAvds = await _socks5Service.getAvailableAvds();
                                                            final currentP = _personas[persona.ip] ?? persona;
                                                            final updated = currentP.copyWith(avdName: null);
                                                            await _personaService.updatePersona(updated);

                                                            if (mounted) {
                                                              setState(() {
                                                                _personas[persona.ip] = updated;
                                                                _availableAvds = freshAvds.toSet();
                                                              });
                                                            }

                                                            if (dialogCtx.mounted) {
                                                              setDialogState(() {
                                                                availableAvds = freshAvds;
                                                                selectedAvd = null;
                                                                hasPersonaAvd = false;
                                                              });
                                                              AppToast.success(dialogCtx, 'Đã xóa máy ảo $avdToDelete thành công');
                                                            }
                                                          } catch (e) {
                                                            if (dialogCtx.mounted) {
                                                              AppToast.error(dialogCtx, 'Lỗi khi xóa máy ảo: $e');
                                                            }
                                                          } finally {
                                                            if (dialogCtx.mounted) {
                                                              setDialogState(() {
                                                                isDeletingPersonaAvd = false;
                                                              });
                                                            }
                                                          }
                                                        },
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        if (isDeletingPersonaAvd)
                                                          const SizedBox(
                                                            width: 10,
                                                            height: 10,
                                                            child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.danger),
                                                          )
                                                        else
                                                          Icon(
                                                            Icons.delete_outline_rounded,
                                                            size: 12,
                                                            color: selectedAvd == null ? AppColors.textDim.withValues(alpha: 0.4) : AppColors.danger,
                                                          ),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          isDeletingPersonaAvd ? 'Đang xóa...' : 'Xóa',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: selectedAvd == null ? AppColors.textDim.withValues(alpha: 0.4) : AppColors.danger,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                 ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          height: 36,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: AppColors.inputBg,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AppColors.borderDark),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String?>(
                                              value: availableAvds.contains(selectedAvd) ? selectedAvd : null,
                                              hint: Text(
                                                isLoadingAvds ? 'Đang quét...' : (availableAvds.isEmpty ? 'Chưa có AVD (Khuyên dùng Ngoại vi)' : 'Chọn AVD...'),
                                                style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                                              ),
                                              dropdownColor: AppColors.sidebarBg,
                                              icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textDim),
                                              isExpanded: true,
                                              style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                                              items: [
                                                const DropdownMenuItem<String?>(
                                                  value: null,
                                                  child: Text('Mặc định hệ thống', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                                                ),
                                                ...availableAvds.map((avd) {
                                                  return DropdownMenuItem<String?>(
                                                    value: avd,
                                                    child: Text(
                                                      avd,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11.5),
                                                    ),
                                                  );
                                                }),
                                              ],
                                              onChanged: (val) {
                                                setDialogState(() {
                                                  selectedAvd = val;
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                            // Cấu hình Số điện thoại & Thuê số OTP
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.inputBg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.borderDark),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.phone_android_rounded, size: 14, color: AppColors.accent),
                                          SizedBox(width: 6),
                                          Text(
                                            () {
                                              final countryObj = SmsPoolService.popularCountries.firstWhere(
                                                (c) => c.id == selectedSmsCountry,
                                                orElse: () => SmsPoolService.popularCountries.first,
                                              );
                                              return 'Thuê số điện thoại ${countryObj.name} (+${countryObj.cc})';
                                            }(),
                                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                          ),
                                        ],
                                      ),
                                      SizedBox(
                                        height: 22,
                                        child: Switch(
                                          value: autoSyncPhoneToDevice,
                                          activeThumbColor: AppColors.accent,
                                          onChanged: (val) {
                                            setDialogState(() {
                                              autoSyncPhoneToDevice = val;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Tự động ghi số điện thoại vào User Profile thiết bị ngoại vi qua ADB khi kết nối',
                                    style: TextStyle(fontSize: 10, color: AppColors.textDim),
                                  ),
                                  const SizedBox(height: 8),
                                  // Dropdown chọn Quốc gia và Dịch vụ SMSPool
                                  Row(
                                     children: [
                                       Expanded(
                                         flex: 5,
                                         child: Container(
                                           height: 34,
                                           padding: const EdgeInsets.symmetric(horizontal: 8),
                                           decoration: BoxDecoration(
                                             color: AppColors.sidebarBg,
                                             borderRadius: BorderRadius.circular(5),
                                             border: Border.all(color: AppColors.borderDark),
                                           ),
                                           child: DropdownButtonHideUnderline(
                                             child: DropdownButton<int>(
                                               value: selectedSmsCountry,
                                               dropdownColor: AppColors.sidebarBg,
                                               isDense: true,
                                               isExpanded: true,
                                               icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textDim),
                                               style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite),
                                               items: SmsPoolService.popularCountries.map((c) {
                                                 return DropdownMenuItem<int>(
                                                   value: c.id,
                                                   child: Text(
                                                     '${c.name} (+${c.cc})',
                                                     overflow: TextOverflow.ellipsis,
                                                   ),
                                                 );
                                               }).toList(),
                                               onChanged: (val) {
                                                 if (val != null) {
                                                   setDialogState(() {
                                                     selectedSmsCountry = val;
                                                   });
                                                 }
                                               },
                                             ),
                                           ),
                                         ),
                                       ),
                                       const SizedBox(width: 8),
                                       Expanded(
                                         flex: 6,
                                         child: Container(
                                           height: 34,
                                           padding: const EdgeInsets.symmetric(horizontal: 8),
                                           decoration: BoxDecoration(
                                             color: AppColors.sidebarBg,
                                             borderRadius: BorderRadius.circular(5),
                                             border: Border.all(color: AppColors.borderDark),
                                           ),
                                           child: DropdownButtonHideUnderline(
                                             child: DropdownButton<int>(
                                               value: selectedSmsService,
                                               dropdownColor: AppColors.sidebarBg,
                                               isDense: true,
                                               isExpanded: true,
                                               icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textDim),
                                               style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite),
                                               items: const [
                                                 DropdownMenuItem(value: 924, child: Text('TikTok')),
                                                 DropdownMenuItem(value: 395, child: Text('Google / Gmail')),
                                                 DropdownMenuItem(value: 329, child: Text('Facebook')),
                                                 DropdownMenuItem(value: 589, child: Text('Telegram')),
                                               ],
                                               onChanged: (val) {
                                                 if (val != null) {
                                                   setDialogState(() {
                                                     selectedSmsService = val;
                                                   });
                                                 }
                                               },
                                             ),
                                           ),
                                         ),
                                       ),
                                     ],
                                   ),
                                   const SizedBox(height: 8),
                                   Row(
                                     children: [
                                       Expanded(
                                         child: SizedBox(
                                           height: 36,
                                           child: TextField(
                                             controller: phoneCtrl,
                                             style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textWhite),
                                             decoration: InputDecoration(
                                               contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                               prefixIcon: const Icon(Icons.dialpad_rounded, size: 15),
                                               hintText: () {
                                                 final countryObj = SmsPoolService.popularCountries.firstWhere(
                                                   (c) => c.id == selectedSmsCountry,
                                                   orElse: () => SmsPoolService.popularCountries.first,
                                                 );
                                                 return '+${countryObj.cc}xxxxxxxxx';
                                               }(),
                                               suffixIcon: phoneCtrl.text.isNotEmpty
                                                   ? Padding(
                                                       padding: const EdgeInsets.only(right: 6),
                                                       child: Tooltip(
                                                         message: 'Xóa số điện thoại',
                                                         child: InkWell(
                                                           onTap: () {
                                                             setDialogState(() {
                                                               phoneCtrl.clear();
                                                               autoSyncPhoneToDevice = false;
                                                             });
                                                           },
                                                           borderRadius: BorderRadius.circular(4),
                                                           child: Container(
                                                             width: 22,
                                                             height: 22,
                                                             alignment: Alignment.center,
                                                             decoration: BoxDecoration(
                                                               color: AppColors.danger.withValues(alpha: 0.15),
                                                               borderRadius: BorderRadius.circular(4),
                                                               border: Border.all(
                                                                 color: AppColors.danger.withValues(alpha: 0.4),
                                                                 width: 0.6,
                                                               ),
                                                             ),
                                                             child: const Icon(
                                                               Icons.close_rounded,
                                                               size: 13,
                                                               color: AppColors.danger,
                                                             ),
                                                           ),
                                                         ),
                                                       ),
                                                     )
                                                   : null,
                                               suffixIconConstraints: const BoxConstraints(
                                                 minWidth: 28,
                                                 minHeight: 28,
                                               ),
                                             ),
                                             onChanged: (_) {
                                               setDialogState(() {});
                                             },
                                           ),
                                         ),
                                       ),
                                       const SizedBox(width: 8),
                                       Tooltip(
                                         message: () {
                                           final countryObj = SmsPoolService.popularCountries.firstWhere(
                                             (c) => c.id == selectedSmsCountry,
                                             orElse: () => SmsPoolService.popularCountries.first,
                                           );
                                           return 'Thuê số ${countryObj.name} (+${countryObj.cc}) cho dịch vụ đã chọn';
                                         }(),
                                         child: ElevatedButton.icon(
                                           onPressed: isPurchasingPhone
                                               ? null
                                               : () async {
                                                   // BẮT BUỘC: Nếu bật chế độ thiết bị ngoại vi, kiểm tra kết nối thiết bị trước rồi mới cho thuê số
                                                   if (useExternalDevice) {
                                                     final devAddr = externalDeviceCtrl.text.trim();
                                                     if (devAddr.isEmpty) {
                                                       AppToast.warning(dialogCtx, 'Chưa nhập địa chỉ thiết bị ngoại vi! Vui lòng nhập IP:Port trước khi thuê số.');
                                                       return;
                                                     }
                                                     setDialogState(() {
                                                       isPurchasingPhone = true;
                                                     });
                                                     try {
                                                       await _socks5Service.connectRemoteDevice(devAddr);
                                                     } catch (e) {
                                                       setDialogState(() {
                                                         isPurchasingPhone = false;
                                                       });
                                                       if (dialogCtx.mounted) {
                                                         AppToast.error(dialogCtx, 'Chưa kết nối được với Thiết bị ngoại vi ($devAddr)! Vui lòng kiểm tra WiFi ADB trên máy.');
                                                       }
                                                       return;
                                                     }
                                                   } else {
                                                     setDialogState(() {
                                                       isPurchasingPhone = true;
                                                     });
                                                   }

                                                   try {
                                                     final countryObj = SmsPoolService.popularCountries.firstWhere(
                                                       (c) => c.id == selectedSmsCountry,
                                                       orElse: () => SmsPoolService.popularCountries.first,
                                                     );
                                                     final res = await SmsPoolService().orderSmsNumber(
                                                       country: selectedSmsCountry,
                                                       service: selectedSmsService,
                                                     );
                                                     if (res['success'] == 1) {
                                                       final rawNum = res['phonenumber']?.toString() ?? res['number']?.toString() ?? '';
                                                       final ccPrefix = countryObj.cc;
                                                       final formattedNum = rawNum.startsWith('+')
                                                           ? rawNum
                                                           : (rawNum.startsWith(ccPrefix)
                                                               ? '+$rawNum'
                                                               : '+$ccPrefix$rawNum');
                                                       phoneCtrl.text = formattedNum;
                                                       currentOrderId = res['order_id']?.toString() ?? res['orderid']?.toString();
                                                       autoSyncPhoneToDevice = true; // Tự động bật switch khi vừa mua số mới
                                                       latestOtpCode = null;
                                                       if (currentOrderId != null && currentOrderId!.isNotEmpty && dialogCtx.mounted) {
                                                         startOtpPolling(currentOrderId!, setDialogState, dialogCtx);
                                                       }

                                                       // Nếu máy ngoại vi đang kết nối, đồng bộ ngay lập tức
                                                       if (useExternalDevice && externalDeviceCtrl.text.trim().isNotEmpty) {
                                                         try {
                                                           await _socks5Service.syncPhoneNumberToDevice(
                                                             externalDeviceCtrl.text.trim(),
                                                             formattedNum,
                                                             ownerName: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'Chủ Thiết Bị',
                                                           );
                                                         } catch (_) {}
                                                       }

                                                       if (dialogCtx.mounted) {
                                                         AppToast.success(dialogCtx, 'Đã thuê số ${countryObj.shortName} (+${countryObj.cc}): $formattedNum và gắn vào máy!');
                                                       }
                                                     } else {
                                                       if (dialogCtx.mounted) {
                                                         AppToast.error(dialogCtx, 'Chưa thể thuê đầu số này.');
                                                       }
                                                     }
                                                   } catch (e) {
                                                     if (dialogCtx.mounted) {
                                                       AppToast.error(dialogCtx, 'Chưa thể thuê đầu số này.');
                                                     }
                                                   } finally {
                                                     setDialogState(() {
                                                       isPurchasingPhone = false;
                                                     });
                                                   }
                                                 },
                                           icon: isPurchasingPhone
                                               ? const SizedBox(
                                                   width: 12,
                                                   height: 12,
                                                   child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                                 )
                                               : const Icon(Icons.shopping_cart_rounded, size: 13),
                                           label: Text(
                                             isPurchasingPhone
                                                 ? 'Đang thuê...'
                                                 : () {
                                                     final countryObj = SmsPoolService.popularCountries.firstWhere(
                                                       (c) => c.id == selectedSmsCountry,
                                                       orElse: () => SmsPoolService.popularCountries.first,
                                                     );
                                                     return 'Thuê số ${countryObj.shortName}';
                                                   }(),
                                             style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                           ),
                                           style: ElevatedButton.styleFrom(
                                             backgroundColor: const Color(0xFF0284C7),
                                             foregroundColor: Colors.white,
                                             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                             shape: RoundedRectangleBorder(
                                               borderRadius: BorderRadius.circular(4),
                                             ),
                                           ),
                                         ),
                                       ),
                                        if (phoneCtrl.text.trim().isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Tooltip(
                                            message: 'Thuê lại chính số điện thoại ${phoneCtrl.text.trim()} này từ nhà cung cấp để nhận mã OTP mới',
                                            child: ElevatedButton.icon(
                                              onPressed: (isPurchasingPhone || isReordering)
                                                  ? null
                                                  : () async {
                                                      final rawPhone = phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
                                                      if (rawPhone.isEmpty) {
                                                        AppToast.warning(dialogCtx, 'Chưa có số điện thoại để thuê lại!');
                                                        return;
                                                      }

                                                      setDialogState(() {
                                                        isReordering = true;
                                                      });

                                                      try {
                                                        String? targetOrderId = currentOrderId;

                                                        if (targetOrderId == null || targetOrderId.isEmpty) {
                                                          final history = await SmsPoolService().getOrderHistory();
                                                          for (final item in history) {
                                                            final itemPhone = (item['phonenumber']?.toString() ?? item['number']?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                                                            if (itemPhone.isNotEmpty && (itemPhone.contains(rawPhone) || rawPhone.contains(itemPhone))) {
                                                              targetOrderId = item['order_code']?.toString() ?? item['order_id']?.toString() ?? item['orderid']?.toString();
                                                              if (targetOrderId != null && targetOrderId.isNotEmpty) {
                                                                break;
                                                              }
                                                            }
                                                          }
                                                        }

                                                        if (targetOrderId == null || targetOrderId.isEmpty) {
                                                          if (dialogCtx.mounted) {
                                                            AppToast.error(dialogCtx, 'Không tìm thấy mã đơn thuê trước đây của số này trên hệ thống để kích hoạt thuê lại.');
                                                          }
                                                          return;
                                                        }

                                                        final res = await SmsPoolService().resendSms(orderId: targetOrderId);
                                                        if (res['success'] == 1) {
                                                          final newOrderId = res['order_id']?.toString() ?? targetOrderId;
                                                          currentOrderId = newOrderId;
                                                          autoSyncPhoneToDevice = true;
                                                          latestOtpCode = null;

                                                          final currentP = _personas[persona.ip] ?? persona;
                                                          final updated = currentP.copyWith(
                                                            phoneNumber: phoneCtrl.text.trim(),
                                                            smsOrderId: newOrderId,
                                                          );
                                                          await _personaService.updatePersona(updated);
                                                          if (mounted) {
                                                            setState(() {
                                                              _personas[persona.ip] = updated;
                                                            });
                                                          }

                                                          if (newOrderId.isNotEmpty && dialogCtx.mounted) {
                                                            startOtpPolling(newOrderId, setDialogState, dialogCtx);
                                                          }

                                                          if (dialogCtx.mounted) {
                                                            AppToast.success(dialogCtx, 'Đã thuê lại thành công số ${phoneCtrl.text.trim()}! Đang chờ mã OTP mới...');
                                                          }
                                                        } else {
                                                          if (dialogCtx.mounted) {
                                                            final msg = res['message']?.toString();
                                                            AppToast.error(dialogCtx, (msg != null && msg.isNotEmpty) ? msg : 'Nhà cung cấp không cho phép thuê lại số điện thoại này vào thời điểm này.');
                                                          }
                                                        }
                                                      } catch (e) {
                                                        if (dialogCtx.mounted) {
                                                          AppToast.error(dialogCtx, 'Lỗi khi yêu cầu thuê lại số điện thoại: $e');
                                                        }
                                                      } finally {
                                                        setDialogState(() {
                                                          isReordering = false;
                                                        });
                                                      }
                                                    },
                                              icon: isReordering
                                                  ? const SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                                    )
                                                  : const Icon(Icons.sync_rounded, size: 13),
                                              label: Text(
                                                isReordering ? 'Đang thuê lại...' : 'Thuê lại số này',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF059669),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                     ],
                                   ),
                                  // Phần kiểm tra mã OTP khi đã có orderId từ SMSPool
                                  if (currentOrderId != null && currentOrderId!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: latestOtpCode != null ? const Color(0xFF10B981) : AppColors.borderDark,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Đơn thuê: $currentOrderId',
                                                  style: const TextStyle(fontSize: 10, color: AppColors.textDim, fontFamily: 'monospace'),
                                                ),
                                                const SizedBox(height: 2),
                                                if (latestOtpCode != null) ...[
                                                  SelectableText(
                                                    'Mã OTP: $latestOtpCode',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF10B981),
                                                    ),
                                                  ),
                                                ] else ...[
                                                  const Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 10,
                                                        height: 10,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 1.5,
                                                          color: Color(0xFFF59E0B),
                                                        ),
                                                      ),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        'Đang chờ tin nhắn OTP tự động...',
                                                        style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B)),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (latestOtpCode != null)
                                            IconButton(
                                              tooltip: 'Sao chép OTP',
                                              icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF10B981)),
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(text: latestOtpCode!));
                                                AppToast.info(dialogCtx, 'Đã sao chép: $latestOtpCode');
                                              },
                                            ),
                                          IconButton(
                                            tooltip: 'Thuê lại số này (Gửi lại OTP)',
                                            icon: isReordering
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 1.5,
                                                      color: Color(0xFF059669),
                                                    ),
                                                  )
                                                : const Icon(Icons.sync_rounded, size: 16, color: Color(0xFF059669)),
                                            onPressed: (isReordering || currentOrderId == null)
                                                ? null
                                                : () async {
                                                    setDialogState(() {
                                                      isReordering = true;
                                                    });
                                                    try {
                                                      final res = await SmsPoolService().resendSms(orderId: currentOrderId!);
                                                      if (res['success'] == 1) {
                                                        final newOrderId = res['order_id']?.toString() ?? currentOrderId!;
                                                        currentOrderId = newOrderId;
                                                        latestOtpCode = null;
                                                        if (dialogCtx.mounted) {
                                                          startOtpPolling(newOrderId, setDialogState, dialogCtx);
                                                          AppToast.success(dialogCtx, 'Đã yêu cầu thuê lại số thành công! Đang chờ mã OTP mới...');
                                                        }
                                                      } else {
                                                        if (dialogCtx.mounted) {
                                                          final msg = res['message']?.toString();
                                                          AppToast.error(dialogCtx, (msg != null && msg.isNotEmpty) ? msg : 'Không thể thuê lại số vào lúc này.');
                                                        }
                                                      }
                                                    } catch (e) {
                                                      if (dialogCtx.mounted) {
                                                        AppToast.error(dialogCtx, 'Lỗi khi yêu cầu thuê lại: $e');
                                                      }
                                                    } finally {
                                                      setDialogState(() {
                                                        isReordering = false;
                                                      });
                                                    }
                                                  },
                                          ),
                                          IconButton(
                                            tooltip: 'Hoàn tiền / Hủy đơn (Refund)',
                                            icon: isRefunding
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 1.5,
                                                      color: Color(0xFFEF4444),
                                                    ),
                                                  )
                                                : const Icon(Icons.replay_rounded, size: 16, color: Color(0xFFEF4444)),
                                            onPressed: isRefunding
                                                ? null
                                                : () async {
                                                    final confirm = await showDialog<bool>(
                                                      context: dialogCtx,
                                                      builder: (ctx) => TaduDialog(
                                                        minWidth: 420,
                                                        maxWidth: 500,
                                                        title: const Row(
                                                          children: [
                                                            Icon(Icons.replay_rounded, color: AppColors.danger, size: 20),
                                                            SizedBox(width: 8),
                                                            Text('Xác Nhận Hoàn Tiền'),
                                                          ],
                                                        ),
                                                        content: Text(
                                                          'Bạn có chắc chắn muốn hủy đơn #$currentOrderId và yêu cầu hoàn tiền (Refund) từ SMSPool không?',
                                                          style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textBody),
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(ctx).pop(false),
                                                            child: const Text('Đóng', style: TextStyle(color: AppColors.textMuted)),
                                                          ),
                                                          ElevatedButton(
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor: const Color(0xFFEF4444),
                                                              foregroundColor: Colors.white,
                                                            ),
                                                            onPressed: () => Navigator.of(ctx).pop(true),
                                                            child: const Text('Hoàn tiền', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                          ),
                                                        ],
                                                      ),
                                                    );

                                                    if (confirm != true) return;

                                                    setDialogState(() {
                                                      isRefunding = true;
                                                    });

                                                    try {
                                                      final res = await SmsPoolService().cancelOrder(orderId: currentOrderId!);
                                                      if (res['success'] == 1) {
                                                        otpTimer?.cancel();
                                                        otpTimer = null;
                                                        final canceledOrderId = currentOrderId;
                                                        setDialogState(() {
                                                          currentOrderId = null;
                                                          latestOtpCode = null;
                                                        });

                                                        // Cập nhật lưu trữ database/json
                                                        final currentP = _personas[persona.ip] ?? persona;
                                                        final updated = currentP.copyWith(smsOrderId: null);
                                                        await _personaService.updatePersona(updated);
                                                        if (mounted) {
                                                          setState(() {
                                                            _personas[persona.ip] = updated;
                                                          });
                                                        }

                                                        if (dialogCtx.mounted) {
                                                          AppToast.success(dialogCtx, 'Đã hủy đơn #$canceledOrderId và hoàn tiền thành công!');
                                                        }
                                                      } else {
                                                        if (dialogCtx.mounted) {
                                                          final errMsg = res['message']?.toString();
                                                          AppToast.error(dialogCtx, (errMsg != null && errMsg.isNotEmpty) ? errMsg : 'Không thể hủy đơn. Đơn có thể đã hoàn thành hoặc hết hạn.');
                                                        }
                                                      }
                                                    } catch (e) {
                                                      if (dialogCtx.mounted) {
                                                        AppToast.error(dialogCtx, 'Lỗi khi yêu cầu hoàn tiền: $e');
                                                      }
                                                    } finally {
                                                      setDialogState(() {
                                                        isRefunding = false;
                                                      });
                                                    }
                                                  },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                    ),
                  ),

                  // 3. MODAL FOOTER (Nền tối riêng biệt và border top sắc nét)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF070C18),
                      border: Border(
                        top: BorderSide(color: AppColors.borderLight, width: 1.2),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
                          child: const Text('Hủy', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final newName = nameCtrl.text.trim();
                                  if (newName.isEmpty) {
                                    AppToast.warning(context, 'Tên nhân vật không được để trống');
                                    return;
                                  }
                                  final newAge = int.tryParse(ageCtrl.text.trim()) ?? persona.age;
                                  final currentP = _personas[persona.ip] ?? persona;
                                  final updated = PersonaProfile(
                                    ip: persona.ip,
                                    name: newName,
                                    age: newAge,
                                    gender: selectedGender,
                                    bio: bioCtrl.text.trim(),
                                    avatarPrompt: promptCtrl.text.trim(),
                                    avatarUrl: currentP.avatarUrl,
                                    externalDeviceAddress: externalDeviceCtrl.text.trim(),
                                    useExternalDevice: useExternalDevice,
                                    avdName: selectedAvd,
                                    deviceType: selectedDeviceType,
                                    agentInfo: agentInfoCtrl.text.trim(),
                                    email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
                                    phoneNumber: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                                    autoSyncPhoneToDevice: autoSyncPhoneToDevice,
                                    smsOrderId: currentOrderId,
                                  );

                                  setDialogState(() {
                                    isSaving = true;
                                  });

                                  try {
                                    await _personaService.updatePersona(updated);
                                    if (mounted) {
                                      setState(() {
                                        _personas[updated.ip] = updated;
                                      });
                                      AppToast.success(context, 'Đã lưu nhân vật cho IP ${updated.ip} vào Database!');
                                    }
                                    if (dialogCtx.mounted) {
                                      Navigator.of(dialogCtx).pop();
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      AppToast.error(context, 'Lỗi lưu database: $e');
                                    }
                                  } finally {
                                    if (dialogCtx.mounted) {
                                      setDialogState(() {
                                        isSaving = false;
                                      });
                                    }
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF070B14)),
                                )
                              : const Icon(Icons.check_rounded, size: 15),
                          label: Text(
                            isSaving ? 'Đang lưu...' : 'Lưu lại',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: const Color(0xFF070B14),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
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
    ).then((_) {
      otpTimer?.cancel();
      otpTimer = null;
      _loadPersonas();
    });
  }



  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final servers = serverProvider.servers;
    final selectedServer = serverProvider.selectedServer;

    // Gom danh sách IP contact card
    final List<_ContactIpItem> allIpCards = [];

    for (final s in servers) {
      final ips = serverProvider.getIpsForServer(s);
      final isSelected = selectedServer != null && (selectedServer.id == s.id || selectedServer.serverIp == s.serverIp);

      for (int i = 0; i < ips.length; i++) {
        final ip = ips[i];
        final isMain = ip == s.serverIp;

        allIpCards.add(
          _ContactIpItem(
            ip: ip,
            isMain: isMain,
            server: s,
            isCurrentServer: isSelected,
          ),
        );
      }
    }

    // Đảm bảo tất cả các IP đã tạo Persona đều xuất hiện trong danh sách card
    final existingIps = allIpCards.map((e) => e.ip).toSet();
    final defaultServer = selectedServer ?? (servers.isNotEmpty ? servers.first : ServerModel(
      id: 'srv_default',
      name: 'Sân khấu hồ sơ',
      serverIp: '127.0.0.1',
    ));

    for (final personaIp in _personas.keys) {
      if (!existingIps.contains(personaIp)) {
        // Tìm xem IP này có khớp với server nào không
        final matchedServer = servers.firstWhere(
          (s) => s.serverIp == personaIp,
          orElse: () => defaultServer,
        );
        allIpCards.add(
          _ContactIpItem(
            ip: personaIp,
            isMain: personaIp == matchedServer.serverIp,
            server: matchedServer,
            isCurrentServer: true,
          ),
        );
        existingIps.add(personaIp);
      }
    }

    final allTargetIps = allIpCards.map((e) => e.ip).toSet().toList();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. TOP TOOLBAR (Height 66px - aligns with Left Sidebar Brand Header)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.contact_mail_rounded, color: AppColors.primaryLight, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Profiles / IP Contact Cards',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedServer != null
                            ? 'Danh sách các IP trỏ vào VPS Sân khấu [${selectedServer.name}] (${selectedServer.serverIp})'
                            : 'Danh sách các đầu IP đang trỏ vào hệ thống Sân khấu SSH',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nút "Sửa chữa Profiles / Browser" giúp user giải phóng lock và sửa lỗi treo Chrome
                    OutlinedButton.icon(
                      onPressed: _isRepairing
                          ? null
                          : () async {
                              final currentContext = context;
                              setState(() {
                                _isRepairing = true;
                              });
                              AppToast.info(currentContext, 'Đang quét và sửa chữa môi trường profiles...');
                              try {
                                final res = await _socks5Service.repairBrowserProfilesAndEnvironment();
                                if (currentContext.mounted) {
                                  final msg = res['message']?.toString() ?? 'Đã hoàn tất sửa chữa profiles!';
                                  AppToast.success(currentContext, msg);
                                }
                              } catch (e) {
                                if (currentContext.mounted) {
                                  AppToast.error(currentContext, 'Lỗi sửa chữa: $e');
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isRepairing = false;
                                  });
                                }
                              }
                            },
                      icon: _isRepairing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan),
                            )
                          : const Icon(Icons.build_circle_outlined, size: 16, color: AppColors.accentCyan),
                      label: Text(
                        _isRepairing ? 'Đang sửa...' : 'Sửa lỗi Profile / Browser',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accentCyan),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.accentCyan, width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),


                    const SizedBox(width: 10),

                    // Nút "AI tạo profiles" thay thế tìm kiếm và quét lại IP
                    ElevatedButton.icon(
                      onPressed: _isGeneratingPersonas
                          ? null
                          : () => _handleGeneratePersonas(allTargetIps),
                      icon: _isGeneratingPersonas
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF070B14)),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: Text(
                        _isGeneratingPersonas ? 'Đang tạo profiles...' : 'AI tạo profiles',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: const Color(0xFF070B14),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. CONTACT CARDS GRID VIEW
          Expanded(
            child: allIpCards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.contact_mail_outlined, size: 54, color: AppColors.textDim.withValues(alpha: 0.5)),
                        const SizedBox(height: 14),
                        const Text(
                          'Chưa tìm thấy IP nào trỏ vào Sân khấu',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hãy kiểm tra lại cấu hình kết nối SSH trong mục Cấu hình',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Tính toán số cột responsive linh hoạt: tối thiểu 1 cột, tối đa 5 cột
                      // Mỗi card có độ rộng lý tưởng khoảng 300 - 360px
                      int crossAxisCount = (constraints.maxWidth / 320).floor();
                      if (crossAxisCount < 1) crossAxisCount = 1;
                      if (crossAxisCount > 5) crossAxisCount = 5;

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          mainAxisExtent: 250,
                        ),
                        itemCount: allIpCards.length,
                        itemBuilder: (context, idx) {
                          final item = allIpCards[idx];
                          return _buildContactCard(item);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Khung danh thiếp Contact Card cho từng IP
  Widget _buildContactCard(_ContactIpItem item) {
    final socks5 = context.watch<Socks5ProxyService>();
    final isBrowserRunning = socks5.isBrowserRunningForIp(item.ip);
    final isDeviceRunning = socks5.isDeviceRunningForIp(item.ip);
    final isAnyRunning = isBrowserRunning || isDeviceRunning;
    final isAlias = !item.isMain;
    final persona = _personas[item.ip];

    final Color cardBorderColor;
    final Color cardBgColor;
    final Color badgeBgColor;
    final Color badgeTextColor;
    final String statusText;
    final Color statusDotColor;

    if (isAnyRunning) {
      if (isAlias) {
        cardBorderColor = AppColors.accent;
        cardBgColor = const Color(0xFF091E1A);
        badgeBgColor = AppColors.accent.withValues(alpha: 0.2);
        badgeTextColor = AppColors.accent;
        if (isBrowserRunning && isDeviceRunning) {
          statusText = 'Browser & Device đang chạy';
        } else if (isDeviceRunning) {
          statusText = 'Mobile Device đang mở';
        } else {
          statusText = 'Trình duyệt đang mở';
        }
        statusDotColor = AppColors.accent;
      } else {
        cardBorderColor = AppColors.primaryLight;
        cardBgColor = const Color(0xFF1C1908);
        badgeBgColor = AppColors.primary.withValues(alpha: 0.2);
        badgeTextColor = AppColors.primaryLight;
        if (isBrowserRunning && isDeviceRunning) {
          statusText = 'Browser & Device đang chạy';
        } else if (isDeviceRunning) {
          statusText = 'Mobile Device đang mở';
        } else {
          statusText = 'Trình duyệt đang mở';
        }
        statusDotColor = AppColors.primaryLight;
      }
    } else {
      cardBorderColor = item.isCurrentServer ? AppColors.primary.withValues(alpha: 0.4) : AppColors.borderDark;
      cardBgColor = AppColors.cardBg;
      badgeBgColor = item.isMain ? AppColors.accent.withValues(alpha: 0.12) : AppColors.sidebarBg;
      badgeTextColor = item.isMain ? AppColors.accent : AppColors.textDim;
      statusText = isAlias ? 'Sẵn sàng kết nối Alias' : 'Sẵn sàng kết nối';
      statusDotColor = item.isMain ? AppColors.accent : AppColors.textDim;
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cardBorderColor,
          width: isAnyRunning ? 1.8 : (item.isCurrentServer ? 1.3 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: isAnyRunning
                ? (isAlias ? AppColors.accent.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.2))
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: isAnyRunning ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card (Tên máy chủ + Trạng thái Loại IP)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isAnyRunning
                  ? (isAlias ? const Color(0xFF0B2923) : const Color(0xFF26200A))
                  : (item.isCurrentServer ? AppColors.primary.withValues(alpha: 0.12) : AppColors.sidebarBg),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: isAnyRunning ? cardBorderColor.withValues(alpha: 0.4) : AppColors.borderDark, width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 15,
                  color: isAnyRunning
                      ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                      : (item.isCurrentServer ? AppColors.primaryLight : AppColors.textDim),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isAnyRunning
                          ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                          : (item.isCurrentServer ? AppColors.primaryLight : AppColors.textWhite),
                    ),
                  ),
                ),
                // Nút nhỏ AI tạo riêng profile cho IP này
                () {
                  final isGeneratingThis = _generatingSingleProfileIps.contains(item.ip);
                  return Tooltip(
                    message: isGeneratingThis
                        ? 'Đang tạo profile cho ${item.ip}...'
                        : (persona == null ? 'AI tạo profile riêng cho IP này' : 'AI tạo lại profile mới cho IP này'),
                    child: InkWell(
                      onTap: (isGeneratingThis || _isGeneratingPersonas)
                          ? null
                          : () => _handleGenerateSinglePersona(item.ip),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isGeneratingThis
                              ? AppColors.primary.withValues(alpha: 0.25)
                              : AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: isGeneratingThis ? 0.8 : 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isGeneratingThis)
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppColors.primaryLight,
                                ),
                              )
                            else
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 11,
                                color: AppColors.primaryLight,
                              ),
                            const SizedBox(width: 4),
                            Text(
                              isGeneratingThis ? 'Đang tạo...' : 'AI Profile',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }(),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isAnyRunning ? cardBorderColor.withValues(alpha: 0.5) : AppColors.borderDark,
                    ),
                  ),
                  child: Text(
                    item.isMain ? 'IP GỐC' : 'ALIAS IP',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: badgeTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body Card (IP Avatar + Persona Profile Specs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Avatar badge + Name / IP / Status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar badge có tương tác: Bấm vào mở dialog phóng to avatar rõ nét
                      () {
                        final isGeneratingAvatar = _generatingAvatarIps.contains(item.ip);
                        final hasCustomAvatar = persona?.avatarUrl != null && persona!.avatarUrl!.isNotEmpty;

                        return Tooltip(
                          message: persona != null
                              ? 'Bấm để phóng to xem rõ nét ảnh avatar của ${persona.name}'
                              : 'Chưa tạo nhân vật',
                          child: InkWell(
                            onTap: (persona == null)
                                ? null
                                : () => _showAvatarPreviewDialog(persona),
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isAnyRunning
                                        ? (isAlias ? AppColors.accent.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15))
                                        : AppColors.inputBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isGeneratingAvatar
                                          ? AppColors.primaryLight
                                          : (isAnyRunning
                                              ? cardBorderColor
                                              : (item.isMain ? AppColors.accent.withValues(alpha: 0.5) : AppColors.borderDark)),
                                      width: 1.3,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: hasCustomAvatar
                                        ? (persona.avatarUrl!.startsWith('http')
                                            ? Image.network(
                                                persona.avatarUrl!,
                                                key: ValueKey(persona.avatarUrl),
                                                fit: BoxFit.cover,
                                                errorBuilder: (ctx, err, stack) => _buildFallbackAvatarIcon(persona, isAnyRunning, isAlias, item.isMain),
                                              )
                                            : Image.file(
                                                File(persona.avatarUrl!),
                                                key: ValueKey(persona.avatarUrl),
                                                fit: BoxFit.cover,
                                                errorBuilder: (ctx, err, stack) => _buildFallbackAvatarIcon(persona, isAnyRunning, isAlias, item.isMain),
                                              ))
                                        : _buildFallbackAvatarIcon(persona, isAnyRunning, isAlias, item.isMain),
                                  ),
                                ),

                                if (isGeneratingAvatar)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                                        ),
                                      ),
                                    ),
                                  )
                                else if (persona != null)
                                  Positioned(
                                    right: -3,
                                    bottom: -3,
                                    child: Tooltip(
                                      message: 'Bấm để AI tạo lại avatar',
                                      child: InkWell(
                                        onTap: () => _handleGenerateAvatar(persona),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: AppColors.cardBg,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(2.5),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.95),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.auto_awesome_rounded, size: 9, color: Color(0xFF070B14)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tên nhân vật hoặc hiển thị Chưa tạo (Có thể bấm để mở cấu hình)
                            InkWell(
                              onTap: () {
                                final p = persona ?? PersonaProfile(
                                  ip: item.ip,
                                  name: 'Nhân vật ${item.ip}',
                                  age: 25,
                                  gender: 'Nam',
                                  bio: 'Nhân vật tự động cho địa chỉ IP ${item.ip}',
                                  avatarPrompt: '',
                                );
                                _showPersonaDetails(p);
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      persona?.name ?? 'Chưa tạo nhân vật',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: persona != null ? AppColors.textWhite : AppColors.textDim,
                                      ),
                                    ),
                                  ),
                                  if (persona != null) ...[
                                    Container(
                                      height: 18,
                                      padding: const EdgeInsets.symmetric(horizontal: 5),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 0.6),
                                      ),
                                      child: Text(
                                        '${persona.gender} · ${persona.age}t',
                                        style: const TextStyle(fontSize: 9.5, color: AppColors.primaryLight, fontWeight: FontWeight.bold, height: 1.1),
                                      ),
                                    ),
                                    if (persona.useExternalDevice && (persona.externalDeviceAddress?.trim().isNotEmpty ?? false)) ...[
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: 'Thiết bị ngoại vi: ${persona.externalDeviceAddress}',
                                        child: Container(
                                          height: 18,
                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5), width: 0.6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Icon(Icons.wifi_tethering_rounded, size: 10.5, color: Color(0xFF38BDF8)),
                                              SizedBox(width: 2.5),
                                              Text(
                                                'EXT',
                                                style: TextStyle(fontSize: 9, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, height: 1.1),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],

                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            // IP và Trạng thái kết nối
                            Row(
                              children: [
                                InkWell(
                                  onTap: () => _copyToClipboard(item.ip, 'IP'),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        item.ip,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'monospace',
                                          color: isAnyRunning
                                              ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(Icons.copy_rounded, size: 10.5, color: AppColors.textDim),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: statusDotColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    statusText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: statusDotColor,
                                      fontWeight: isAnyRunning ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Row 2: Bio kèm Nút Số điện thoại và Email ngay bên dưới
                  if (persona != null) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.inputBg.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.borderDark.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _showPersonaDetails(persona),
                                      child: SingleChildScrollView(
                                        child: Text(
                                          persona.bio,
                                          style: const TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.3),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  () {
                                    final isGeneratingThis = _generatingSingleProfileIps.contains(item.ip);
                                    return Tooltip(
                                      message: 'AI tạo lại nhân vật cho IP này',
                                      child: InkWell(
                                        onTap: (isGeneratingThis || _isGeneratingPersonas)
                                            ? null
                                            : () => _handleGenerateSinglePersona(item.ip),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          width: 26,
                                          height: 26,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                          ),
                                          child: isGeneratingThis
                                              ? const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
                                                )
                                              : const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.primaryLight),
                                        ),
                                      ),
                                    );
                                  }(),
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: 'Xem chi tiết & Chỉnh sửa nhân vật',
                                    child: InkWell(
                                      onTap: () => _showPersonaDetails(persona),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        width: 26,
                                        height: 26,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                        ),
                                        child: const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.primaryLight),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if ((persona.phoneNumber != null && persona.phoneNumber!.isNotEmpty) ||
                              (persona.email != null && persona.email!.isNotEmpty)) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                if (persona.phoneNumber != null && persona.phoneNumber!.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () => _copyToClipboard(persona.phoneNumber!, 'Số điện thoại'),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Tooltip(
                                      message: 'Số điện thoại: ${persona.phoneNumber}${persona.autoSyncPhoneToDevice ? ' (Đã bật tự động gắn vào máy)' : ''} (Bấm để chép)',
                                      child: Container(
                                        height: 20,
                                        width: 20,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5), width: 0.6),
                                        ),
                                        child: const Icon(Icons.phone_rounded, size: 11, color: Color(0xFF34D399)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (persona.email != null && persona.email!.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () => _copyToClipboard(persona.email!, 'Email'),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Tooltip(
                                      message: 'Email: ${persona.email} (Bấm để chép)',
                                      child: Container(
                                        height: 20,
                                        width: 20,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5), width: 0.6),
                                        ),
                                        child: const Icon(Icons.email_rounded, size: 11, color: Color(0xFFA78BFA)),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else ...[
                    // Trạng thái Card mới tinh "Chưa tạo nhân vật": Có nút nổi bật "AI tạo Profile" và nút nhập thủ công
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderDark.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Nút to nổi bật: AI tạo tự động hồ sơ cho riêng Card này
                            () {
                              final isGeneratingThis = _generatingSingleProfileIps.contains(item.ip);
                              return SizedBox(
                                width: double.infinity,
                                height: 28,
                                child: ElevatedButton.icon(
                                  onPressed: (isGeneratingThis || _isGeneratingPersonas)
                                      ? null
                                      : () => _handleGenerateSinglePersona(item.ip),
                                  icon: isGeneratingThis
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: Color(0xFF070B14),
                                          ),
                                        )
                                      : const Icon(Icons.auto_awesome_rounded, size: 13),
                                  label: Text(
                                    isGeneratingThis ? 'Đang tạo profile...' : 'AI tạo Profile cho IP này',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: const Color(0xFF070B14),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              );
                            }(),
                            const SizedBox(height: 5),
                            // Nút phụ hoặc bấm dòng chữ nhập thủ công
                            InkWell(
                              onTap: () {
                                final p = PersonaProfile(
                                  ip: item.ip,
                                  name: 'Nhân vật ${item.ip}',
                                  age: 25,
                                  gender: 'Nam',
                                  bio: 'Nhân vật tự động cho địa chỉ IP ${item.ip}',
                                  avatarPrompt: '',
                                );
                                _showPersonaDetails(p);
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_note_rounded, size: 12, color: AppColors.textDim),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Hoặc tự điền thủ công',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textDim,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Footer Action Bar: 2 nút đặt cạnh nhau (Mở/Đóng trình duyệt & Mở/Đóng device)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: isAnyRunning
                  ? (isAlias ? const Color(0xFF09211C) : const Color(0xFF211D09))
                  : AppColors.sidebarBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
              border: Border(top: BorderSide(color: isAnyRunning ? cardBorderColor.withValues(alpha: 0.3) : AppColors.borderDark, width: 0.8)),
            ),
            child: Row(
              children: [
                // 1. NÚT MỞ / ĐÓNG TRÌNH DUYỆT (BROWSER)
                Expanded(
                  child: () {
                    final isOpening = _openingIps.contains(item.ip);
                    final isClosing = _closingIps.contains(item.ip);
                    final isBusy = isOpening || isClosing;

                    if (isBrowserRunning) {
                      return ElevatedButton.icon(
                        onPressed: isBusy
                            ? null
                            : () async {
                                setState(() {
                                  _closingIps.add(item.ip);
                                });
                                try {
                                  await _socks5Service.closeBrowserForIp(item.ip);
                                  if (mounted) {
                                    AppToast.info(context, 'Đã đóng trình duyệt cho ${item.ip}');
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    AppToast.error(context, 'Lỗi khi đóng trình duyệt: $e');
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _closingIps.remove(item.ip);
                                    });
                                  }
                                }
                              },
                        icon: isClosing
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                              )
                            : const Icon(Icons.close_rounded, size: 14),
                        label: Text(
                          isClosing ? 'Đang đóng...' : 'Đóng browser',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }

                    return ElevatedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () async {
                              setState(() {
                                _openingIps.add(item.ip);
                              });
                              AppToast.info(context, 'Đang mở trình duyệt cho ${item.ip}...');
                              try {
                                await _socks5Service.launchBrowserWithSocks5(
                                  server: item.server,
                                  ip: item.ip,
                                );
                                if (mounted) {
                                  AppToast.success(context, 'Đã mở trình duyệt qua ${item.ip}');
                                }
                              } catch (e) {
                                if (mounted) {
                                  AppToast.error(context, 'Lỗi mở trình duyệt: $e');
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _openingIps.remove(item.ip);
                                  });
                                }
                              }
                            },
                      icon: isOpening
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF070B14)),
                            )
                          : const Icon(Icons.open_in_browser_rounded, size: 14),
                      label: Text(
                        isOpening ? 'Đang mở...' : 'Mở browser',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: const Color(0xFF070B14),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }(),
                ),

                const SizedBox(width: 6),

                // 2. NÚT MỞ / ĐÓNG MOBILE DEVICE
                Expanded(
                  child: () {
                    final isOpeningDevice = _openingDeviceIps.contains(item.ip);
                    final isClosingDevice = _closingDeviceIps.contains(item.ip);
                    final isDeviceBusy = isOpeningDevice || isClosingDevice;
                    final targetRemoteDevice = (persona != null && persona.useExternalDevice && (persona.externalDeviceAddress?.trim().isNotEmpty ?? false))
                        ? persona.externalDeviceAddress!.trim()
                        : null;

                    if (isDeviceRunning) {
                      return ElevatedButton.icon(
                        onPressed: isDeviceBusy
                            ? null
                            : () async {
                                setState(() {
                                  _closingDeviceIps.add(item.ip);
                                });
                                try {
                                  await _socks5Service.closeDeviceForIp(item.ip);
                                  if (mounted) {
                                    AppToast.info(context, 'Đã đóng mobile device cho ${item.ip}');
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    AppToast.error(context, 'Lỗi khi đóng device: $e');
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _closingDeviceIps.remove(item.ip);
                                    });
                                  }
                                }
                              },
                        icon: isClosingDevice
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                              )
                            : const Icon(Icons.phone_disabled_rounded, size: 14),
                        label: Text(
                          isClosingDevice ? 'Đang đóng...' : 'Đóng device',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC53030),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }

                    final bool isExt = targetRemoteDevice != null;
                    final currentP = _personas[item.ip] ?? persona;
                    final sanitizedIp = item.ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
                    final expectedNameAvd = generatePersonaAvdName(ip: item.ip, personaName: currentP?.name);
                    final legacyPersonaAvd = 'Pixel_10_Pro_persona_$sanitizedIp';
                    final bool hasLocalAvd = (currentP?.avdName != null &&
                            currentP!.avdName!.isNotEmpty &&
                            (_availableAvds.contains(currentP.avdName) || currentP.avdName!.contains('persona_') || _availableAvds.isEmpty)) ||
                        _availableAvds.contains(expectedNameAvd) ||
                        _availableAvds.contains(legacyPersonaAvd);
                    final bool hasDeviceSetup = isExt || hasLocalAvd;

                    // Nếu chưa có thiết bị máy ảo, hiện nút "Cài đặt máy ảo" bấm vào mở modal hồ sơ
                    if (!hasDeviceSetup) {
                      return ElevatedButton.icon(
                        onPressed: () {
                          final p = currentP ?? PersonaProfile(
                            ip: item.ip,
                            name: 'Nhân vật ${item.ip}',
                            age: 25,
                            gender: 'Nam',
                            bio: 'Nhân vật tự động cho địa chỉ IP ${item.ip}',
                            avatarPrompt: '',
                          );
                          _showPersonaDetails(p);
                        },
                        icon: const Icon(Icons.phonelink_setup_rounded, size: 14),
                        label: const Text(
                          'Cài đặt máy ảo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }

                    return ElevatedButton.icon(
                      onPressed: isDeviceBusy
                          ? null
                          : () async {
                              setState(() {
                                _openingDeviceIps.add(item.ip);
                              });
                              AppToast.info(
                                context,
                                isExt
                                    ? 'Đang kết nối thiết bị ngoại vi ($targetRemoteDevice)...'
                                    : 'Đang khởi động mobile device cho ${item.ip}...',
                              );
                              try {
                                await _socks5Service.launchDeviceWithSocks5(
                                  server: item.server,
                                  ip: item.ip,
                                  remoteDeviceAddress: targetRemoteDevice,
                                  avdName: currentP?.avdName,
                                  deviceType: currentP?.deviceType ?? 'mobile',
                                  phoneNumber: currentP?.phoneNumber,
                                  autoSyncPhone: currentP?.autoSyncPhoneToDevice ?? false,
                                );
                                if (mounted) {
                                  AppToast.success(
                                    context,
                                    isExt
                                        ? 'Đã kết nối ngoại vi $targetRemoteDevice'
                                        : 'Đã mở ${currentP?.deviceType == 'tablet' ? 'tablet' : 'mobile'} device qua ${item.ip}',
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  AppToast.error(context, 'Lỗi mở mobile device: $e');
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _openingDeviceIps.remove(item.ip);
                                  });
                                }
                              }
                            },
                      icon: isOpeningDevice
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                            )
                          : Icon(isExt ? Icons.wifi_tethering_rounded : Icons.smartphone_rounded, size: 14),
                      label: Text(
                        isOpeningDevice ? 'Đang mở...' : (isExt ? 'Mở ngoại vi' : 'Mở device'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isExt ? const Color(0xFF0284C7) : const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackAvatarIcon(PersonaProfile? persona, bool isAnyRunning, bool isAlias, bool isMain) {
    return Center(
      child: Icon(
        persona != null
            ? (persona.gender.toLowerCase() == 'nữ' ? Icons.face_3_rounded : Icons.face_rounded)
            : (isAnyRunning ? Icons.language_rounded : Icons.fingerprint_rounded),
        color: isAnyRunning
            ? (isAlias ? AppColors.accent : AppColors.primaryLight)
            : (isMain ? AppColors.accent : AppColors.primaryLight),
        size: 22,
      ),
    );
  }
}

class _ContactIpItem {
  final String ip;
  final bool isMain;
  final ServerModel server;
  final bool isCurrentServer;

  _ContactIpItem({
    required this.ip,
    required this.isMain,
    required this.server,
    required this.isCurrentServer,
  });
}
