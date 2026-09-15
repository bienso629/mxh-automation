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
  bool _isLoaded = false;

  String get _storageFilePath {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final dir = p.join(home, '.agent_mxh_auto');
    if (!Directory(dir).existsSync()) {
      try {
        Directory(dir).createSync(recursive: true);
      } catch (_) {}
    }
    return p.join(dir, 'personas.json');
  }

  /// Nạp danh sách nhân vật từ database local của app (fallback json nếu chưa có trong DB)
  Future<Map<String, PersonaProfile>> loadSavedPersonas() async {
    if (_isLoaded && _cachedPersonas.isNotEmpty) {
      return Map.unmodifiable(_cachedPersonas);
    }

    try {
      // 1. Thử tải từ database SQLite local
      final dbPersonas = await _dbService.getPersonaProfiles();
      if (dbPersonas.isNotEmpty) {
        _cachedPersonas.addAll(dbPersonas);
      }
    } catch (_) {}

    // 2. Đồng bộ thêm từ file JSON nếu database còn thiếu profile nào
    try {
      final file = File(_storageFilePath);
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
- agent_info: Vai trò, nhiệm vụ chính của nhân vật này trong hệ thống MXH (ví dụ: "Seeding bài viết ẩm thực, bình luận chia sẻ kinh nghiệm quán ăn, tạo tương tác tự nhiên với khách hàng", hoặc "Review đồ công nghệ, trả lời giải đáp thắc mắc người xem livestream", hoặc "Chăm sóc khách hàng, tương tác thân thiện trong group cộng đồng"...)
- avatar_prompt: Một prompt chi tiết bằng tiếng Anh chuyên dùng cho AI vẽ ảnh (Midjourney/FLUX/Stable Diffusion) để tạo chân dung cận cảnh avatar cho nhân vật này. ĐẶC BIỆT: Prompt ảnh BẮT BUỘC PHẢI THỂ HIỆN RÕ CÁ TÍNH, VAI TRÒ VÀ NHIỆM VỤ của nhân vật từ bio và agent_info (ví dụ về trang phục, biểu cảm khuôn mặt, ánh mắt, bối cảnh làm việc hoặc môi trường phù hợp với vai trò của họ). Ví dụ: "Close-up portrait of a 24-year-old Vietnamese female food reviewer, vibrant cheerful expression, stylish casual hoodie, holding a subtle coffee cup, blurred modern cafe background with warm bokeh lights, cinematic sunlight, hyperrealistic 8k".

BẮT BUỘC TRẢ VỀ ĐỊNH DẠNG JSON DUY NHẤT (không bọc trong markdown hoặc chỉ bọc trong ```json ... ```):
[
  {
    "ip": "...",
    "name": "...",
    "age": 25,
    "gender": "Nam",
    "bio": "...",
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

    // Xây dựng prompt avatar người thật chụp ảnh chân dung (Photorealistic Portrait Photo)
    String effectivePrompt;
    if (persona.avatarPrompt.trim().isNotEmpty) {
      effectivePrompt = persona.avatarPrompt.trim();
      final extraDetails = <String>[];
      if (persona.bio.trim().isNotEmpty && !effectivePrompt.toLowerCase().contains(persona.bio.toLowerCase().split(' ').first)) {
        extraDetails.add('personality: ${persona.bio.trim()}');
      }
      if (persona.agentInfo != null && persona.agentInfo!.trim().isNotEmpty && !effectivePrompt.toLowerCase().contains(persona.agentInfo!.toLowerCase().split(' ').first)) {
        extraDetails.add('role: ${persona.agentInfo!.trim()}');
      }
      if (extraDetails.isNotEmpty) {
        effectivePrompt = '$effectivePrompt, ${extraDetails.join(", ")}';
      }
      effectivePrompt += ', authentic realistic human portrait photography, real person face, natural skin texture, 35mm photograph, DSLR, soft natural studio lighting, ultra-realistic, highly detailed, high quality photo, NO 3D render, NO cartoon, NO illustration, NO vector icon, NO drawing';
    } else {
      final roleContext = (persona.agentInfo != null && persona.agentInfo!.trim().isNotEmpty)
          ? ', role: ${persona.agentInfo!.trim()}'
          : '';
      final bioContext = persona.bio.trim().isNotEmpty ? ', personality: ${persona.bio.trim()}' : '';
      effectivePrompt = 'Authentic close-up photography portrait of a real ${persona.gender.toLowerCase() == "nữ" ? "Vietnamese woman" : "Vietnamese man"}, ${persona.age} years old, name ${persona.name}$bioContext$roleContext, beautiful natural facial features, real human skin pores and texture, natural casual outfit, cinematic bokeh background, captured on Canon EOS R5 85mm lens, photorealistic 8k, ultra-realistic photo, NO 3D render, NO cartoon, NO anime, NO vector graphics, NO CGI';
    }

    // 1. NHÁNH CLOUD API PROXY: Thử gọi Cloud Image Model qua mitom.ai (DALL-E / FLUX / Wan / Doubao Image)
    if (apiKey.isNotEmpty) {
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
              'size': '512x512',
              'response_format': 'b64_json',
            }),
          ).timeout(const Duration(seconds: 40));

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
                final dlRes = await http.get(Uri.parse(imgUrl)).timeout(const Duration(seconds: 25));
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

    // 2. ENGINE AI PHOTO SYNTHESIS (FLUX & TURBO PHOTOREALISTIC ENGINE)
    // Tạo ảnh chân dung người thật bằng mô hình khuếch tán AI chuyên ảnh thực (FLUX / Turbo / Photo Real)
    final aiPhotoModels = ['flux', 'turbo'];
    final seed = '${persona.ip}_${persona.name}_${persona.gender}_$timestamp'.hashCode.abs();

    for (final aiModelName in aiPhotoModels) {
      try {
        final promptForGen = Uri.encodeComponent(effectivePrompt);
        final aiGenUrl = 'https://image.pollinations.ai/prompt/$promptForGen?width=512&height=512&nologo=true&seed=$seed&model=$aiModelName&enhance=true';
        final genRes = await http.get(
          Uri.parse(aiGenUrl),
          headers: {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'},
        ).timeout(const Duration(seconds: 35));

        if (genRes.statusCode == 200 && genRes.bodyBytes.length > 5000) {
          await File(localImagePath).writeAsBytes(genRes.bodyBytes);
          final updated = persona.copyWith(avatarUrl: localImagePath);
          await updatePersona(updated);
          return localImagePath;
        }
      } catch (_) {}
    }

    // 3. DỰ PHÒNG CHÂN DUNG NGƯỜI THẬT CHUYÊN DỤNG (Tuyệt đối không dùng 3D vector cartoon)
    // Sử dụng bộ sinh ảnh khuôn mặt người thật ngẫu nhiên từ kho ảnh chân dung thực tế
    try {
      final genderParam = persona.gender.toLowerCase() == 'nữ' ? 'female' : 'male';
      final faceIndex = (seed % 90) + 1;
      final realHumanFaceUrl = 'https://xsgames.co/randomusers/assets/avatars/$genderParam/$faceIndex.jpg';
      final dlFace = await http.get(Uri.parse(realHumanFaceUrl)).timeout(const Duration(seconds: 15));
      if (dlFace.statusCode == 200 && dlFace.bodyBytes.length > 3000) {
        await File(localImagePath).writeAsBytes(dlFace.bodyBytes);
        final updated = persona.copyWith(avatarUrl: localImagePath);
        await updatePersona(updated);
        return localImagePath;
      }
    } catch (_) {}

    // Fallback ảnh chân dung người thật Unsplash AI curated portrait
    final isFemale = persona.gender.toLowerCase() == 'nữ';
    final photoFallbackUrl = isFemale
        ? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=512&q=80'
        : 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=512&q=80';
    try {
      final dlPhoto = await http.get(Uri.parse(photoFallbackUrl)).timeout(const Duration(seconds: 15));
      if (dlPhoto.statusCode == 200 && dlPhoto.bodyBytes.length > 3000) {
        await File(localImagePath).writeAsBytes(dlPhoto.bodyBytes);
        final updated = persona.copyWith(avatarUrl: localImagePath);
        await updatePersona(updated);
        return localImagePath;
      }
    } catch (_) {}

    final updated = persona.copyWith(avatarUrl: photoFallbackUrl);
    await updatePersona(updated);
    return photoFallbackUrl;
  }
}
