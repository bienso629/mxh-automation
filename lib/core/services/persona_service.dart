import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../models/persona_profile_model.dart';
import 'database_service.dart';
import 'local_config_service.dart';

class PersonaService {
  static final PersonaService _instance = PersonaService._internal();
  factory PersonaService() => _instance;
  PersonaService._internal();

  final LocalConfigService _configService = LocalConfigService();
  final DatabaseService _dbService = DatabaseService();
  final Map<String, PersonaProfile> _cachedPersonas = {};
  final Set<String> _activeScopeIps = {};
  String? _currentUserKey;
  bool _isLoaded = false;

  Set<String> get activeScopeIps => Set.unmodifiable(_activeScopeIps);

  void setActiveScopeIps(Iterable<String> ips) {
    _activeScopeIps.clear();
    _activeScopeIps.addAll(ips);
  }

  void clearActiveScope() {
    _activeScopeIps.clear();
  }

  void switchUser(String? userKey) {
    if (_currentUserKey != userKey) {
      _currentUserKey = userKey;
      _cachedPersonas.clear();
      _activeScopeIps.clear();
      _isLoaded = false;
    }
  }

  void clearCache() {
    _cachedPersonas.clear();
    _activeScopeIps.clear();
    _isLoaded = false;
  }

  List<String> get _candidateStoragePaths {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final primaryDir = p.join(home, '.agent_mxh_auto');
    if (!Directory(primaryDir).existsSync()) {
      try {
        Directory(primaryDir).createSync(recursive: true);
      } catch (_) {}
    }
    final key = _currentUserKey ?? '';
    final list = <String>[];
    if (key.isNotEmpty) {
      list.add(p.join(primaryDir, 'personas_$key.json'));
    }
    list.add(p.join(primaryDir, 'personas.json'));
    list.add(p.join(home, '.tadu_ai_agent', 'personas.json'));
    list.add(p.join(Directory.current.path, 'personas.json'));
    return list;
  }

  String get _storageFilePath => _candidateStoragePaths.first;

