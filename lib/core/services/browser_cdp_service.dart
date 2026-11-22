import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'socks5_proxy_service.dart';

/// Điều khiển trình duyệt profile nhân vật qua Chrome DevTools Protocol (CDP).
/// Trình duyệt profile cô lập được khởi chạy với `--remote-debugging-port=0`,
/// Chrome ghi cổng thực tế vào file `DevToolsActivePort` trong thư mục profile.
/// Nhờ vậy AI Agent có thể đọc trang, bấm nút, gõ chữ, tải tệp video lên... thay vì chỉ mở cửa sổ rồi dừng.
class BrowserCdpService {
  static final BrowserCdpService _instance = BrowserCdpService._internal();
  factory BrowserCdpService() => _instance;
  BrowserCdpService._internal();

  final Map<String, _CdpPage> _pages = {};

  /// Chỉ dùng cho kiểm thử: ghi đè thư mục profile của một ProfileKey
  final Map<String, Directory> profileDirOverrides = {};

  Directory profileDirFor(String trackKey) {
    final override = profileDirOverrides[trackKey];
    if (override != null) return override;
    final svc = Socks5ProxyService();
    final cleanIp = Socks5ProxyService.extractCleanIp(trackKey);
    final dirName = trackKey == cleanIp
        ? 'ip_${cleanIp.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}'
        : 'ek_${trackKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    return Directory(p.join(svc.getBrowserProfilesDirectory().path, dirName));
  }

  /// Đọc cổng DevTools đang hoạt động của profile (null nếu trình duyệt không bật cổng điều khiển)
  Future<int?> getDebugPort(String trackKey) async {
    final f = File(p.join(profileDirFor(trackKey).path, 'DevToolsActivePort'));
    if (!f.existsSync()) return null;
    try {
      final lines = await f.readAsLines();
      if (lines.isEmpty) return null;
      final port = int.tryParse(lines.first.trim());
      if (port == null || port <= 0) return null;
      final res = await http
          .get(Uri.parse('http://127.0.0.1:$port/json/version'))
          .timeout(const Duration(milliseconds: 1500));
      return res.statusCode == 200 ? port : null;
    } catch (_) {
      return null;
    }
  }

  /// Chờ cổng DevTools sẵn sàng sau khi vừa mở trình duyệt
  Future<int?> waitForDebugPort(String trackKey, {Duration timeout = const Duration(seconds: 20)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final port = await getDebugPort(trackKey);
      if (port != null) return port;
      await Future.delayed(const Duration(milliseconds: 700));
    }
    return null;
  }

  Future<_CdpPage> _page(String trackKey) async {
    final port = await getDebugPort(trackKey);
    if (port == null) {
      throw const CdpUnavailableException(
          'Trình duyệt của nhân vật chưa bật cổng điều khiển tự động (chưa mở, hoặc được mở trước bản cập nhật / dùng profile trình duyệt hệ thống).');
    }
    final res = await http.get(Uri.parse('http://127.0.0.1:$port/json/list')).timeout(const Duration(seconds: 4));
    final list = jsonDecode(res.body);
    Map<String, dynamic>? target;
    if (list is List) {
      for (final t in list) {
        if (t is Map<String, dynamic> &&
            t['type'] == 'page' &&
            !(t['url']?.toString() ?? '').startsWith('chrome-extension://') &&
            !(t['url']?.toString() ?? '').startsWith('devtools://')) {
          target = t;
          break;
        }
      }
    }
    if (target == null) {
      // Không có tab nào: mở tab mới
      final created = await http
          .put(Uri.parse('http://127.0.0.1:$port/json/new?about:blank'))
          .timeout(const Duration(seconds: 4));
      target = jsonDecode(created.body) as Map<String, dynamic>;
    }
    final targetId = target['id'].toString();
    final cached = _pages[trackKey];
    if (cached != null && cached.targetId == targetId && cached.isOpen) return cached;
    await cached?.close();
    final page = await _CdpPage.connect(target['webSocketDebuggerUrl'].toString(), targetId);
    _pages[trackKey] = page;
    return page;
  }

  Future<dynamic> _eval(_CdpPage page, String js) async {
    final r = await page.send('Runtime.evaluate', {
      'expression': js,
      'returnByValue': true,
      'awaitPromise': true,
    });
    if (r['exceptionDetails'] != null) {
      throw Exception('Lỗi JavaScript: ${r['exceptionDetails']['exception']?['description'] ?? r['exceptionDetails']['text']}');
    }
    return r['result']?['value'];
  }

