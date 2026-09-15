class ProfileAccount {
  final String? alias;
  final String? email;
  final String? platform;
  final bool? active;
  final String? note;

  ProfileAccount({
    this.alias,
    this.email,
    this.platform,
    this.active,
    this.note,
  });

  factory ProfileAccount.fromJson(Map<String, dynamic> json) {
    return ProfileAccount(
      alias: json['alias'] as String?,
      email: json['email'] as String?,
      platform: json['platform'] as String?,
      active: json['active'] as bool?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (alias != null) 'alias': alias,
      if (email != null) 'email': email,
      if (platform != null) 'platform': platform,
      if (active != null) 'active': active,
      if (note != null) 'note': note,
    };
  }
}

class ProfileItem {
  final String profile;
  bool running;
  int? devtoolsPort;
  String? avatar;
  String? proxy;
  Map<String, dynamic>? vpn;
  List<ProfileAccount> accounts;
  String? note;

  ProfileItem({
    required this.profile,
    this.running = false,
    this.devtoolsPort,
    this.avatar,
    this.proxy,
    this.vpn,
    List<ProfileAccount>? accounts,
    this.note,
  }) : accounts = accounts ?? [];

  factory ProfileItem.fromJson(Map<String, dynamic> json) {
    var rawAcc = json['accounts'];
    List<ProfileAccount> accList = [];
    if (rawAcc is List) {
      accList = rawAcc
          .whereType<Map<String, dynamic>>()
          .map((e) => ProfileAccount.fromJson(e))
          .toList();
    }

    return ProfileItem(
      profile: json['profile']?.toString() ?? '',
      running: json['running'] == true,
      devtoolsPort: json['devtools_port'] as int?,
      avatar: json['avatar'] as String?,
      proxy: json['proxy'] as String?,
      vpn: json['vpn'] is Map<String, dynamic> ? json['vpn'] as Map<String, dynamic> : null,
      accounts: accList,
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile': profile,
      'running': running,
      if (devtoolsPort != null) 'devtools_port': devtoolsPort,
      if (avatar != null) 'avatar': avatar,
      if (proxy != null) 'proxy': proxy,
      if (vpn != null) 'vpn': vpn,
      'accounts': accounts.map((e) => e.toJson()).toList(),
      if (note != null) 'note': note,
    };
  }
}
