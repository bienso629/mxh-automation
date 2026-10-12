import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/chat_message.dart';

class PdfExportService {
  static Future<pw.ImageProvider?> _loadLogoImage() async {
    // 1. Try rootBundle logo.jpg
    try {
      final ByteData data = await rootBundle.load('assets/logo.jpg');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.isNotEmpty) return pw.MemoryImage(bytes);
    } catch (_) {}

    // 2. Try rootBundle icon.png
    try {
      final ByteData data = await rootBundle.load('assets/icon.png');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.isNotEmpty) return pw.MemoryImage(bytes);
    } catch (_) {}

    // 3. Try filesystem relative & absolute paths (Desktop only)
    if (!kIsWeb) {
      final candidatePaths = [
        'assets/logo.jpg',
        'assets/icon.png',
        'mobile/assets/logo.jpg',
        'mobile/assets/icon.png',
        '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/mobile/assets/logo.jpg',
        '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/mobile/assets/icon.png',
      ];

      for (final p in candidatePaths) {
        try {
          final f = File(p);
          if (f.existsSync()) {
            final bytes = f.readAsBytesSync();
            if (bytes.isNotEmpty) return pw.MemoryImage(bytes);
          }
        } catch (_) {}
      }
    }

    return null;
  }

  /// Parses inline markdown such as **bold**, `code`, *italic* into pw.RichText spans
  static pw.InlineSpan _buildInlineSpans(
    String text,
    pw.Font font,
    pw.Font fontBold,
    pw.Font fontMono, {
    PdfColor? defaultColor,
    double fontSize = 9.5,
    double lineSpacing = 1.35,
  }) {
    final textColor = defaultColor ?? PdfColors.grey900;
    final List<pw.InlineSpan> spans = [];

    // Regex to match **bold**, `code`, *italic*
    final reg = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`|\*[^*]+\*)');
    int lastEnd = 0;

    for (final match in reg.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          pw.TextSpan(
            text: text.substring(lastEnd, match.start),
            style: pw.TextStyle(font: font, fontSize: fontSize, color: textColor, lineSpacing: lineSpacing),
          ),
        );
      }

      final token = match.group(0)!;
      if (token.startsWith('**') && token.endsWith('**')) {
        spans.add(
          pw.TextSpan(
            text: token.substring(2, token.length - 2),
            style: pw.TextStyle(
              font: fontBold,
              fontSize: fontSize,
              color: textColor == PdfColors.grey900 ? PdfColors.black : textColor,
              fontWeight: pw.FontWeight.bold,
              lineSpacing: lineSpacing,
            ),
          ),
        );
      } else if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(
          pw.TextSpan(
            text: ' ${token.substring(1, token.length - 1)} ',
            style: pw.TextStyle(
              font: fontMono,
              fontSize: fontSize * 0.9,
              color: PdfColors.red800,
              lineSpacing: lineSpacing,
              background: const pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
            ),
          ),
        );
      } else if (token.startsWith('*') && token.endsWith('*')) {
        spans.add(
          pw.TextSpan(
            text: token.substring(1, token.length - 1),
            style: pw.TextStyle(font: font, fontSize: fontSize, color: textColor, fontStyle: pw.FontStyle.italic, lineSpacing: lineSpacing),
          ),
        );
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(
        pw.TextSpan(
          text: text.substring(lastEnd),
          style: pw.TextStyle(font: font, fontSize: fontSize, color: textColor, lineSpacing: lineSpacing),
        ),
      );
    }

    return pw.TextSpan(children: spans);
  }

  /// Cleans problematic high surrogate emoji characters while preserving readable badges
  static String _cleanEmoji(String input) {
    var text = input;
    text = text.replaceAll('👋', '');
    text = text.replaceAll('📊', '[Thống kê]');
    text = text.replaceAll('🔄', '[Tải lại]');
    text = text.replaceAll('⚡', '[Tác vụ]');
    text = text.replaceAll('🛡️', '[Bảo mật]');
    text = text.replaceAll('🛡', '[Bảo mật]');
    text = text.replaceAll('🧹', '[Dọn dẹp]');
    text = text.replaceAll('🔍', '[Tìm kiếm]');
    text = text.replaceAll('🚀', '[Triển khai]');
    text = text.replaceAll('✅', '[✔]');
    text = text.replaceAll('✔️', '[✔]');
    text = text.replaceAll('❌', '[✕]');
    text = text.replaceAll('⚠️', '[!]');
    text = text.replaceAll('📋', '[Copy]');
    text = text.replaceAll('📄', '[Tài liệu]');
    text = text.replaceAll('🖥️', '[Server]');
    text = text.replaceAll('🖥', '[Server]');
    text = text.replaceAll('🧠', '[AI]');
    text = text.replaceAll('💡', '[Gợi ý]');
    text = text.replaceAll('🎯', '[Mục tiêu]');
    text = text.replaceAll('📌', '[Ghim]');
    text = text.replaceAll('🕒', '[Thời gian]');
    text = text.replaceAll('⚙️', '[Cấu hình]');
    text = text.replaceAll('⚙', '[Cấu hình]');
    text = text.replaceAll('🔧', '[Công cụ]');

    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}|\u{1F300}-\u{1F5FF}|\u{1F680}-\u{1F6FF}|\u{1F1E0}-\u{1F1FF}|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}|\u{FE00}-\u{FE0F}|\u{1F900}-\u{1F9FF}|\u{1FA00}-\u{1FA6F}|\u{1FA70}-\u{1FAFF}]',
      unicode: true,
    );
    return text.replaceAll(emojiRegex, '');
  }

  static Future<String?> exportMessageToPdf(ChatMessageModel msg, {String? serverInfo}) async {
    final pdf = pw.Document();

    pw.Font font;
    pw.Font fontBold;
    pw.Font fontMono;

    // Load fonts with offline fallback
    try {
      if (File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf').existsSync()) {
        final fontBytes = await File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf').readAsBytes();
        font = pw.Font.ttf(fontBytes.buffer.asByteData());

        if (File('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf').existsSync()) {
          final boldBytes = await File('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf').readAsBytes();
          fontBold = pw.Font.ttf(boldBytes.buffer.asByteData());
        } else {
          fontBold = font;
        }

        if (File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf').existsSync()) {
          final monoBytes = await File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf').readAsBytes();
          fontMono = pw.Font.ttf(monoBytes.buffer.asByteData());
        } else {
          fontMono = font;
        }
      } else {
        font = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
        fontMono = pw.Font.courier();
      }
    } catch (_) {
      font = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
      fontMono = pw.Font.courier();
    }

    // Load Tadu Logo
    final logoImage = await _loadLogoImage();

    final timeStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(msg.createdAt);
      final filename = 'Tadu_AI_Report_${DateFormat('yyyyMMdd_HHmmss').format(msg.createdAt)}.pdf';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 100,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logoImage != null)
                        pw.Container(
                          width: 36,
                          height: 36,
                          margin: const pw.EdgeInsets.only(right: 10),
                          decoration: pw.BoxDecoration(
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                          ),
                          child: pw.ClipRRect(
                            horizontalRadius: 6,
                            verticalRadius: 6,
                            child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                          ),
                        )
                      else
                        pw.Container(
                          width: 36,
                          height: 36,
                          margin: const pw.EdgeInsets.only(right: 10),
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.red800,
                            borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text('TADU', style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 10)),
                        ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'MXH TỰ ĐỘNG',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 16,
                              color: PdfColors.blue800,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Báo Cáo Phân Tích & Hướng Dẫn Kỹ Thuật Máy Chủ',
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 8.5,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        child: pw.Text(
                          'Thời gian: $timeStr',
                          style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey800),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Hệ thống: ${serverInfo ?? 'Linux Remote Server'}',
                        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                height: 2,
                color: PdfColors.red700,
              ),
              pw.SizedBox(height: 16),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Báo cáo được xuất tự động bởi Diễn viên MXH',
                    style: pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.grey500),
                  ),
                  pw.Text(
                    'Trang ${context.pageNumber} / ${context.pagesCount}',
                    style: pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          // 1. Tool Executions (Terminal Commands)
          if (msg.toolExecutions.isNotEmpty) {
            for (final tool in msg.toolExecutions) {
              // Command header
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.blue800,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        child: pw.Text(
                          '>_ SHELL',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 7.5,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Text(
                          _cleanEmoji(tool.command),
                          style: pw.TextStyle(
                            font: fontMono,
                            fontSize: 8.5,
                            color: PdfColors.blue900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );

              // Command Output: Safe chunking to prevent PdfTooBigPageException
              if (tool.output.isNotEmpty) {
                final cleanOut = _cleanEmoji(tool.output.trim());
                final outLines = cleanOut.split('\n');
                List<String> outputLinesToRender = outLines;

                // If output is massive (> 40 lines), keep head & tail with summary
                if (outLines.length > 40) {
                  outputLinesToRender = [
                    ...outLines.take(25),
                    '... [Đã rút gọn ${outLines.length - 35} dòng output terminal dài] ...',
                    ...outLines.skip(outLines.length - 10),
                  ];
                }

                // Chunk into blocks of max 20 lines so each block easily fits on a page
                const int chunkSize = 20;
                for (int c = 0; c < outputLinesToRender.length; c += chunkSize) {
                  final end = (c + chunkSize < outputLinesToRender.length) ? c + chunkSize : outputLinesToRender.length;
                  final chunkText = outputLinesToRender.sublist(c, end).join('\n');
                  widgets.add(
                    pw.Container(
                      width: double.infinity,
                      margin: const pw.EdgeInsets.only(bottom: 2),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFF0F172A),
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                      ),
                      child: pw.Text(
                        chunkText,
                        style: pw.TextStyle(
                          font: fontMono,
                          fontSize: 8.0,
                          color: PdfColor.fromInt(0xFF38BDF8),
                          lineSpacing: 1.35,
                        ),
                      ),
                    ),
                  );
                }
                widgets.add(pw.SizedBox(height: 8));
              }
            }
          }

          // 2. Structured Markdown Parser
          final rawContent = _cleanEmoji(msg.content);
          final lines = rawContent.split('\n');

          bool inCodeBlock = false;
          final List<String> codeBlockBuffer = [];
          final List<String> tableBuffer = [];

          void flushCodeBlock() {
            if (codeBlockBuffer.isEmpty) return;
            const int chunkSize = 25;
            for (int c = 0; c < codeBlockBuffer.length; c += chunkSize) {
              final end = (c + chunkSize < codeBlockBuffer.length) ? c + chunkSize : codeBlockBuffer.length;
              final chunkText = codeBlockBuffer.sublist(c, end).join('\n');
              widgets.add(
                pw.Container(
                  width: double.infinity,
                  margin: const pw.EdgeInsets.only(bottom: 3),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFF0F172A),
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    chunkText,
                    style: pw.TextStyle(
                      font: fontMono,
                      fontSize: 8.2,
                      color: PdfColor.fromInt(0xFF4ADE80),
                      lineSpacing: 1.4,
                    ),
                  ),
                ),
              );
            }
            widgets.add(pw.SizedBox(height: 6));
            codeBlockBuffer.clear();
          }

          void flushTable() {
            if (tableBuffer.isEmpty) return;
            final rows = <pw.TableRow>[];

            for (int r = 0; r < tableBuffer.length; r++) {
              final rowLine = tableBuffer[r].trim();
              if (rowLine.contains('---') || rowLine.contains('===') || rowLine.replaceFirst(RegExp(r'^\|'), '').replaceFirst(RegExp(r'\|$'), '').trim().split('|').every((c) => c.trim().startsWith('-'))) {
                continue;
              }

              final rawCells = rowLine.split('|');
              final cells = <String>[];
              for (int c = 0; c < rawCells.length; c++) {
                if (c == 0 && rawCells[c].trim().isEmpty) continue;
                if (c == rawCells.length - 1 && rawCells[c].trim().isEmpty) continue;
                cells.add(rawCells[c].trim());
              }

              if (cells.isEmpty) continue;
              final isHeader = (r == 0);

              rows.add(
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: isHeader ? PdfColors.grey200 : (rows.length % 2 == 0 ? PdfColors.white : PdfColors.grey50),
                  ),
                  children: cells.map((cellText) {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: isHeader
                          ? pw.Text(
                              cellText,
                              style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.black),
                            )
                          : pw.RichText(
                              text: _buildInlineSpans(cellText, font, fontBold, fontMono, fontSize: 8.5, lineSpacing: 1.35),
                            ),
                    );
                  }).toList(),
                ),
              );
            }

            if (rows.isNotEmpty) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
                    children: rows,
                  ),
                ),
              );
            }
            tableBuffer.clear();
          }

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            final trimmed = line.trim();

            // Table detection
            if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
              tableBuffer.add(trimmed);
              continue;
            } else if (tableBuffer.isNotEmpty) {
              flushTable();
            }

            // Code block toggle
            if (trimmed.startsWith('```')) {
              if (inCodeBlock) {
                inCodeBlock = false;
                flushCodeBlock();
              } else {
                inCodeBlock = true;
              }
              continue;
            }

            if (inCodeBlock) {
              codeBlockBuffer.add(line);
              continue;
            }

            if (trimmed.isEmpty) {
              widgets.add(pw.SizedBox(height: 4));
            } else if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                ),
              );
            } else if (trimmed.startsWith('#### ')) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
                  child: pw.RichText(
                    text: _buildInlineSpans(
                      trimmed.substring(5),
                      fontBold,
                      fontBold,
                      fontMono,
                      defaultColor: PdfColors.blueGrey800,
                      fontSize: 9.6,
                      lineSpacing: 1.15,
                    ),
                  ),
                ),
              );
            } else if (trimmed.startsWith('### ')) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
                  child: pw.RichText(
                    text: _buildInlineSpans(
                      trimmed.substring(4),
                      fontBold,
                      fontBold,
                      fontMono,
                      defaultColor: PdfColors.red800,
                      fontSize: 10.5,
                      lineSpacing: 1.15,
                    ),
                  ),
                ),
              );
            } else if (trimmed.startsWith('## ')) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
                  child: pw.RichText(
                    text: _buildInlineSpans(
                      trimmed.substring(3),
                      fontBold,
                      fontBold,
                      fontMono,
                      defaultColor: PdfColors.red900,
                      fontSize: 11.2,
                      lineSpacing: 1.15,
                    ),
                  ),
                ),
              );
            } else if (trimmed.startsWith('# ')) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
                  child: pw.RichText(
                    text: _buildInlineSpans(
                      trimmed.substring(2),
                      fontBold,
                      fontBold,
                      fontMono,
                      defaultColor: PdfColors.red900,
                      fontSize: 12.5,
                      lineSpacing: 1.15,
                    ),
                  ),
                ),
              );
            } else if (trimmed.startsWith('> ')) {
              // Blockquote
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 4),
                  padding: const pw.EdgeInsets.only(left: 10, top: 4, bottom: 4, right: 8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border(
                      left: pw.BorderSide(color: PdfColors.red800, width: 3),
                    ),
                  ),
                  child: pw.RichText(
                    text: _buildInlineSpans(trimmed.substring(2), font, fontBold, fontMono, defaultColor: PdfColors.grey800, fontSize: 9.2, lineSpacing: 1.35),
                  ),
                ),
              );
            } else if (trimmed.startsWith('* ') || trimmed.startsWith('- ') || trimmed.startsWith('+ ')) {
              // Bullet item
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, top: 1, bottom: 3),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 4,
                        height: 4,
                        margin: const pw.EdgeInsets.only(top: 5, right: 7),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.red800,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.RichText(
                          text: _buildInlineSpans(trimmed.substring(2), font, fontBold, fontMono, fontSize: 9.5, lineSpacing: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } else if (RegExp(r'^\d+\.\s+').hasMatch(trimmed)) {
              // Numbered item
              final match = RegExp(r'^(\d+\.)\s+(.*)').firstMatch(trimmed);
              final numPrefix = match?.group(1) ?? '1.';
              final itemContent = match?.group(2) ?? trimmed;

              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, top: 1, bottom: 3),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 18,
                        child: pw.Text(
                          numPrefix,
                          style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.red800),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.RichText(
                          text: _buildInlineSpans(itemContent, font, fontBold, fontMono, fontSize: 9.5, lineSpacing: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } else {
              // Regular paragraph with rich inline formatting
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.RichText(
                    text: _buildInlineSpans(line, font, fontBold, fontMono, fontSize: 9.5, lineSpacing: 1.35),
                  ),
                ),
              );
            }
          }

          if (tableBuffer.isNotEmpty) {
            flushTable();
          }

          if (inCodeBlock && codeBlockBuffer.isNotEmpty) {
            flushCodeBlock();
          }

          return widgets;
        },
      ),
    );

    Uint8List bytes;
    try {
      bytes = await pdf.save();
    } catch (_) {
      // Fallback: Generate a simplified, unconstrained document if any layout error occurs
      final fallbackPdf = pw.Document();
      final cleanText = _cleanEmoji(msg.content);
      fallbackPdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          maxPages: 100,
          margin: const pw.EdgeInsets.all(36),
          build: (pw.Context context) {
            return [
              pw.Text('MXH TỰ ĐỘNG - REPORT', style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.red800)),
              pw.SizedBox(height: 4),
              pw.Text('Thời gian: $timeStr | Hệ thống: ${serverInfo ?? 'Linux Server'}', style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey700)),
              pw.Divider(color: PdfColors.red700, thickness: 1.5),
              pw.SizedBox(height: 12),
              ...cleanText.split('\n').map((l) => pw.Paragraph(
                text: l,
                style: pw.TextStyle(font: font, fontSize: 9.5, lineSpacing: 1.3),
              )),
            ];
          },
        ),
      );
      bytes = await fallbackPdf.save();
    }

    String? savedFilePath;

    if (kIsWeb) {
      // Web: Trigger browser download via Printing
      try {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } catch (_) {}
      return filename;
    }

    // Desktop: Direct Save to ~/Downloads
    try {
      final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (homeDir != null) {
        final downloadsDir = Directory('$homeDir/Downloads');
        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }
        final file = File('${downloadsDir.path}/$filename');
        await file.writeAsBytes(bytes);
        savedFilePath = file.path;
      }
    } catch (_) {}

    // Auto open the PDF file in default viewer
    if (savedFilePath != null && File(savedFilePath).existsSync()) {
      try {
        if (Platform.isLinux) {
          Process.run('xdg-open', [savedFilePath]);
        } else if (Platform.isMacOS) {
          Process.run('open', [savedFilePath]);
        } else if (Platform.isWindows) {
          Process.run('cmd', ['/c', 'start', '', savedFilePath]);
        }
      } catch (_) {}
    }

    return savedFilePath ?? filename;
  }
}
