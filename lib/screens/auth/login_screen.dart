import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/slide_to_verify.dart';
import '../../core/services/multi_account_service.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  String _selectedServer = 'vn.s3';

  // State xác thực kéo trượt hiện đại (Slide to Verify)
  bool _isSlideVerified = false;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  final List<Map<String, String>> _servers = [
    {'value': 'vn.s3', 'label': 'Việt Nam - TP.HCM/S3 (ổn định)'},
    {'value': 'vn.s1', 'label': 'Việt Nam - TP.HCM/S1 (đang sửa chữa)'},
    {'value': 'vn.s2', 'label': 'Việt Nam - TP.HCM/S2 (đang sửa chữa)'},
  ];

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnimation = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_isSlideVerified) {
      AppToast.error(context, 'Vui lòng trượt thanh xác minh để tiếp tục.');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      AppToast.error(context, 'Thiếu thông tin đăng nhập.');
      return;
    }

    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();

    final success = await auth.login(
      email: _emailController.text,
      password: _passwordController.text,
      server: _selectedServer,
      rememberMe: _rememberMe,
    );

    if (mounted) {
      if (success) {
        AppToast.success(context, 'Đăng nhập thành công! Chào mừng bạn trở lại.');
      } else {
        // Đặt lại thanh trượt khi đăng nhập thất bại
        setState(() {
          _isSlideVerified = false;
        });
      }
    }
  }

  Future<void> _handleSelectAccount(AccountProfile account) async {
    final auth = context.read<AuthProvider>();
    final success = await auth.switchAccount(account.id);
    if (mounted && success) {
      AppToast.success(context, 'Đã chuyển sang tài khoản ${account.name ?? account.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.4),
            radius: 1.2,
            colors: [
              Color(0xFF0D1B2A), // Xanh đen thẳm
              AppColors.bgDark,
            ],
          ),
        ),
        child: Center(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg, // Xanh đen Slate 900
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.borderDark, // Viền xanh slate 800
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF020617).withValues(alpha: 0.8),
                        blurRadius: 36,
                        spreadRadius: 4,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08), // Hào quang ánh vàng nhẹ
                        blurRadius: 44,
                        spreadRadius: -2,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Logo & Branding
                        Center(
                          child: Column(
                            children: [
                              AnimatedBuilder(
                                animation: _glowAnimation,
                                builder: (context, child) {
                                  final v = _glowAnimation.value;
                                  return Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(alpha: 0.35 + 0.35 * v),
                                          blurRadius: 8 + 10 * v,
                                          spreadRadius: 1 + 2 * v,
                                        ),
                                        BoxShadow(
                                          color: AppColors.primaryLight.withValues(alpha: 0.15 + 0.25 * v),
                                          blurRadius: 16 + 16 * v,
                                          spreadRadius: 2 + 4 * v,
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset(
                                    'assets/logo.jpg',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: AppColors.primaryDark,
                                      child: const Icon(
                                        Icons.cloud_sync_rounded,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Phần mềm AI quản lý MXH tự động',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textWhite,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Đăng nhập tài khoản hệ thống Type.vn',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Multi-account bar if any accounts saved
                        if (auth.accounts.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Tài khoản đã lưu:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: auth.accounts.map((acc) {
                              final hasAvatar = acc.avatar != null && acc.avatar!.isNotEmpty;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  onTap: () => _handleSelectAccount(acc),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: acc.isActive ? AppColors.accent : AppColors.borderLight,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 10,
                                          backgroundColor: AppColors.primaryDark,
                                          backgroundImage: hasAvatar ? NetworkImage(acc.avatar!) : null,
                                          child: !hasAvatar
                                              ? Text(
                                                  (acc.name?.isNotEmpty == true ? acc.name![0] : acc.id[0]).toUpperCase(),
                                                  style: const TextStyle(fontSize: 10, color: Colors.white),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          acc.name?.isNotEmpty == true ? acc.name! : acc.id,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: acc.isActive ? FontWeight.bold : FontWeight.normal,
                                            color: acc.isActive ? AppColors.accent : AppColors.textBody,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Error Alert Banner
                      if (auth.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.danger,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  auth.errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primaryLight,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Email Field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Email tài khoản forum type.vn',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textBody,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 13, color: AppColors.textWhite),
                            decoration: const InputDecoration(
                              hintText: 'admin@type.vn',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              prefixIcon: Icon(
                                Icons.mail_outline_rounded,
                                size: 16,
                                color: AppColors.textDim,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Vui lòng nhập email';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Password Field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mật khẩu',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textBody,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 13, color: AppColors.textWhite),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 16,
                                color: AppColors.textDim,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 16,
                                  color: AppColors.textDim,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Vui lòng nhập mật khẩu';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Server Selector Dropdown
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Máy chủ xác thực (Server)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textBody,
                            ),
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedServer,
                            isExpanded: true,
                            isDense: true,
                            dropdownColor: const Color(0xFF0F172A),
                            style: const TextStyle(fontSize: 13, color: AppColors.textWhite),
                            icon: const Icon(Icons.arrow_drop_down, color: AppColors.textDim),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              prefixIcon: Icon(
                                Icons.dns_outlined,
                                size: 16,
                                color: AppColors.textDim,
                              ),
                            ),
                            items: _servers.map((s) {
                              return DropdownMenuItem<String>(
                                value: s['value'],
                                child: Text(
                                  s['label']!,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textWhite),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedServer = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Remember Me Checkbox Row
                      Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              side: const BorderSide(color: AppColors.borderLight),
                              onChanged: (val) {
                                setState(() {
                                  _rememberMe = val ?? true;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _rememberMe = !_rememberMe;
                              });
                            },
                            child: const Text(
                              'Ghi nhớ tài khoản',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // ==============================================================
                      // Modern Slide to Verify Captcha (Sang - Xịn - Mịn)
                      // ==============================================================
                      SlideToVerify(
                        isVerified: _isSlideVerified,
                        onVerifiedChanged: (verified) {
                          setState(() {
                            _isSlideVerified = verified;
                          });
                        },
                      ),

                      const SizedBox(height: 14),

                      // Submit Login Button
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isSlideVerified ? AppColors.primary : const Color(0xFF334155),
                            foregroundColor: _isSlideVerified ? const Color(0xFF070B14) : Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed: auth.isLoading ? null : _handleLogin,
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.login_rounded, size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      'Truy cập ứng dụng',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Footer
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 12,
                              color: AppColors.accent.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Phần mềm AI quản lý MXH tự động',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}
