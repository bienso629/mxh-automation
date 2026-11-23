import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/services/database_service.dart';
import 'core/services/local_config_service.dart';
import 'core/services/persona_service.dart';
import 'core/services/socks5_proxy_service.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/gateway_provider.dart';
import 'providers/metrics_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/server_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Storage Service
  try {
    await StorageService().init();
  } catch (_) {}

  // Initialize Database and Local Config only for currently authenticated user
  try {
    final storage = StorageService();
    if (await storage.isLoggedIn()) {
      final userKey = await storage.getUserKey();
      if (userKey.isNotEmpty) {
        await DatabaseService().switchUser(userKey);
        await LocalConfigService().switchUser(userKey);
        PersonaService().switchUser(userKey);
      }
    }
  } catch (_) {}

  // Setup System UI Overlay styles
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.sidebarBg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const TaduCloudAiAgentApp());
}

class TaduCloudAiAgentApp extends StatelessWidget {
  const TaduCloudAiAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GatewayProvider()),
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => MetricsProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
        ChangeNotifierProvider.value(value: Socks5ProxyService()),
      ],
      child: MaterialApp(
        title: 'Diễn viên MXH',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  String? _lastTrackedUserKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AuthProvider>().verifyLiveGroupMembership();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isCheckingAuth) {
      return const Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final currentKey = auth.isAuthenticated ? auth.activeUserKey : '';
    if (_lastTrackedUserKey != null && _lastTrackedUserKey != currentKey) {
      final serverProv = context.read<ServerProvider>();
      final chatProv = context.read<ChatProvider>();
      final schedProv = context.read<ScheduleProvider>();
      final wasAuthenticated = _lastTrackedUserKey!.isNotEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        serverProv.resetForUserSwitch();
        chatProv.resetForUserSwitch();
        schedProv.resetForUserSwitch();
        if (wasAuthenticated && currentKey.isEmpty && mounted) {
          // Đóng mọi hộp thoại đang mở để người dùng thấy ngay màn hình đăng nhập và thông báo bị đăng xuất
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        if (currentKey.isNotEmpty) {
          serverProv.loadServers();
          chatProv.initChat();
          schedProv.loadTasks();
        }
      });
    }
    _lastTrackedUserKey = currentKey;

    if (auth.isAuthenticated) {
      return MainNavigationScreen(
        key: ValueKey('nav_${auth.activeUserKey}'),
      );
    }

    return const LoginScreen();
  }
}