  Future<void> _waitReady(_CdpPage page, {int seconds = 30}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final st = await _eval(page, 'document.readyState');
        if (st == 'complete' || st == 'interactive') {
          await Future.delayed(const Duration(milliseconds: 800));
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<String> navigate(String trackKey, String url) async {
    final page = await _page(trackKey);
    await page.send('Page.navigate', {'url': url});
    await Future.delayed(const Duration(milliseconds: 600));
    await _waitReady(page);
    final title = await _eval(page, 'document.title');
    final href = await _eval(page, 'location.href');
    return 'Đã mở trang: $title ($href)';
  }

  static const String _snapshotJs = r'''
(() => {
  const vis = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
  const sel = 'a[href],button,input,textarea,select,[role=button],[role=link],[role=textbox],[role=menuitem],[role=tab],[role=checkbox],[role=option],[role=switch],[contenteditable=true],[aria-label][tabindex]';
  document.querySelectorAll('[data-mxh-id]').forEach(e => e.removeAttribute('data-mxh-id'));
  let n = 0; const items = [];
  for (const el of document.querySelectorAll(sel)) {
    const isFile = el.tagName === 'INPUT' && el.type === 'file';
    if (!isFile && !vis(el)) continue;
    const r = el.getBoundingClientRect();
    if (!isFile && (r.bottom < -50 || r.top > innerHeight * 2.5)) continue;
    n++; el.setAttribute('data-mxh-id', String(n));
    const label = (el.getAttribute('aria-label') || el.innerText || el.value || el.getAttribute('placeholder') || el.getAttribute('aria-placeholder') || el.getAttribute('title') || el.getAttribute('name') || '').trim().replace(/\s+/g, ' ').slice(0, 90);
    const it = { id: n, tag: el.tagName.toLowerCase() };
    const role = el.getAttribute('role'); if (role) it.role = role;
    if (el.type && el.tagName === 'INPUT') it.type = el.type;
    if (label) it.label = label;
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') it.disabled = true;
    if (isFile) it.accept = el.accept || '*';
    if (el.isContentEditable) it.editable = true;
    items.push(it);
    if (items.length >= 160) break;
  }
  const text = (document.body ? document.body.innerText : '').replace(/\n{2,}/g, '\n').slice(0, 2500);
  const dialogs = Array.from(document.querySelectorAll('[role=dialog]')).filter(vis).map(d => (d.getAttribute('aria-label') || d.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 120));
  return JSON.stringify({ url: location.href, title: document.title, open_dialogs: dialogs, elements: items, page_text: text });
})()
''';

  Future<String> snapshot(String trackKey) async {
    final page = await _page(trackKey);
    final v = await _eval(page, _snapshotJs);
    return v?.toString() ?? '{}';
  }

  /// Định vị phần tử theo element_id (từ snapshot) hoặc theo nội dung chữ / aria-label
  String _locateJs({int? elementId, String? text}) {
    final idJs = elementId != null ? '"$elementId"' : 'null';
    final textJs = jsonEncode((text ?? '').trim().toLowerCase());
    return '''
(() => {
  let el = null;
  const id = $idJs; const t = $textJs;
  if (id) el = document.querySelector('[data-mxh-id="' + id + '"]');
  if (!el && t) {
    const sel = 'a[href],button,input,textarea,[role=button],[role=link],[role=menuitem],[role=tab],[role=option],[role=textbox],[contenteditable=true],[aria-label],span,div';
    const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    const lab = e => (e.getAttribute('aria-label') || e.innerText || e.value || e.getAttribute('placeholder') || '').trim().replace(/\\s+/g, ' ').toLowerCase();
    const all = Array.from(document.querySelectorAll(sel)).filter(vis);
    el = all.find(e => lab(e) === t) || all.filter(e => lab(e).includes(t)).sort((a, b) => lab(a).length - lab(b).length)[0] || null;
  }
  return el;
})()''';
  }

  Future<Map<String, dynamic>> _locate(_CdpPage page, {int? elementId, String? text}) async {
    final js = '''
(() => {
  const el = ${_locateJs(elementId: elementId, text: text)};
  if (!el) return JSON.stringify({ found: false });
  el.scrollIntoView({ block: 'center', inline: 'center' });
  const r = el.getBoundingClientRect();
  return JSON.stringify({ found: true, x: r.left + r.width / 2, y: r.top + r.height / 2,
    label: (el.getAttribute('aria-label') || el.innerText || el.value || '').trim().replace(/\\s+/g, ' ').slice(0, 80),
    disabled: !!(el.disabled || el.getAttribute('aria-disabled') === 'true') });
})()''';
    final v = await _eval(page, js);
    return jsonDecode(v.toString()) as Map<String, dynamic>;
  }

  Future<String> click(String trackKey, {int? elementId, String? text}) async {
    final page = await _page(trackKey);
    final loc = await _locate(page, elementId: elementId, text: text);
    if (loc['found'] != true) {
      return 'LỖI: Không tìm thấy phần tử (id=$elementId, text="$text"). Hãy gọi browser_snapshot để lấy lại danh sách phần tử.';
    }
    if (loc['disabled'] == true) {
      return 'LỖI: Phần tử "${loc['label']}" đang bị vô hiệu hóa (disabled). Có thể cần chờ tải lên/xử lý xong hoặc điền đủ thông tin trước.';
    }
    await Future.delayed(const Duration(milliseconds: 250));
    final loc2 = await _locate(page, elementId: elementId, text: text);
    final x = (loc2['x'] as num?)?.toDouble() ?? (loc['x'] as num).toDouble();
    final y = (loc2['y'] as num?)?.toDouble() ?? (loc['y'] as num).toDouble();
    await page.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
    await page.send('Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
    await Future.delayed(const Duration(milliseconds: 60));
    await page.send('Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
    await Future.delayed(const Duration(milliseconds: 1200));
    return 'Đã bấm vào "${loc['label']}".';
  }

  Future<String> type(String trackKey, {int? elementId, String? targetText, required String text, bool clear = false}) async {
    final page = await _page(trackKey);
    final focusJs = '''
(() => {
  const el = ${_locateJs(elementId: elementId, text: targetText)};
  if (!el) return 'NOT_FOUND';
  el.scrollIntoView({ block: 'center' });
  el.focus();
  if ($clear) {
    if (el.isContentEditable) { document.execCommand('selectAll', false, null); document.execCommand('delete', false, null); }
    else if ('value' in el) { el.value = ''; el.dispatchEvent(new Event('input', { bubbles: true })); }
  }
  return 'OK';
})()''';
    final r = await _eval(page, focusJs);
    if (r != 'OK') {
      return 'LỖI: Không tìm thấy ô nhập (id=$elementId). Hãy gọi browser_snapshot để lấy lại danh sách phần tử.';
    }
    await page.send('Input.insertText', {'text': text});
    await Future.delayed(const Duration(milliseconds: 500));
    return 'Đã nhập ${text.length} ký tự vào ô.';
  }

  Future<String> uploadFile(String trackKey, {required String filePath, int? elementId}) async {
    final f = File(filePath);
    if (!f.existsSync()) {
      return 'LỖI: Tệp không tồn tại trên máy: $filePath';
    }
    final page = await _page(trackKey);
    final idJs = elementId != null ? '"$elementId"' : 'null';
    final pickJs = '''
(() => {
  const id = $idJs;
  let el = id ? document.querySelector('[data-mxh-id="' + id + '"]') : null;
  if (el && !(el.tagName === 'INPUT' && el.type === 'file')) el = el.querySelector('input[type=file]');
  if (!el) {
    const inputs = Array.from(document.querySelectorAll('input[type=file]'));
    el = inputs.reverse().find(i => (i.accept || '').includes('video')) || inputs[0] || null;
  }
  return el;
})()''';
    final r = await page.send('Runtime.evaluate', {'expression': pickJs, 'returnByValue': false});
    final objectId = r['result']?['objectId'];
    if (objectId == null) {
      return 'LỖI: Trang hiện tại chưa có ô chọn tệp (input[type=file]). Hãy bấm nút "Ảnh/video" hoặc "Tải lên" trong khung đăng bài trước, rồi gọi lại browser_upload_file.';
    }
    await page.send('DOM.enable', {});
    await page.send('DOM.setFileInputFiles', {'files': [f.absolute.path], 'objectId': objectId});
    await Future.delayed(const Duration(milliseconds: 1500));
    final sizeMb = (f.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    return 'Đã gắn tệp ${p.basename(filePath)} ($sizeMb MB) vào ô tải lên. Hãy dùng browser_wait / browser_snapshot để chờ tải lên xử lý xong trước khi bấm Đăng.';
  }

  Future<String> pressKey(String trackKey, String key) async {
    final page = await _page(trackKey);
    const codes = {'Enter': 13, 'Escape': 27, 'Tab': 9, 'Backspace': 8, 'ArrowDown': 40, 'ArrowUp': 38, 'Space': 32};
    final norm = codes.keys.firstWhere((k) => k.toLowerCase() == key.toLowerCase(), orElse: () => 'Enter');
    final code = codes[norm]!;
    final keyName = norm == 'Space' ? ' ' : norm;
    await page.send('Input.dispatchKeyEvent', {
      'type': 'keyDown',
      'key': keyName,
      'code': norm,
      'windowsVirtualKeyCode': code,
      if (norm == 'Enter') 'text': '\r',
      if (norm == 'Space') 'text': ' ',
    });
    await page.send('Input.dispatchKeyEvent', {'type': 'keyUp', 'key': keyName, 'code': norm, 'windowsVirtualKeyCode': code});
    await Future.delayed(const Duration(milliseconds: 600));
    return 'Đã nhấn phím $norm.';
  }

  Future<String> scroll(String trackKey, int deltaY) async {
    final page = await _page(trackKey);
    await _eval(page, 'window.scrollBy({ top: $deltaY, behavior: "smooth" }); true');
    await Future.delayed(const Duration(milliseconds: 900));
    return 'Đã cuộn trang $deltaY px.';
  }

  /// Chờ đến khi trang xuất hiện (hoặc biến mất) đoạn chữ, tối đa [seconds] giây
  Future<String> waitFor(String trackKey, {String? text, bool untilGone = false, int seconds = 10}) async {
    final page = await _page(trackKey);
    final s = seconds.clamp(1, 600);
    if (text == null || text.trim().isEmpty) {
      await Future.delayed(Duration(seconds: s));
      return 'Đã chờ $s giây.';
    }
    final needle = jsonEncode(text.trim().toLowerCase());
    final deadline = DateTime.now().add(Duration(seconds: s));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final has = await _eval(page, '(document.body ? document.body.innerText.toLowerCase() : "").includes($needle)');
        if (has == true && !untilGone) return 'Đã thấy "$text" trên trang.';
        if (has != true && untilGone) return 'Chữ "$text" đã biến mất khỏi trang.';
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
    return untilGone
        ? 'HẾT THỜI GIAN: Sau $s giây chữ "$text" vẫn còn trên trang.'
        : 'HẾT THỜI GIAN: Sau $s giây vẫn chưa thấy "$text" trên trang.';
  }

  Future<String> screenshot(String trackKey) async {
    final page = await _page(trackKey);
    final r = await page.send('Page.captureScreenshot', {'format': 'png'}, timeout: const Duration(seconds: 20));
    final data = r['data']?.toString();
    if (data == null) return 'LỖI: Không chụp được màn hình.';
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final dir = Directory(p.join(home, '.agent_mxh_auto', 'screenshots'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safeKey = trackKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final path = p.join(dir.path, 'shot_${safeKey}_${DateTime.now().millisecondsSinceEpoch}.png');
    await File(path).writeAsBytes(base64Decode(data));
    return 'Đã chụp màn hình làm bằng chứng: $path';
  }

  Future<void> disconnect(String trackKey) async {
    await _pages.remove(trackKey)?.close();
  }
}

class CdpUnavailableException implements Exception {
  final String message;
  const CdpUnavailableException(this.message);
  @override
  String toString() => message;
}

class _CdpPage {
  final WebSocket ws;
  final String targetId;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  bool _closed = false;

  _CdpPage._(this.ws, this.targetId) {
    ws.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw.toString());
          if (msg is Map<String, dynamic> && msg['id'] is int) {
            final c = _pending.remove(msg['id']);
            if (c != null && !c.isCompleted) {
              if (msg['error'] != null) {
                c.completeError(Exception('CDP: ${msg['error']['message']}'));
              } else {
                c.complete((msg['result'] as Map?)?.cast<String, dynamic>() ?? {});
              }
            }
          }
        } catch (_) {}
      },
      onDone: _failAll,
      onError: (_) => _failAll(),
      cancelOnError: true,
    );
  }

  void _failAll() {
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(Exception('Mất kết nối tới tab trình duyệt'));
    }
    _pending.clear();
  }

  bool get isOpen => !_closed && ws.readyState == WebSocket.open;

  static Future<_CdpPage> connect(String wsUrl, String targetId) async {
    final ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 6));
    return _CdpPage._(ws, targetId);
  }

  Future<Map<String, dynamic>> send(String method, Map<String, dynamic> params,
      {Duration timeout = const Duration(seconds: 30)}) {
    if (!isOpen) return Future.error(Exception('Tab trình duyệt đã đóng'));
    final id = _nextId++;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    ws.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('CDP $method quá thời gian');
    });
  }

  Future<void> close() async {
    _closed = true;
    try {
      await ws.close();
    } catch (_) {}
  }
}