  /// Nạp danh sách nhân vật từ database local của app (fallback json nếu chưa có trong DB)
  Future<Map<String, PersonaProfile>> loadSavedPersonas({bool forceReload = false}) async {
    if (!forceReload && _isLoaded && _cachedPersonas.isNotEmpty) {
      return Map.unmodifiable(_cachedPersonas);
    }

    if (forceReload) {
      _cachedPersonas.clear();
    }

    try {
      // 1. Thử tải từ database SQLite local
      final dbPersonas = await _dbService.getPersonaProfiles();
      if (dbPersonas.isNotEmpty) {
        _cachedPersonas.addAll(dbPersonas);
      }
    } catch (_) {}

    // 2. Đồng bộ thêm từ các file JSON dự phòng nếu database còn thiếu profile nào
    for (final path in _candidateStoragePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            final decoded = jsonDecode(content);
            if (decoded is Map<String, dynamic>) {
              final toInsertToDb = <PersonaProfile>[];
              decoded.forEach((ip, val) {
                if (val is Map<String, dynamic>) {
                  final p = PersonaProfile.fromJson(val);
                  if (!_cachedPersonas.containsKey(ip)) {
                    _cachedPersonas[ip] = p;
                    toInsertToDb.add(p);
                  }
                }
              });
              if (toInsertToDb.isNotEmpty) {
                await _dbService.batchUpsertPersonaProfiles(toInsertToDb);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Nếu DB có profiles mà file JSON chính chưa có thì đồng bộ ngược lại JSON
    if (_cachedPersonas.isNotEmpty) {
      try {
        final mainFile = File(_storageFilePath);
        if (!await mainFile.exists()) {
          final mapToSave = <String, dynamic>{};
          _cachedPersonas.forEach((ip, profile) {
            mapToSave[ip] = profile.toJson();
          });
          await mainFile.writeAsString(const JsonEncoder.withIndent('  ').convert(mapToSave));
        }
      } catch (_) {}
    }

    _isLoaded = true;
    return Map.unmodifiable(_cachedPersonas);
  }

  /// Lưu hoặc cập nhật một nhân vật đơn lẻ vào cả database local và file cache
  Future<bool> updatePersona(PersonaProfile persona) async {
    _cachedPersonas[persona.ip] = persona;
    bool dbOk = false;
    try {
      dbOk = await _dbService.upsertPersonaProfile(persona);
    } catch (_) {}

    try {
      final file = File(_storageFilePath);
      final mapToSave = <String, dynamic>{};
      _cachedPersonas.forEach((ip, profile) {
        mapToSave[ip] = profile.toJson();
      });
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(mapToSave));
    } catch (_) {}

    return dbOk;
  }

  /// Lưu danh sách nhân vật vào cả database SQLite local và file JSON
  Future<void> savePersonas(Map<String, PersonaProfile> personas) async {
    _cachedPersonas.addAll(personas);
    try {
      await _dbService.batchUpsertPersonaProfiles(personas.values.toList());
    } catch (_) {}

    try {
      final file = File(_storageFilePath);
      final mapToSave = <String, dynamic>{};
      _cachedPersonas.forEach((ip, profile) {
        mapToSave[ip] = profile.toJson();
      });
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(mapToSave));
    } catch (_) {}
  }

  PersonaProfile? getPersona(String ip) {
    return _cachedPersonas[ip];
  }

  Map<String, PersonaProfile> get allPersonas => Map.unmodifiable(_cachedPersonas);

  /// Lấy macro tự động hóa của nhân vật theo IP và actionKey (ví dụ: 'facebook_like', 'tiktok_like')
  Map<String, dynamic>? getMacroForPersona(String ip, String actionKey) {
    final persona = _cachedPersonas[ip];
    if (persona?.automationMacros != null && persona!.automationMacros!.containsKey(actionKey)) {
      final val = persona.automationMacros![actionKey];
      if (val is Map) return Map<String, dynamic>.from(val);
    }
    return null;
  }

  /// Cập nhật macro tự động hóa và độ phân giải màn hình cho riêng nhân vật theo IP
  Future<bool> saveMacroForPersona({
    required String ip,
    required String actionKey,
    required Map<String, dynamic> macroData,
    String? resolution,
  }) async {
    final persona = _cachedPersonas[ip];
    if (persona == null) return false;

    final updatedMacros = Map<String, dynamic>.from(persona.automationMacros ?? {});
    updatedMacros[actionKey] = {
      ...macroData,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final updatedProfile = persona.copyWith(
      automationMacros: updatedMacros,
      deviceResolution: (resolution != null && resolution.isNotEmpty) ? resolution : persona.deviceResolution,
    );

    return await updatePersona(updatedProfile);
  }

  Future<Map<String, PersonaProfile>> generatePersonas({
    required List<String> ips,
    String? model,
  }) async {
    if (ips.isEmpty) return {};

    final cfg = await _configService.loadConfig();
    final prompt = '''Bạn là một chuyên gia sáng tạo danh tính số (Digital Persona Creator) cho hệ thống mạng xã hội tự động.
Dưới đây là danh sách các địa chỉ IP:
${ips.map((ip) => "- $ip").join("\n")}

Nhiệm vụ: Hãy tạo cho MỖI địa chỉ IP một nhân vật (profile persona) độc nhất, tự nhiên, đậm chất đời thực (Việt Nam hoặc quốc tế đa dạng).
Mỗi nhân vật phải gồm:
- ip: Địa chỉ IP tương ứng chính xác
- name: Họ và tên nhân vật (ví dụ: Nguyễn Hoàng Nam, Trần Thu Hà, Lê Minh Triết...)
- age: Tuổi (từ 18 đến 45)
- gender: Giới tính ("Nam" hoặc "Nữ")
- bio: Mô tả cá tính, tính cách, sở thích và phong cách sống (khoảng 1 - 2 câu súc tích)
- email: Địa chỉ email tự nhiên phù hợp với tên nhân vật (ví dụ: nam.nguyenhoang98@gmail.com, triet.leminh89@outlook.com...)
- agent_info: Vai trò, nhiệm vụ chính của nhân vật này trong hệ thống MXH (ví dụ: "Seeding bài viết ẩm thực, bình luận chia sẻ kinh nghiệm quán ăn, tạo tương tác tự nhiên với khách hàng", hoặc "Review đồ công nghệ, trả lời giải đáp thắc mắc người xem livestream", hoặc "Chăm sóc khách hàng, tương tác thân thiện trong group cộng đồng"...)
- avatar_prompt: Một prompt chi tiết bằng tiếng Anh chuyên dùng cho AI vẽ ảnh (Midjourney/FLUX/Stable Diffusion) để tạo chân dung cận cảnh avatar cho nhân vật này. ĐẶC BIỆT: Yêu cầu ảnh chụp cận cảnh khuôn mặt (close-up headshot portrait focusing strictly on facial features, eyes, and natural expression), phản ánh đúng giới tính, độ tuổi, cá tính từ bio và nghề nghiệp/vai trò từ agent_info, không có watermark, không có logo hay chữ. Ví dụ: "Close-up headshot portrait photo of a 24-year-old Vietnamese female food reviewer, friendly warm smile, natural skin texture, beautiful expressive eyes, blurred coffee shop background, soft morning sunlight, cinematic lighting, 8k resolution, authentic photography, no watermark, no text".

BẮT BUỘC TRẢ VỀ ĐỊNH DẠNG JSON DUY NHẤT (không bọc trong markdown hoặc chỉ bọc trong ```json ... ```):
[
  {
    "ip": "...",
    "name": "...",
    "age": 25,
    "gender": "Nam",
    "bio": "...",
    "email": "...",
    "agent_info": "...",
    "avatar_prompt": "..."
  }
]''';

    // Gọi Cloud API qua Proxy Base URL và API Key
    var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://api.mitom.ai/v1';
    if (!LocalConfigService.isValidMitomProxyUrl(baseUrl)) {
      throw Exception('Cấu hình Proxy Base URL không hợp lệ. Chỉ chấp nhận domain thuộc *.mitom.ai');
    }
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final apiKey = cfg['proxy_api_key']?.toString() ?? '';
    final defaultModel = cfg['ai_model']?.toString() ?? 'glm-5.3';
    final targetModel = (model != null && model.isNotEmpty) ? model : defaultModel;

    final uri = Uri.parse('$baseUrl/chat/completions');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': targetModel,
        'messages': [
          {
            'role': 'system',
            'content': 'Bạn là trợ lý AI chuyên tạo dữ liệu nhân vật chuẩn JSON. Chỉ trả về mảng JSON hợp lệ.',
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'temperature': 0.7,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Lỗi gọi AI API (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Phản hồi AI trống');
    }

    final rawReply = choices[0]['message']?['content']?.toString() ?? '';

    final parsedProfiles = _parseAiJson(rawReply, ips);
    await savePersonas(parsedProfiles);
    return parsedProfiles;
  }

  Map<String, PersonaProfile> _parseAiJson(String rawText, List<String> ips) {
    String clean = rawText.trim();
    if (clean.startsWith('```json')) {
      clean = clean.substring(7);
    } else if (clean.startsWith('```')) {
      clean = clean.substring(3);
    }
    if (clean.endsWith('```')) {
      clean = clean.substring(0, clean.length - 3);
    }
    clean = clean.trim();

    // Find JSON array start and end
    final startIdx = clean.indexOf('[');
    final endIdx = clean.lastIndexOf(']');
    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
      clean = clean.substring(startIdx, endIdx + 1);
    }

    final Map<String, PersonaProfile> result = {};
    try {
      final decoded = jsonDecode(clean);
      if (decoded is List) {
        for (int i = 0; i < decoded.length; i++) {
          final item = decoded[i];
          if (item is Map<String, dynamic>) {
            var ip = item['ip']?.toString().trim() ?? '';
            if (ip.isEmpty || !ips.contains(ip)) {
              if (i < ips.length) {
                ip = ips[i];
              }
            }
            if (ip.isNotEmpty) {
              result[ip] = PersonaProfile(
                ip: ip,
                name: item['name']?.toString() ?? 'Nhân vật AI',
                age: (item['age'] is num) ? (item['age'] as num).toInt() : 25,
                gender: item['gender']?.toString() ?? 'Nam',
                bio: item['bio']?.toString() ?? 'Người dùng mạng xã hội',
                agentInfo: item['agent_info']?.toString() ?? item['agentInfo']?.toString() ?? 'Tương tác mạng xã hội tự nhiên',
                email: item['email']?.toString(),
                avatarPrompt: item['avatar_prompt']?.toString() ?? item['avatarPrompt']?.toString() ?? 'Portrait photo, photorealistic 8k',
              );
            }
          }
        }
      }
    } catch (e) {
      throw Exception('Lỗi phân tích JSON từ AI: $e. Phản hồi thô: $rawText');
    }

    // Fallback: Nếu một số IP chưa có trong kết quả, gán IP tương ứng
    for (int i = 0; i < ips.length; i++) {
      final ip = ips[i];
      if (!result.containsKey(ip)) {
        result[ip] = PersonaProfile(
          ip: ip,
          name: 'Nhân vật $ip',
          age: 25,
          gender: 'Nam',
          bio: 'Thành viên mạng xã hội năng động',
          agentInfo: 'Tương tác mạng xã hội tự nhiên, seeding nội dung đời thực',
          avatarPrompt: 'Portrait of a young creative professional, cinematic lighting, 8k',
        );
      }
    }

    return result;
  }

  /// Sinh hình ảnh Avatar AI dựa trên avatarPrompt của Nhân vật
  Future<String> generateAvatarImage(PersonaProfile persona) async {
    final cfg = await _configService.loadConfig();
    var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://api.mitom.ai/v1';
    if (!LocalConfigService.isValidMitomProxyUrl(baseUrl)) {
      throw Exception('Cấu hình Proxy Base URL không hợp lệ. Chỉ chấp nhận domain thuộc *.mitom.ai');
    }
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final apiKey = cfg['proxy_api_key']?.toString() ?? '';

    // Thư mục lưu trữ avatar cục bộ
    final home = Platform.environment['HOME'] ?? '';
    final avatarDir = Directory(p.join(home, '.agent_mxh_auto', 'avatars'));
    if (!avatarDir.existsSync()) {
      avatarDir.createSync(recursive: true);
    }

    final sanitizedIp = persona.ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final localImagePath = p.join(avatarDir.path, 'avatar_${sanitizedIp}_$timestamp.png');

    // Xóa các avatar cũ của IP này nếu có để không bị đầy ổ đĩa
    try {
      if (avatarDir.existsSync()) {
        final existingFiles = avatarDir.listSync();
        for (final file in existingFiles) {
          if (file is File && p.basename(file.path).startsWith('avatar_$sanitizedIp')) {
            try {
              file.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // Xây dựng prompt avatar AI cận cảnh tập trung vào khuôn mặt (Close-up face portrait)
    // Tận dụng chính xác các thông tin: Tên, Tuổi, Giới tính, Cá tính (Bio), Vai trò (Agent Info) và avatarPrompt
    final genderEn = persona.gender.toLowerCase() == 'nữ' ? 'Vietnamese woman' : 'Vietnamese man';
    final ageText = '${persona.age} years old';
    final nameContext = persona.name.isNotEmpty ? 'named ${persona.name}' : '';
    final bioContext = persona.bio.trim().isNotEmpty ? ', personality: ${persona.bio.trim()}' : '';
    final roleContext = (persona.agentInfo != null && persona.agentInfo!.trim().isNotEmpty)
        ? ', profession/role: ${persona.agentInfo!.trim()}'
        : '';

    String promptCore;
    if (persona.avatarPrompt.trim().isNotEmpty) {
      promptCore = persona.avatarPrompt.trim();
    } else {
      promptCore = 'A realistic detailed close-up face portrait of a $genderEn, $ageText$nameContext$bioContext$roleContext';
    }

    // Luôn định hướng trọng tâm vào khuôn mặt (headshot, facial features, eyes, expression)
    final effectivePrompt = '$promptCore, headshot portrait, looking directly at camera, detailed facial features, realistic human skin texture, natural expression, focused on face, soft natural cinematic lighting, 8k resolution, photorealistic, sharp focus, masterpiece, authentic photo, NO watermark, NO logo, NO text, NO signature, NO cartoon, NO anime, NO 3D render, NO illustration';

    String lastError = '';

    // 1. ƯU TIÊN TUYỆT ĐỐI MODEL AI gemini-nano-banana-2.1 (Chat Multimodal Output 2K)
    // Sinh ảnh chân dung 2K siêu nét, chuẩn tỷ lệ 1:1, không watermark, không logo
    if (apiKey.isNotEmpty) {
      try {
        final chatUri = Uri.parse('$baseUrl/chat/completions');
        final promptForGemini = 'A 1:1 square headshot avatar portrait photo of a $genderEn named ${persona.name}, ${persona.age} years old$bioContext$roleContext. Showing full face from forehead to chin, looking directly into camera with natural facial expression, realistic detailed skin pores and eyes, studio lighting, ultra-sharp 2K 2048x2048 resolution masterpiece, clean background, no watermark, no text, no logo.';
        
        final res = await http.post(
          chatUri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': 'gemini-nano-banana-2.1',
            'messages': [
              {'role': 'user', 'content': promptForGemini},
            ],
            'modalities': ['text', 'image'],
          }),
        ).timeout(const Duration(seconds: 120));

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final choices = data['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final content = choices[0]['message']?['content']?.toString() ?? '';
            
            // Tìm chuỗi base64 qua data:image
            const marker = 'data:image/';
            final markerIdx = content.indexOf(marker);
            if (markerIdx != -1) {
              final base64Marker = ';base64,';
              final b64Start = content.indexOf(base64Marker, markerIdx);
              if (b64Start != -1) {
                final contentStart = b64Start + base64Marker.length;
                // Tìm ký tự kết thúc như ')', '"', '\n', hoặc hết chuỗi
                var contentEnd = content.length;
                for (var i = contentStart; i < content.length; i++) {
                  final code = content.codeUnitAt(i);
                  if (code == 41 || code == 34 || code == 39 || code == 10 || code == 13 || code == 32) { // ), ", ', \n, \r, space
                    contentEnd = i;
                    break;
                  }
                }
                var rawB64 = content.substring(contentStart, contentEnd).replaceAll(RegExp(r'\s+'), '');
                while (rawB64.length % 4 != 0) {
                  rawB64 += '=';
                }
                final bytes = base64Decode(rawB64);
                if (bytes.length > 5000) {
                  await File(localImagePath).writeAsBytes(bytes);
                  final updated = persona.copyWith(avatarUrl: localImagePath);
                  await updatePersona(updated);
                  return localImagePath;
                }
              }
            }
          } else {
            lastError = 'Server trả về choices rỗng';
          }
        } else {
          lastError = 'HTTP ${res.statusCode}: ${res.body}';
        }
      } catch (e) {
        lastError = e.toString();
      }

      // Thử tiếp các model Image qua images/generations với chuẩn 2K/1024
      final imageModels = [
        'qwen-image-3.0',
        'wan2.7-image',
        'doubao-seedream-5-0-260128',
        'dall-e-3',
      ];

      for (final modelName in imageModels) {
        try {
          final imageUri = Uri.parse('$baseUrl/images/generations');
          final res = await http.post(
            imageUri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': modelName,
              'prompt': effectivePrompt,
              'n': 1,
              'size': '2048x2048',
              'response_format': 'b64_json',
            }),
          ).timeout(const Duration(seconds: 60));

          if (res.statusCode == 200) {
            final data = jsonDecode(utf8.decode(res.bodyBytes));
            final dataList = data['data'] as List<dynamic>?;
            if (dataList != null && dataList.isNotEmpty) {
              final first = dataList[0];
              if (first['b64_json'] != null) {
                final bytes = base64Decode(first['b64_json'].toString());
                if (bytes.length > 3000) {
                  await File(localImagePath).writeAsBytes(bytes);
                  final updated = persona.copyWith(avatarUrl: localImagePath);
                  await updatePersona(updated);
                  return localImagePath;
                }
              } else if (first['url'] != null) {
                final imgUrl = first['url'].toString();
                final dlRes = await http.get(Uri.parse(imgUrl)).timeout(const Duration(seconds: 30));
                if (dlRes.statusCode == 200 && dlRes.bodyBytes.length > 3000) {
                  await File(localImagePath).writeAsBytes(dlRes.bodyBytes);
                  final updated = persona.copyWith(avatarUrl: localImagePath);
                  await updatePersona(updated);
                  return localImagePath;
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    throw Exception('Không thể tạo ảnh bằng model AI gemini-nano-banana-2.1. Chi tiết: ${lastError.isNotEmpty ? lastError : "Chưa cấu hình API Key hoặc Proxy không phản hồi."}');
  }
}
