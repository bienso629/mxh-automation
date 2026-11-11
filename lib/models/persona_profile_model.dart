class PersonaProfile {
  final String ip;
  /// Khóa định danh duy nhất cho nhân vật (entryKey).
  /// Nhân vật gốc: entryKey = ip. Nhân vật phụ cùng IP: entryKey = 'ip##n' (n >= 2).
  /// Luôn dùng entryKey làm khóa lưu trữ, còn ip là địa chỉ mạng thật để mở trình duyệt/proxy.
  final String entryKey;

  /// Khóa lưu trữ/track thực tế: entryKey nếu có, ngược lại dùng ip (tương thích dữ liệu cũ)
  String get effectiveEntryKey =>
      (entryKey.trim().isNotEmpty) ? entryKey.trim() : ip;
  final String name;
  final int age;
  final String gender;
  final String bio;
  final String avatarPrompt;
  final String? avatarUrl;
  final String? externalDeviceAddress;
  final bool useExternalDevice;
  final String? avdName;
  final String deviceType; // 'mobile' | 'tablet'
  final String? agentInfo; // Thông tin Agent / System role của nhân vật này
  final String? email; // Địa chỉ email của nhân vật
  final String? phoneNumber; // Số điện thoại gắn với nhân vật (từ SMSPool hoặc nhập tay)
  final bool autoSyncPhoneToDevice; // Switch tự động gắn số điện thoại vào thiết bị ngoại vi
  final String? smsOrderId; // Mã đơn hàng SMSPool (nếu có thuê qua SMSPool)
  final String? deviceResolution; // Độ phân giải màn hình SQLite
  final Map<String, dynamic>? automationMacros; // Bộ nhớ macro tự động hóa riêng biệt của nhân vật
  final String? browserProfileId; // ID profile của trình duyệt hệ thống gắn với nhân vật ('Default', 'Profile 1'...)
  final String? browserProfileName; // Tên hiển thị của profile trình duyệt đã gắn (cache tên để hiển thị nhanh)

  PersonaProfile({
    required this.ip,
    String? entryKey,
    required this.name,
    required this.age,
    required this.gender,
    required this.bio,
    required this.avatarPrompt,
    this.avatarUrl,
    this.externalDeviceAddress,
    this.useExternalDevice = false,
    this.avdName,
    this.deviceType = 'mobile',
    this.agentInfo,
    this.email,
    this.phoneNumber,
    this.autoSyncPhoneToDevice = false,
    this.smsOrderId,
    this.deviceResolution,
    this.automationMacros,
    this.browserProfileId,
    this.browserProfileName,
  }) : entryKey = entryKey ?? ip;

  PersonaProfile copyWith({
    String? ip,
    String? entryKey,
    String? name,
    int? age,
    String? gender,
    String? bio,
    String? avatarPrompt,
    String? avatarUrl,
    String? externalDeviceAddress,
    bool? useExternalDevice,
    String? avdName,
    String? deviceType,
    String? agentInfo,
    String? email,
    String? phoneNumber,
    bool? autoSyncPhoneToDevice,
    String? smsOrderId,
    String? deviceResolution,
    Map<String, dynamic>? automationMacros,
    String? browserProfileId,
    String? browserProfileName,
    bool clearSmsOrderId = false,
    bool clearAvdName = false,
    bool clearPhoneNumber = false,
    bool clearEmail = false,
    bool clearAvatarUrl = false,
    bool clearBrowserProfile = false,
  }) {
    return PersonaProfile(
      ip: ip ?? this.ip,
      entryKey: entryKey ?? this.entryKey,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      avatarPrompt: avatarPrompt ?? this.avatarPrompt,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      externalDeviceAddress: externalDeviceAddress ?? this.externalDeviceAddress,
      useExternalDevice: useExternalDevice ?? this.useExternalDevice,
      avdName: clearAvdName ? null : (avdName ?? this.avdName),
      deviceType: deviceType ?? this.deviceType,
      agentInfo: agentInfo ?? this.agentInfo,
      email: clearEmail ? null : (email ?? this.email),
      phoneNumber: clearPhoneNumber ? null : (phoneNumber ?? this.phoneNumber),
      autoSyncPhoneToDevice: autoSyncPhoneToDevice ?? this.autoSyncPhoneToDevice,
      smsOrderId: clearSmsOrderId ? null : (smsOrderId ?? this.smsOrderId),
      deviceResolution: deviceResolution ?? this.deviceResolution,
      automationMacros: automationMacros ?? this.automationMacros,
      browserProfileId: clearBrowserProfile ? null : (browserProfileId ?? this.browserProfileId),
      browserProfileName: clearBrowserProfile ? null : (browserProfileName ?? this.browserProfileName),
    );
  }

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'entry_key': entryKey,
    'name': name,
    'age': age,
    'gender': gender,
    'bio': bio,
    'avatar_prompt': avatarPrompt,
    'avatar_url': avatarUrl,
    'external_device_address': externalDeviceAddress,
    'use_external_device': useExternalDevice ? 1 : 0,
    'avd_name': avdName,
    'device_type': deviceType,
    'agent_info': agentInfo,
    'email': email,
    'phone_number': phoneNumber,
    'auto_sync_phone_to_device': autoSyncPhoneToDevice ? 1 : 0,
    'sms_order_id': smsOrderId,
    'device_resolution': deviceResolution,
    'automation_macros': automationMacros,
    'browser_profile_id': browserProfileId,
    'browser_profile_name': browserProfileName,
  };

  factory PersonaProfile.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? parsedMacros;
    if (json['automation_macros'] is Map) {
      parsedMacros = Map<String, dynamic>.from(json['automation_macros'] as Map);
    }

    return PersonaProfile(
      ip: json['ip']?.toString() ?? '',
      entryKey: json['entry_key']?.toString(),
      name: json['name']?.toString() ?? '',
      age: (json['age'] is num) ? (json['age'] as num).toInt() : (int.tryParse(json['age']?.toString() ?? '') ?? 25),
      gender: json['gender']?.toString() ?? 'Nam',
      bio: json['bio']?.toString() ?? '',
      avatarPrompt: json['avatar_prompt']?.toString() ?? json['avatarPrompt']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString() ?? json['avatarUrl']?.toString(),
      externalDeviceAddress: json['external_device_address']?.toString(),
      useExternalDevice: json['use_external_device'] == 1 || json['use_external_device'] == true,
      avdName: json['avd_name']?.toString(),
      deviceType: json['device_type']?.toString() ?? 'mobile',
      agentInfo: json['agent_info']?.toString(),
      email: json['email']?.toString(),
      phoneNumber: json['phone_number']?.toString(),
      autoSyncPhoneToDevice: json['auto_sync_phone_to_device'] == 1 || json['auto_sync_phone_to_device'] == true,
      smsOrderId: json['sms_order_id']?.toString(),
      deviceResolution: json['device_resolution']?.toString(),
      automationMacros: parsedMacros,
      browserProfileId: json['browser_profile_id']?.toString(),
      browserProfileName: json['browser_profile_name']?.toString(),
    );
  }
}
