import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Xanh Đen (Deep Navy / Midnight Blue Backgrounds)
  static const Color bgDark = Color(0xFF070B14);       // Nền đen ánh xanh thẳm
  static const Color sidebarBg = Color(0xFF0B132B);     // Xanh đen đậm
  static const Color cardBg = Color(0xFF0F172A);        // Xanh Slate 900
  static const Color inputBg = Color(0xFF050811);       // Nền ô nhập xanh đen
  static const Color borderDark = Color(0xFF1E293B);    // Viền xanh slate 800
  static const Color borderLight = Color(0xFF334155);   // Viền xanh slate 700

  // Màu Vàng (Amber / Cyber Gold Primary Palette)
  static const Color primary = Color(0xFFEAB308);       // Vàng tươi Amber 500
  static const Color primaryHover = Color(0xFFCA8A04);  // Vàng đậm Amber 600
  static const Color primaryLight = Color(0xFFFDE047);  // Vàng sáng Amber 300
  static const Color primaryDark = Color(0xFFA16207);   // Vàng đồng Amber 700

  // Phụ trợ (Accents & Status)
  static const Color accent = Color(0xFF10B981);        // Xanh ngọc lục bảo
  static const Color accentCyan = Color(0xFF38BDF8);    // Xanh cyan ánh sáng
  static const Color warning = Color(0xFFF59E0B);       // Hổ phách
  static const Color danger = Color(0xFFEF4444);        // Đỏ cảnh báo

  // Aliases tương thích
  static const Color surfaceDark = Color(0xFF0B132B);
  static const Color cardDark = Color(0xFF0F172A);

  // Chữ & Biểu tượng
  static const Color textWhite = Color(0xFFF8FAFC);
  static const Color textBody = Color(0xFFE2E8F0);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textDim = Color(0xFF64748B);

  // Terminal & Code
  static const Color terminalBg = Color(0xFF030712);
  static const Color terminalGreen = Color(0xFF22C55E);
  static const Color codeBg = Color(0xFF0B132B);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDark,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.primaryLight,
        surface: AppColors.cardBg,
        error: AppColors.danger,
        onPrimary: Color(0xFF070B14),
        onSecondary: Color(0xFF070B14),
        onSurface: AppColors.textWhite,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ).apply(
        bodyColor: AppColors.textBody,
        displayColor: AppColors.textWhite,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textWhite,
        ),
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.borderDark, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBg,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: const Color(0xFF070B14), // Chữ đen trên nền vàng nổi bật
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.borderDark),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardBg,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.borderDark, width: 1),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textWhite,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textBody,
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide.none,
          ),
          textStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF070B14);
          }
          return const Color(0xFF94A3B8);
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.inputBg;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.borderDark;
        }),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderDark,
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll<bool>(true),
        trackVisibility: const WidgetStatePropertyAll<bool>(true),
        thickness: const WidgetStatePropertyAll<double>(6),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.dragged) || states.contains(WidgetState.hovered)) {
            return AppColors.primary;
          }
          return AppColors.primaryLight.withValues(alpha: 0.6);
        }),
        trackColor: WidgetStatePropertyAll<Color>(AppColors.bgDark.withValues(alpha: 0.5)),
        trackBorderColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
    );
  }
}
