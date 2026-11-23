import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agent_mxh_auto/core/services/crypto_helper.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';
import 'package:agent_mxh_auto/core/services/forum_auth_service.dart';
import 'package:agent_mxh_auto/core/services/local_config_service.dart';
import 'package:agent_mxh_auto/core/services/multi_account_service.dart';
import 'package:agent_mxh_auto/core/services/storage_service.dart';
import 'package:agent_mxh_auto/providers/auth_provider.dart';

void main() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final testEmail = 'actor_member_$ts@gmail.com';
  final testUsername = 'actor_member_$ts';
  final testUid = '${900000 + (ts % 99999)}';
  final testUserKey = StorageService.sanitizeUserKey(testEmail);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clearAuth();
  });

  tearDownAll(() async {
    await DatabaseService().closeForLogout();
    await LocalConfigService().clearForLogout();
    final dataDir = DatabaseService.resolveDefaultDataDir();
    for (final fileName in [
      'chat_history_$testUserKey.db',
      'config_$testUserKey.json',
      'personas_$testUserKey.json',
    ]) {
      try {
        final f = File(p.join(dataDir, fileName));
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  });

  Future<void> seedLoggedInActorSession() async {
    final user = <String, dynamic>{
      'id': testUid,
      'name': testUsername,
      'email': testEmail,
      'server': 'vn.s3',
      'groups': ['nhóm-diễn-viên-mxh', 'registered-users'],
    };
    final jwt = CryptoHelper.generateJWTToken(user);
    await MultiAccountService().saveAccount(
      testEmail,
      {'user': user, 'profile': user},
      uid: testUid,
      userKey: testUserKey,
    );
    await StorageService().setAuthToken(jwt);
    await StorageService().setUserEmail(testEmail);
    await StorageService().setUserName(testUsername);
    await StorageService().setUserUid(testUid);
    await StorageService().setAuthServer('vn.s3');
    await StorageService().setUserKey(testUserKey);
    await StorageService().setLoggedIn(true);
  }

  group('Tự động đăng xuất khi tài khoản bị gỡ khỏi nhóm "nhóm-diễn-viên-mxh"', () {
    test('Phân tích phản hồi /forum/groups chính xác cả khi còn nhóm, khi bị kích, và khi danh sách bị cắt trang', () {
      final resWithMember = {
        'success': true,
        'data': {
          'groups': [
            {
              'slug': 'nhóm-diễn-viên-mxh',
              'name': 'Nhóm diễn viên MXH',
              'memberCount': 2,
              'members': [
                {'uid': 4, 'username': 'buctuong2000', 'userslug': 'buctuong2000'},
                {'uid': int.parse(testUid), 'username': testUsername, 'userslug': testUsername},
              ],
            },
          ],
        },
      };

      final inGroup = ForumAuthService.extractLiveGroupResultFromForumGroups(
        groupsRes: resWithMember,
        uid: testUid,
        username: testUsername,
        email: testEmail,
      );
      expect(inGroup.verified, isTrue);
      expect(inGroup.groups, contains('nhóm-diễn-viên-mxh'));

      final resKicked = {
        'success': true,
        'data': {
          'groups': [
            {
              'slug': 'nhóm-diễn-viên-mxh',
              'name': 'Nhóm diễn viên MXH',
              'memberCount': 1,
              'members': [
                {'uid': 4, 'username': 'buctuong2000', 'userslug': 'buctuong2000'},
              ],
            },
          ],
        },
      };

      final kicked = ForumAuthService.extractLiveGroupResultFromForumGroups(
        groupsRes: resKicked,
        uid: testUid,
        username: testUsername,
        email: testEmail,
      );
      expect(kicked.verified, isTrue);
      expect(kicked.groups, isEmpty);

      // Nếu danh sách thành viên bị phân trang cắt bớt (members.length < memberCount) và chưa thấy user -> chưa kết luận vội
      final resTruncated = {
        'success': true,
        'data': {
          'groups': [
            {
              'slug': 'nhóm-diễn-viên-mxh',
              'name': 'Nhóm diễn viên MXH',
              'memberCount': 50,
              'members': [
                {'uid': 4, 'username': 'buctuong2000', 'userslug': 'buctuong2000'},
              ],
            },
          ],
        },
      };
      final truncated = ForumAuthService.extractLiveGroupResultFromForumGroups(
        groupsRes: resTruncated,
        uid: testUid,
        username: testUsername,
        email: testEmail,
      );
      expect(truncated.verified, isFalse);
    });

    test('Đang đăng nhập và bị kích khỏi nhóm -> bộ giám sát định kỳ lập tức đăng xuất và xóa nhóm cũ trong cache', () async {
      await seedLoggedInActorSession();

      bool isStillInGroup = true;
      final auth = AuthProvider(autoCheck: false, enablePeriodicCheck: true)
        ..groupCheckInterval = const Duration(milliseconds: 60)
        ..liveGroupCheckerOverride = ({uid, username, email, required server, sessionCookie}) async {
          return LiveGroupCheckResult(
            verified: true,
            groups: isStillInGroup ? ['nhóm-diễn-viên-mxh'] : ['registered-users'],
            source: 'test_mock',
          );
        };

      await auth.checkAuthStatus();
      expect(auth.isAuthenticated, isTrue);
      expect(auth.userEmail, testEmail);

      // Giả lập admin kích tài khoản khỏi nhóm "nhóm-diễn-viên-mxh" trên type.vn
      isStillInGroup = false;
      await Future.delayed(const Duration(milliseconds: 180));

      expect(auth.isAuthenticated, isFalse);
      expect(await StorageService().isLoggedIn(), isFalse);
      expect(auth.errorMessage, contains('nhóm-diễn-viên-mxh'));
      expect(auth.errorMessage, contains('tự động đăng xuất'));

      // Tài khoản đã lưu trong MultiAccountService cũng phải bị xóa nhóm cũ và không thể chuyển nhanh lại
      final switchOk = await auth.switchAccount(testEmail);
      expect(switchOk, isFalse);
      expect(auth.isAuthenticated, isFalse);
      auth.dispose();
    });

    test('Bị kích khỏi nhóm trong lúc tắt app -> khi mở lại (checkAuthStatus) lập tức đăng xuất, không tin JWT cũ', () async {
      await seedLoggedInActorSession();

      final auth = AuthProvider(autoCheck: false, enablePeriodicCheck: false)
        ..liveGroupCheckerOverride = ({uid, username, email, required server, sessionCookie}) async {
          return const LiveGroupCheckResult(
            verified: true,
            groups: ['registered-users'],
            source: 'test_mock',
          );
        };

      await auth.checkAuthStatus();

      expect(auth.isAuthenticated, isFalse);
      expect(await StorageService().isLoggedIn(), isFalse);
      expect(auth.errorMessage, contains('nhóm-diễn-viên-mxh'));
      auth.dispose();
    });

    test('Lỗi mạng tạm thời (verified: false) KHÔNG được đăng xuất nhầm tài khoản hợp lệ', () async {
      await seedLoggedInActorSession();

      final auth = AuthProvider(autoCheck: false, enablePeriodicCheck: false)
        ..liveGroupCheckerOverride = ({uid, username, email, required server, sessionCookie}) async {
          return const LiveGroupCheckResult(verified: false);
        };

      await auth.checkAuthStatus();
      expect(auth.isAuthenticated, isTrue);

      final stillAuth = await auth.verifyLiveGroupMembership();
      expect(stillAuth, isTrue);
      expect(auth.isAuthenticated, isTrue);
      auth.dispose();
    });
  });
}
