class IpProfileModel {
  final String ip;
  final String serverName;
  final String serverHost;
  final int sshPort;
  final String sshUser;
  final bool isMain;
  final bool isOnline;
  final String? domain;
  final String? note;
  final String? country;

  IpProfileModel({
    required this.ip,
    required this.serverName,
    required this.serverHost,
    this.sshPort = 22,
    this.sshUser = 'root',
    this.isMain = false,
    this.isOnline = true,
    this.domain,
    this.note,
    this.country,
  });

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'serverName': serverName,
    'serverHost': serverHost,
    'sshPort': sshPort,
    'sshUser': sshUser,
    'isMain': isMain,
    'isOnline': isOnline,
    'domain': domain,
    'note': note,
    'country': country,
  };

  factory IpProfileModel.fromJson(Map<String, dynamic> json) => IpProfileModel(
    ip: json['ip'] ?? '',
    serverName: json['serverName'] ?? '',
    serverHost: json['serverHost'] ?? '',
    sshPort: json['sshPort'] ?? 22,
    sshUser: json['sshUser'] ?? 'root',
    isMain: json['isMain'] ?? false,
    isOnline: json['isOnline'] ?? true,
    domain: json['domain'],
    note: json['note'],
    country: json['country'],
  );
}
