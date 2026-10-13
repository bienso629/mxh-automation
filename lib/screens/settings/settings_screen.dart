import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/cli_scanner_service.dart';
import '../../core/services/local_config_service.dart';
import '../../core/services/native_ssh_service.dart';
import '../../core/services/persona_service.dart';
import '../../core/services/socks5_proxy_service.dart';
import '../../core/services/windows_hypervisor_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/model_picker_dialog.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/persona_profile_model.dart';
import '../../models/server_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/server_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _modelCtrl = TextEditingController(text: 'glm-5.3');
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'https://api.mitom.ai/v1');
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _maxDevicesCtrl = TextEditingController(text: '2');
  bool _isDeviceExecutionMode = false; // false: Trình duyệt (Browser), true: Thiết bị (Device/AVD)

  // AI Engine Mode: 'proxy' (Cloud Proxy AI) hoặc 'cli' (Local CLI Agent)
  String _aiEngineType = 'proxy';
  String _activeCliAgent = 'antigravity-cli';
  List<LocalCliAgent> _installedCliAgents = [];
  bool _isScanningCli = false;
  bool _isRepairing = false;

  // Hyper-V / Windows Hypervisor Platform (chỉ Windows)
  final WindowsHypervisorService _hypervisor = WindowsHypervisorService();
  HypervisorState _hypervisorState = HypervisorState.unknown;
  bool _isTogglingHypervisor = false;

  @override
  void initState() {
    super.initState();
    _loadGlobalConfig();
    _scanCliAgents();
    _refreshHypervisorState();
  }

  Future<void> _refreshHypervisorState() async {
    if (!_hypervisor.isSupported) return;
    final state = await _hypervisor.getState();
    if (mounted && _hypervisorState != HypervisorState.pendingRestart) {
      setState(() => _hypervisorState = state);
    }
  }

  Future<void> _toggleHypervisor(bool enable) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(enable ? 'Bật Hyper-V cho máy ảo' : 'Tắt Hyper-V'),
        content: Text(enable
            ? 'Windows sẽ hỏi quyền Administrator để bật Hyper-V và Windows Hypervisor Platform giúp máy ảo Android chạy nhanh hơn.\n\nSau khi bật xong cần khởi động lại máy.'
            : 'Windows sẽ hỏi quyền Administrator để tắt Hyper-V và Windows Hypervisor Platform.\n\nSau khi tắt xong cần khởi động lại máy.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đồng ý')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isTogglingHypervisor = true);
    final ok = await _hypervisor.setEnabled(enable);
    if (!mounted) return;
    setState(() {
      _isTogglingHypervisor = false;
      if (ok) _hypervisorState = HypervisorState.pendingRestart;
    });

    if (!ok) {
      AppToast.error(context, 'Không thể ${enable ? 'bật' : 'tắt'} Hyper-V. Bạn đã từ chối quyền Administrator hoặc Windows không hỗ trợ (bản Home cũ, chưa bật ảo hóa trong BIOS).');
      return;
    }

    final restart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cần khởi động lại máy'),
        content: Text('Đã ${enable ? 'bật' : 'tắt'} Hyper-V thành công. Khởi động lại máy ngay để áp dụng?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Để sau')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Khởi động lại')),
        ],
      ),
    );
    if (restart == true) {
      await _hypervisor.restartNow();
    }
  }

  Widget _buildHypervisorToggle() {
    final enabled = _hypervisorState == HypervisorState.enabled;
    final pending = _hypervisorState == HypervisorState.pendingRestart;
    final String subtitle;
    if (pending) {
      subtitle = 'Đã thay đổi. Vui lòng khởi động lại máy để áp dụng.';
    } else if (_hypervisorState == HypervisorState.unknown) {
      subtitle = 'Không xác định được trạng thái. Bạn vẫn có thể thử bật.';
    } else {
      subtitle = enabled
          ? 'Máy ảo Android đang được tăng tốc phần cứng qua Windows Hypervisor Platform'
          : 'Chưa bật tăng tốc. Máy ảo Android sẽ chạy rất chậm hoặc không khởi động được';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: enabled ? AppColors.accent.withValues(alpha: 0.4) : AppColors.borderDark),
      ),
      child: Row(
        children: [
          Icon(Icons.memory_rounded, size: 18, color: enabled ? AppColors.accent : AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tăng tốc máy ảo (Hyper-V / WHPX)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (_isTogglingHypervisor)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            SizedBox(
              height: 22,
              child: Switch(
                value: enabled,
                onChanged: pending ? null : (val) => _toggleHypervisor(val),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _maxDevicesCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanCliAgents() async {
    setState(() {
      _isScanningCli = true;
    });
    try {
      final agents = await CliScannerService().scanInstalledAgents();
      if (mounted) {
        setState(() {
          _installedCliAgents = agents;
          _isScanningCli = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isScanningCli = false;
        });
      }
    }
  }

  Future<void> _loadGlobalConfig() async {
    try {
      final cfg = await _api.getConfig();
      final aiModel = cfg['ai_model']?.toString() ?? '';
      if (aiModel.isNotEmpty) {
        _modelCtrl.text = aiModel;
      }
      if (cfg['proxy_base_url'] != null) _baseUrlCtrl.text = cfg['proxy_base_url'].toString();
      if (cfg['proxy_api_key'] != null) _apiKeyCtrl.text = cfg['proxy_api_key'].toString();
      if (cfg['max_concurrent_devices'] != null) {
        _maxDevicesCtrl.text = cfg['max_concurrent_devices'].toString();
      }
      if (cfg['ai_engine_type'] != null) {
        _aiEngineType = cfg['ai_engine_type'].toString();
      }
      if (cfg['active_cli_agent'] != null) {
        _activeCliAgent = cfg['active_cli_agent'].toString();
      }
      if (cfg['default_execution_mode'] != null) {
        final mode = cfg['default_execution_mode'].toString();
        setState(() {
          _isDeviceExecutionMode = mode == 'device';
        });
      } else {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _saveAISettings() async {
    if (_aiEngineType == 'proxy') {
      final rawBaseUrl = _baseUrlCtrl.text.trim();
      if (rawBaseUrl.isNotEmpty && !LocalConfigService.isValidMitomProxyUrl(rawBaseUrl)) {
        AppToast.error(context, 'Chỉ chấp nhận Proxy Base URL thuộc domain *.mitom.ai (Ví dụ: https://api.mitom.ai/v1)');
        return;
      }
    }

    try {
      final cfg = await _api.getConfig();
      cfg['ai_engine_type'] = _aiEngineType;
      cfg['active_cli_agent'] = _activeCliAgent;
      cfg['ai_model'] = _modelCtrl.text.trim();
      cfg['proxy_base_url'] = _baseUrlCtrl.text.trim();
      cfg['proxy_api_key'] = _apiKeyCtrl.text.trim();
      final ok = await _api.saveConfig(cfg);
      if (mounted) {
        if (ok) {
          context.read<ServerProvider>().setGlobalAiModel(_modelCtrl.text.trim());
          AppToast.success(context, 'Đã lưu cấu hình AI Engine & Model thành công!');
        } else {
          AppToast.error(context, 'Lưu cấu hình AI thất bại!');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi: $e');
      }
    }
  }

  Future<void> _saveDeviceSettings() async {
    final maxDevParsed = int.tryParse(_maxDevicesCtrl.text.trim());
    if (maxDevParsed == null || maxDevParsed <= 0) {
      AppToast.warning(context, 'Số thiết bị tối đa phải là số nguyên dương lớn hơn 0 (ví dụ: 2)');
      return;
    }

    try {
      final cfg = await _api.getConfig();
      cfg['max_concurrent_devices'] = maxDevParsed;
      cfg['default_execution_mode'] = _isDeviceExecutionMode ? 'device' : 'browser';
      final ok = await _api.saveConfig(cfg);
      if (mounted) {
        if (ok) {
          AppToast.success(context, 'Đã lưu cấu hình thiết bị & máy ảo thành công!');
        } else {
          AppToast.error(context, 'Lưu cấu hình thiết bị thất bại!');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi: $e');
      }
    }
  }

  void _showAddEditServerDialog([ServerModel? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ipCtrl = TextEditingController(text: existing?.serverIp ?? '');
    final portCtrl = TextEditingController(text: existing?.sshPort.toString() ?? '22');
    final userCtrl = TextEditingController(text: existing?.sshUser ?? 'root');
    final passCtrl = TextEditingController(text: existing?.sshPass ?? '');
    showDialog(
      context: context,
      builder: (ctx) {
        bool isTesting = false;
        bool isServiceActive = false;
        bool isOperatingService = false;
        bool isCheckingStatus = existing != null && existing.serverIp.isNotEmpty;
        bool hasCheckedService = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            // Tự động kiểm tra trạng thái service khi mở modal chỉnh sửa Sân khấu
            if (isCheckingStatus && !hasCheckedService && existing != null && existing.serverIp.isNotEmpty) {
              Future.microtask(() async {
                try {
                  final active = await NativeSshService().getMultiIpSocks5Status(
                    host: existing.serverIp,
                    port: existing.sshPort,
                    user: existing.sshUser.isEmpty ? 'root' : existing.sshUser,
                    pass: existing.sshPass,
                  );
                  if (ctx.mounted) {
                    setModalState(() {
                      isServiceActive = active;
                      hasCheckedService = true;
                      isCheckingStatus = false;
                    });
                  }
                } catch (_) {
                  if (ctx.mounted) {
                    setModalState(() {
                      hasCheckedService = true;
                      isCheckingStatus = false;
                    });
                  }
                }
              });
            }

            return TaduDialog(
              minWidth: 540,
              maxWidth: 640,
              title: Row(
                children: [
                  const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 22),
                  const SizedBox(width: 8),
                  Text(existing != null ? 'Chỉnh Sửa Sân Khấu' : 'Thêm Sân Khấu Mới'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên Gợi Nhớ (Ví dụ: Web Production)',
                      prefixIcon: Icon(Icons.label_outline_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ipCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Địa Chỉ IP Sân Khấu',
                      prefixIcon: Icon(Icons.public_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: userCtrl,
                          decoration: const InputDecoration(labelText: 'SSH User (root)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật Khẩu SSH / Sudo',
                      prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // KHỐI QUẢN LÝ SERVICE MULTI-IP SOCKS5
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.sidebarBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.hub_rounded, size: 16, color: AppColors.primaryLight),
                            const SizedBox(width: 8),
                            const Text(
                              'Dịch Vụ Multi-IP SOCKS5 (Alias Routing)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                            const Spacer(),
                            if (isCheckingStatus)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.primaryLight),
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Đang kiểm tra...',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (hasCheckedService)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isServiceActive
                                      ? AppColors.accent.withValues(alpha: 0.15)
                                      : AppColors.danger.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isServiceActive
                                        ? AppColors.accent.withValues(alpha: 0.4)
                                        : AppColors.danger.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  isServiceActive ? 'Đang chạy' : 'Đang tắt',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isServiceActive ? AppColors.accent : AppColors.danger,
                                  ),
                                ),
                              ),
                          ],
                        ),
                            const SizedBox(height: 6),
                            const Text(
                              'Kích hoạt service systemd "multi-ip-socks5.service" trên VPS để trình duyệt nhận đúng IP Alias khi mở.',
                              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // Nút Bật / Tắt Service
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isServiceActive ? AppColors.danger : AppColors.primary,
                                    foregroundColor: isServiceActive ? Colors.white : const Color(0xFF070B14),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  icon: isOperatingService
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                        )
                                      : Icon(
                                          isServiceActive ? Icons.stop_circle_outlined : Icons.play_circle_fill_rounded,
                                          size: 15,
                                        ),
                                  label: Text(
                                    isOperatingService
                                        ? 'Đang xử lý...'
                                        : (isServiceActive ? 'Tắt Service (Disable)' : 'Bật Service (Enable)'),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: isOperatingService
                                      ? null
                                      : () async {
                                          final host = ipCtrl.text.trim();
                                          if (host.isEmpty) {
                                            AppToast.error(ctx, 'Vui lòng nhập IP Sân khấu!');
                                            return;
                                          }
                                          setModalState(() {
                                            isOperatingService = true;
                                          });
                                          try {
                                            final ssh = NativeSshService();
                                            final targetEnable = !isServiceActive;
                                            final ok = await ssh.toggleMultiIpSocks5Service(
                                              host: host,
                                              port: int.tryParse(portCtrl.text.trim()) ?? 22,
                                              user: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                                              pass: passCtrl.text.trim(),
                                              enable: targetEnable,
                                            );
                                            if (ctx.mounted) {
                                              if (ok) {
                                                setModalState(() {
                                                  isServiceActive = targetEnable;
                                                  hasCheckedService = true;
                                                });
                                                AppToast.success(
                                                  ctx,
                                                  targetEnable
                                                      ? 'Đã bật multi-ip-socks5.service thành công!'
                                                      : 'Đã tắt multi-ip-socks5.service thành công!',
                                                );
                                              } else {
                                                AppToast.error(ctx, 'Thao tác service thất bại! Kiểm tra SSH.');
                                              }
                                            }
                                          } catch (e) {
                                            if (ctx.mounted) {
                                              AppToast.error(ctx, 'Lỗi: $e');
                                            }
                                          } finally {
                                            if (ctx.mounted) {
                                              setModalState(() {
                                                isOperatingService = false;
                                              });
                                            }
                                          }
                                        },
                                ),
                                const SizedBox(width: 8),
                                // Nút Kiểm tra trạng thái
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textWhite,
                                    side: const BorderSide(color: AppColors.borderDark),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textDim),
                                  label: const Text('Kiểm tra trạng thái', style: TextStyle(fontSize: 11.5)),
                                  onPressed: isOperatingService
                                      ? null
                                      : () async {
                                          final host = ipCtrl.text.trim();
                                          if (host.isEmpty) {
                                            AppToast.error(ctx, 'Vui lòng nhập IP Sân khấu!');
                                            return;
                                          }
                                          setModalState(() {
                                            isOperatingService = true;
                                          });
                                          try {
                                            final ssh = NativeSshService();
                                            final active = await ssh.getMultiIpSocks5Status(
                                              host: host,
                                              port: int.tryParse(portCtrl.text.trim()) ?? 22,
                                              user: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                                              pass: passCtrl.text.trim(),
                                            );
                                            if (ctx.mounted) {
                                              setModalState(() {
                                                isServiceActive = active;
                                                hasCheckedService = true;
                                              });
                                              AppToast.info(
                                                ctx,
                                                active
                                                    ? 'Dịch vụ multi-ip-socks5 đang HOẠT ĐỘNG (Active)'
                                                    : 'Dịch vụ multi-ip-socks5 ĐANG TẮT (Inactive)',
                                              );
                                            }
                                          } catch (e) {
                                            if (ctx.mounted) {
                                              AppToast.error(ctx, 'Lỗi: $e');
                                            }
                                          } finally {
                                            if (ctx.mounted) {
                                              setModalState(() {
                                                isOperatingService = false;
                                              });
                                            }
                                          }
                                        },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              leadingActions: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isTesting ? AppColors.primaryLight : AppColors.textWhite,
                    side: BorderSide(
                      color: isTesting ? AppColors.primary : AppColors.borderDark,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
                        )
                      : const Icon(Icons.wifi_tethering_rounded, size: 16, color: AppColors.accent),
                  label: Text(
                    isTesting ? 'Đang test...' : 'Test kết nối',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: isTesting
                      ? null
                      : () async {
                          final host = ipCtrl.text.trim();
                          if (host.isEmpty) {
                            AppToast.error(ctx, 'Vui lòng nhập IP Sân khấu để kiểm tra!');
                            return;
                          }
                          setModalState(() {
                            isTesting = true;
                          });

                          try {
                            final ssh = NativeSshService();
                            final ok = await ssh.testConnection(
                              host: host,
                              port: int.tryParse(portCtrl.text.trim()) ?? 22,
                              user: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                              pass: passCtrl.text.trim(),
                            );

                            if (ctx.mounted) {
                              if (ok) {
                                AppToast.success(ctx, 'Kết nối SSH thành công đến $host!');
                              } else {
                                AppToast.error(ctx, 'Kết nối thất bại! Kiểm tra IP, Port hoặc Mật khẩu.');
                              }
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              AppToast.error(ctx, 'Lỗi kết nối: $e');
                            }
                          } finally {
                            if (ctx.mounted) {
                              setModalState(() {
                                isTesting = false;
                              });
                            }
                          }
                        },
                ),
              ],
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final ip = ipCtrl.text.trim();
                    if (ip.isEmpty) {
                      AppToast.error(context, 'Vui lòng nhập Địa chỉ IP Sân khấu');
                      return;
                    }
                    final newServer = ServerModel(
                      id: existing?.id ?? 'srv_${DateTime.now().millisecondsSinceEpoch}',
                      name: nameCtrl.text.trim().isEmpty ? ip : nameCtrl.text.trim(),
                      serverIp: ip,
                      sshPort: int.tryParse(portCtrl.text.trim()) ?? 22,
                      sshUser: userCtrl.text.trim().isEmpty ? 'root' : userCtrl.text.trim(),
                      sshPass: passCtrl.text.trim(),
                      aiModel: existing?.aiModel ?? 'glm-5.3',
                      remoteWorkDir: existing?.remoteWorkDir ?? '/opt/ai_agent',
                      apiPort: existing?.apiPort ?? 8000,
                      isSelected: existing?.isSelected ?? false,
                    );
                    final srvProvider = context.read<ServerProvider>();
                    final rootCtx = context;
                    Navigator.pop(ctx);
                    final ok = await srvProvider.addOrUpdateServer(newServer);
                    if (rootCtx.mounted) {
                      if (ok) {
                        AppToast.success(rootCtx, 'Đã lưu thông tin Sân khấu!');
                      } else {
                        AppToast.error(rootCtx, 'Lưu thông tin Sân khấu thất bại');
                      }
                    }
                  },
                  child: const Text('Lưu Sân Khấu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteServerConfirmDialog(ServerModel server) {
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 420,
        maxWidth: 500,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 22),
            SizedBox(width: 8),
            Text('Xác Nhận Xóa Sân Khấu'),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa Sân khấu "${server.name}" (${server.serverIp}:${server.sshPort}) khỏi danh sách kết nối không?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await context.read<ServerProvider>().deleteServer(server.id);
              if (mounted) {
                if (ok) {
                  AppToast.info(context, 'Đã xóa Sân khấu "${server.name}"');
                } else {
                  AppToast.error(context, 'Không thể xóa Sân khấu');
                }
              }
            },
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final gateway = context.watch<GatewayProvider>();
    final authProvider = context.watch<AuthProvider>();
    final isAdmin = authProvider.isAdmin;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // Topbar Header (Height 66px)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: AppColors.primaryLight, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Quản Lý Đa Sân Khấu & Cấu Hình AI',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        Text(
                          'Thêm, sửa, chuyển đổi Sân khấu SSH Remote và cấu hình AI Model (${serverProvider.currentAiModel})',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentCyan,
                        side: const BorderSide(color: AppColors.accentCyan),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text('Import Sân Khấu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _handleImportServerPackage(),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Thêm Sân Khấu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _showAddEditServerDialog(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // GROUP 1: MULTI-SERVER MANAGEMENT
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lan_rounded, size: 16, color: AppColors.accentCyan),
                          const SizedBox(width: 8),
                          const Text(
                            '1. Danh Sách Sân Khấu Remote (Multi-Server)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${serverProvider.servers.length} Sân khấu',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Servers Grid Cards
                  if (serverProvider.servers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: const Text('Chưa có Sân khấu nào được thêm', style: TextStyle(color: AppColors.textMuted)),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 490,
                        mainAxisExtent: 130,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: serverProvider.servers.length,
                      itemBuilder: (context, idx) {
                        final s = serverProvider.servers[idx];
                        final isSelected = serverProvider.selectedServer != null &&
                            (s.id == serverProvider.selectedServer!.id || s.serverIp == serverProvider.selectedServer!.serverIp);

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.cardBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.borderDark,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Hàng 1: Tên server & Badge Đang kết nối
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.dns_rounded, size: 18, color: isSelected ? AppColors.primaryLight : AppColors.textMuted),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            s.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ĐANG KẾT NỐI',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              // Hàng 2: SSH User & Main IP + Số lượng IP
                              Builder(
                                builder: (context) {
                                  final ips = serverProvider.getIpsForServer(s);
                                  final isLoading = serverProvider.isLoadingIps(s.id);
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${s.sshUser}@${s.serverIp}:${s.sshPort}',
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textMuted),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isLoading)
                                              const Padding(
                                                padding: EdgeInsets.only(right: 4),
                                                child: SizedBox(
                                                  width: 8,
                                                  height: 8,
                                                  child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.primaryLight),
                                                ),
                                              ),
                                            Text(
                                              isLoading ? 'Đang quét...' : '${ips.length} IPs',
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                              // Hàng 3: Actions (Chọn server, Sửa, Xóa)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      if (!isSelected)
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                          onPressed: () => serverProvider.selectServer(s),
                                          child: const Text('Chọn Sân Khấu', style: TextStyle(fontSize: 11)),
                                        )
                                      else
                                        const Text('Mặc định', style: TextStyle(fontSize: 11, color: AppColors.accent)),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.primaryLight,
                                          side: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.5)),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        ),
                                        icon: const Icon(Icons.archive_outlined, size: 13),
                                        label: const Text('Backup/Import', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                                        onPressed: () => _showServerBackupImportSheet(s, serverProvider),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16),
                                        onPressed: () => _showAddEditServerDialog(s),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                                        tooltip: 'Xóa Sân khấu',
                                        onPressed: () => _showDeleteServerConfirmDialog(s),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),

                  // GROUP 2: AI ENGINE & MODEL CONFIGURATION
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.psychology_rounded, size: 18, color: AppColors.primaryLight),
                                SizedBox(width: 8),
                                Text(
                                  '2. Cấu Hình Chế Độ AI Agent & Engine',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cardBg,
                                side: const BorderSide(color: AppColors.primary),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 16, color: AppColors.primaryLight),
                              label: const Text('Lưu Cấu Hình AI', style: TextStyle(color: AppColors.primaryLight)),
                              onPressed: _saveAISettings,
                            ),
                          ],
                        ),
                        const Divider(height: 20),

                        // CHỌN CHẾ ĐỘ AI ENGINE: Luôn có Proxy AI, chỉ Admin mới thấy thêm lựa chọn "Local CLI Agent (Máy Local)"
                        const Text(
                          'Chế Độ Vận Hành AI Agent',
                          style: TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _aiEngineType = 'proxy';
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: _aiEngineType == 'proxy'
                                          ? AppColors.primary.withValues(alpha: 0.15)
                                          : AppColors.bgDark,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _aiEngineType == 'proxy'
                                            ? AppColors.primary
                                            : AppColors.borderDark,
                                        width: _aiEngineType == 'proxy' ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.cloud_sync_rounded,
                                          size: 20,
                                          color: _aiEngineType == 'proxy' ? AppColors.primaryLight : AppColors.textMuted,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Proxy AI (Cloud LLM)',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: _aiEngineType == 'proxy' ? Colors.white : AppColors.textDim,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              const Text(
                                                'Gọi qua API Proxy Mitom (GLM-5.3, GPT-4o, DeepSeek...)',
                                                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_aiEngineType == 'proxy')
                                          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primaryLight),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (isAdmin) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _aiEngineType = 'cli';
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _aiEngineType == 'cli'
                                            ? AppColors.accent.withValues(alpha: 0.15)
                                            : AppColors.bgDark,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: _aiEngineType == 'cli'
                                              ? AppColors.accent
                                              : AppColors.borderDark,
                                          width: _aiEngineType == 'cli' ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.terminal_rounded,
                                            size: 20,
                                            color: _aiEngineType == 'cli' ? AppColors.accent : AppColors.textMuted,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      'Local CLI Agent (Máy Local)',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: _aiEngineType == 'cli' ? Colors.white : AppColors.textDim,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.accent.withValues(alpha: 0.2),
                                                        borderRadius: BorderRadius.circular(3),
                                                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                                                      ),
                                                      child: const Text(
                                                        'ADMIN',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppColors.accent,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                const Text(
                                                  'Chạy trực tiếp công cụ CLI đã cài đặt (Antigravity agy, Claude...)',
                                                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_aiEngineType == 'cli')
                                            const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.accent),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                        // NỘI DUNG FORM CHI TIẾT THEO CHẾ ĐỘ (USER THƯỜNG LUÔN LÀ PROXY AI, CHỈ ADMIN MỚI THẤY CLI)
                        if (!isAdmin || _aiEngineType == 'proxy') ...[
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('AI Model Name', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _modelCtrl,
                                      decoration: InputDecoration(
                                        hintText: 'glm-5.3 / gpt-4o / deepseek-chat',
                                        prefixIcon: const Icon(Icons.smart_toy_outlined, size: 18),
                                        suffixIcon: IconButton(
                                          icon: const Icon(Icons.list_alt_rounded, size: 18, color: AppColors.primaryLight),
                                          tooltip: 'Mở bảng chọn AI Model',
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => ModelPickerDialog(
                                                serverProvider: serverProvider,
                                              ),
                                            ).then((_) {
                                              if (mounted) {
                                                setState(() {
                                                  _modelCtrl.text = serverProvider.cloudAiModel;
                                                });
                                              }
                                            });
                                          },
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
                                    const Text('Proxy Base URL', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _baseUrlCtrl,
                                      obscureText: true,
                                      decoration: const InputDecoration(hintText: 'https://api.mitom.ai/v1'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Proxy API Key', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _apiKeyCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(hintText: 'sk-or-v1-... (OpenRouter / Zhipu / OpenAI API Key)'),
                          ),
                        ] else ...[
                          // GIAO DIỆN CHỌN LOCAL CLI AGENT (DÀNH CHO ADMIN)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Công cụ CLI đã phát hiện trên máy local:',
                                style: TextStyle(fontSize: 11, color: AppColors.textDim),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: _isScanningCli
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent),
                                      )
                                    : const Icon(Icons.refresh_rounded, size: 14, color: AppColors.accent),
                                label: Text(
                                  _isScanningCli ? 'Đang quét...' : 'Quét lại CLI',
                                  style: const TextStyle(fontSize: 11, color: AppColors.accent),
                                ),
                                onPressed: _isScanningCli ? null : _scanCliAgents,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          if (_installedCliAgents.isEmpty && !_isScanningCli)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.bgDark,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.borderDark),
                              ),
                              child: const Text(
                                'Không tìm thấy công cụ CLI nào đã cài đặt (agy, claude, gemini, ollama). Hãy cài đặt và bấm "Quét lại CLI".',
                                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _installedCliAgents.map((cli) {
                                final isSelected = _activeCliAgent == cli.id;
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      _activeCliAgent = cli.id;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.bgDark,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSelected ? AppColors.accent : AppColors.borderDark,
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.terminal_rounded,
                                          size: 16,
                                          color: isSelected ? AppColors.accent : AppColors.textMuted,
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              cli.label,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? Colors.white : AppColors.textDim,
                                              ),
                                            ),
                                            Text(
                                              '${cli.binary} (${cli.path})${cli.version != null ? ' - ${cli.version}' : ''}',
                                              style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'),
                                            ),
                                          ],
                                        ),
                                        if (isSelected) ...[
                                          const SizedBox(width: 8),
                                          const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.accent),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.bgDark,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.flash_on_rounded, size: 16, color: AppColors.accent),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Vũ khí tự động hóa cho $_activeCliAgent:',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Đã trang bị bộ công cụ CLI Bridge `mxh-tool` (~/.agent_mxh_auto/bin/mxh-tool). Khi bạn ra lệnh, CLI Agent sẽ tự động chạy lệnh terminal để mở/đóng cửa sổ trình duyệt Chromium theo từng profile IP nhân vật, truy cập link Facebook/TikTok/Reels và điều khiển máy ảo Android trực tiếp trên máy local mà không cần thông qua Cloud Proxy.',
                                  style: TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.45),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 3: DEVICE & EMULATOR SYSTEM CONFIGURATION
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.devices_other_rounded, size: 18, color: AppColors.accent),
                                SizedBox(width: 8),
                                Text(
                                  '3. Cấu Hình Thiết Bị & Máy Ảo Android',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cardBg,
                                side: const BorderSide(color: AppColors.accent),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 16, color: AppColors.accent),
                              label: const Text('Lưu Cấu Hình Thiết Bị', style: TextStyle(color: AppColors.accent)),
                              onPressed: _saveDeviceSettings,
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Môi Trường Thực Thi Mặc Định Cho Tác Vụ', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final newVal = !_isDeviceExecutionMode;
                                setState(() {
                                  _isDeviceExecutionMode = newVal;
                                });
                                try {
                                  final cfg = await _api.getConfig();
                                  cfg['default_execution_mode'] = newVal ? 'device' : 'browser';
                                  await _api.saveConfig(cfg);
                                  if (!context.mounted) return;
                                  AppToast.info(context, newVal ? 'Đã đổi chế độ: Thiết bị (Device / AVD)' : 'Đã đổi chế độ: Trình duyệt (Browser)');
                                } catch (_) {}
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _isDeviceExecutionMode
                                      ? Colors.purpleAccent.withValues(alpha: 0.1)
                                      : AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _isDeviceExecutionMode
                                        ? Colors.purpleAccent.withValues(alpha: 0.3)
                                        : AppColors.primaryLight.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          _isDeviceExecutionMode ? Icons.phone_android_rounded : Icons.open_in_browser_rounded,
                                          size: 18,
                                          color: _isDeviceExecutionMode ? Colors.purpleAccent : AppColors.primaryLight,
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _isDeviceExecutionMode ? 'Chạy trên Thiết bị (Device / AVD)' : 'Chạy trên Trình duyệt (Browser)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: _isDeviceExecutionMode ? Colors.purpleAccent : AppColors.primaryLight,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _isDeviceExecutionMode
                                                  ? 'Tự động kích hoạt thiết bị Android hoặc máy ảo AVD khi giao việc cho nhân vật'
                                                  : 'Mở cửa sổ trình duyệt web antidetect độc lập theo profile nhân vật',
                                              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                      height: 22,
                                      child: Switch(
                                        value: _isDeviceExecutionMode,
                                        activeThumbColor: Colors.purpleAccent,
                                        activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.3),
                                        inactiveThumbColor: AppColors.primaryLight,
                                        inactiveTrackColor: AppColors.primary.withValues(alpha: 0.3),
                                        onChanged: (val) async {
                                          setState(() {
                                            _isDeviceExecutionMode = val;
                                          });
                                          try {
                                            final cfg = await _api.getConfig();
                                            cfg['default_execution_mode'] = val ? 'device' : 'browser';
                                            await _api.saveConfig(cfg);
                                            if (!context.mounted) return;
                                            AppToast.info(context, val ? 'Đã đổi chế độ: Thiết bị (Device / AVD)' : 'Đã đổi chế độ: Trình duyệt (Browser)');
                                          } catch (_) {}
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (Platform.isWindows) ...[
                              _buildHypervisorToggle(),
                              const SizedBox(height: 16),
                            ],
                            const Text('Số Thiết Bị Tối Đa Được Mở Đồng Thời', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _maxDevicesCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '2',
                                prefixIcon: Icon(Icons.phone_android_rounded, size: 18),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Áp dụng cho cả mở thiết bị thủ công và hàng đợi chạy tác vụ tự động (Task Queue)',
                              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.inputBg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.borderDark),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 16, color: AppColors.accent),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Cơ Chế Bảo Vệ Tài Nguyên Máy Host: Khi số lượng máy ảo/ngoại vi đạt mức tối đa này, hệ thống sẽ tự động tắt thiết bị cũ nhất hoặc xếp hàng đợi luân phiên để chống tràn RAM và nghẽn CPU.',
                                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 4: SECURITY & STORAGE INFO
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield_rounded, size: 18, color: AppColors.accent),
                            SizedBox(width: 8),
                            Text(
                              '4. Bảo Mật & Thông Tin Hệ Thống',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoBox('Chuẩn Mã Hoá', 'AES-256 GCM + HMAC-SHA256 lưu trữ an toàn trong config.json'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox('Trạng Thái Gateway', gateway.isConnected ? 'Kết nối OK (${gateway.pingMs} ms)' : 'Chưa kết nối'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox('Giao Thức Terminal', 'WebSocket xterm-256color PTY Live Stream'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 5: SYSTEM REPAIR & PROFILE MAINTENANCE
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.build_circle_rounded, size: 18, color: AppColors.accentCyan),
                                SizedBox(width: 8),
                                Text(
                                  '5. Bảo Trì & Sửa Chữa Môi Trường (System Repair)',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: _isRepairing
                                  ? null
                                  : () async {
                                      final currentContext = context;
                                      setState(() {
                                        _isRepairing = true;
                                      });
                                      AppToast.info(currentContext, 'Đang quét và sửa chữa môi trường profiles...');
                                      try {
                                        final res = await Socks5ProxyService().repairBrowserProfilesAndEnvironment();
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
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF070B14)),
                                    )
                                  : const Icon(Icons.auto_fix_high_rounded, size: 16),
                              label: Text(
                                _isRepairing ? 'Đang sửa chữa...' : 'Quét & Sửa lỗi Profile / Trình duyệt',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accentCyan,
                                foregroundColor: const Color(0xFF070B14),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.borderDark),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: AppColors.accentCyan),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Chức Năng Sửa Chữa Toàn Diện: Tự động phát hiện và bứng sạch toàn bộ dangling symlink (SingletonLock, SingletonCookie, SingletonSocket) bị kẹt do trình duyệt tắt đột ngột, dọn dẹp tiến trình treo Chrome ngầm và khôi phục cài đặt Tiếng Việt cho toàn bộ profile IP của người dùng.',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
                                ),
                              ),
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
        ],
      ),
    );
  }

  Widget _buildInfoBox(String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  void _showServerBackupImportSheet(ServerModel server, ServerProvider serverProvider) {
    final ips = serverProvider.getIpsForServer(server);
    final personaService = PersonaService();
    final allPersonas = personaService.allPersonas;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: AppColors.borderDark),
      ),
      builder: (bCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.archive_outlined, color: AppColors.primaryLight, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Backup / Import Sân Khấu: ${server.name}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(bCtx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Sân khấu IP: ${server.serverIp} (${ips.length} IPs đi kèm). File backup chứa cấu hình SSH, AI model và toàn bộ Persona profile của dải IP.',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.borderDark),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.download_rounded, color: AppColors.accentCyan, size: 20),
                ),
                title: const Text('Export Backup Sân Khấu Này', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text('Lưu file .json chứa cấu hình Sân khấu và ${ips.length} IPs/Personas', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                onTap: () async {
                  Navigator.pop(bCtx);
                  await _exportServerPackage(server, ips, allPersonas);
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.borderDark),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.upload_file_rounded, color: AppColors.primaryLight, size: 20),
                ),
                title: const Text('Import Cấu Hình & Danh Sách IP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text('Chọn file backup .json để ghi đè hoặc nạp thêm IP vào Sân khấu này', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                onTap: () async {
                  Navigator.pop(bCtx);
                  await _handleImportServerPackage(targetServer: server);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportServerPackage(ServerModel server, List<String> ips, Map<String, PersonaProfile> allPersonas) async {
    try {
      final safeServerName = server.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final fileName = 'server_backup_${safeServerName}_${DateTime.now().millisecondsSinceEpoch}.json';

      // Thu thập thông tin personas tương ứng với danh sách IP của server này
      final serverPersonasMap = <String, dynamic>{};
      for (final ip in ips) {
        if (allPersonas.containsKey(ip)) {
          serverPersonasMap[ip] = allPersonas[ip]!.toJson();
        }
      }

      final payload = {
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'server': server.toJson(),
        'ips': ips,
        'personas': serverPersonasMap,
      };

      final jsonContent = const JsonEncoder.withIndent('  ').convert(payload);

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Chọn nơi lưu file backup Sân khấu',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (savePath == null) {
        return;
      }

      final file = File(savePath);
      await file.writeAsString(jsonContent);

      if (mounted) {
        AppToast.success(context, 'Đã xuất backup Sân khấu thành công ra:\n$savePath');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi xuất backup: $e');
      }
    }
  }

  Future<void> _handleImportServerPackage({ServerModel? targetServer}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Chọn file backup cấu hình Sân khấu (.json)',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return;
      }

      final filePath = result.files.single.path!;
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) AppToast.error(context, 'File không tồn tại');
        return;
      }

      final content = await file.readAsString();
      final decoded = jsonDecode(content);

      if (decoded is! Map<String, dynamic>) {
        if (mounted) AppToast.error(context, 'Định dạng file backup không hợp lệ');
        return;
      }

      if (!mounted) return;
      final serverProvider = Provider.of<ServerProvider>(context, listen: false);
      final personaService = PersonaService();

      // Trường hợp 1: File chứa cấu hình Sân khấu đầy đủ
      ServerModel? importedServer;
      if (decoded['server'] is Map<String, dynamic>) {
        importedServer = ServerModel.fromJson(decoded['server'] as Map<String, dynamic>);
      } else if (targetServer != null) {
        importedServer = targetServer;
      }

      if (importedServer == null && targetServer == null) {
        if (mounted) AppToast.error(context, 'File không có thông tin Sân khấu để import');
        return;
      }

      final serverToSave = (targetServer != null && importedServer != null)
          ? importedServer.copyWith(id: targetServer.id, serverIp: targetServer.serverIp)
          : (importedServer ?? targetServer!);

      // Lưu/Cập nhật Sân khấu
      await serverProvider.addOrUpdateServer(serverToSave);

      // Lưu các persona và danh sách IP đi kèm
      int importedIpsCount = 0;
      if (decoded['personas'] is Map<String, dynamic>) {
        final personasMap = decoded['personas'] as Map<String, dynamic>;
        final personasToSave = <String, PersonaProfile>{};
        personasMap.forEach((ip, val) {
          if (val is Map<String, dynamic>) {
            personasToSave[ip] = PersonaProfile.fromJson(val);
          }
        });
        if (personasToSave.isNotEmpty) {
          await personaService.savePersonas(personasToSave);
          importedIpsCount = personasToSave.length;
        }
      }

      // Nạp danh sách IPs vào cache map của server
      if (decoded['ips'] is List) {
        final rawIps = (decoded['ips'] as List).map((e) => e.toString()).toList();
        if (rawIps.isNotEmpty) {
          serverProvider.serverIpsMap[serverToSave.id] = rawIps;
          importedIpsCount = rawIps.length > importedIpsCount ? rawIps.length : importedIpsCount;
        }
      }

      await serverProvider.loadServers();

      if (mounted) {
        AppToast.success(
          context,
          'Import thành công Sân khấu "${serverToSave.name}" kèm $importedIpsCount IP nhân vật!',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi import Sân khấu: $e');
      }
    }
  }
}
