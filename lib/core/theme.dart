import 'package:flutter/material.dart';

/// D2F Global design tokens, extracted from the approved UI screens
/// (cream canvas, deep navy type, coral primary, gold + sky-blue accents).
class AppColors {
  AppColors._();

  static const cream = Color(0xFFEDF2F9); // app canvas
  static const deepBlue = Color(0xFF12365C);
  static const deepTeal = Color(0xFF104D55);
  static const deepPurple = Color(0xFF45315D);
  static const navy = Color(0xFF0B1B46); // headings / primary text
  static const textGrey = Color(0xFF6B7280); // secondary text
  static const border = Color(0xFFDFE7F3); // card hairline

  static const coral = Color(0xFFFF5139); // primary actions
  static const coralSoft = Color(0xFFFFEAE4);

  static const gold = Color(0xFFF0B323); // accents / arrows
  static const goldSoft = Color(0xFFFFF1C9);

  static const blue = Color(0xFF1668DC); // info / tracking
  static const blueSoft = Color(0xFFE3F1FF);

  static const green = Color(0xFF1FA05C); // success
  static const greenSoft = Color(0xFFE1F4E9);

  static const teal = Color(0xFF0E8F8A);
  static const tealSoft = Color(0xFFE0F2F1);

  static const indigo = Color(0xFF5B4FC9);
  static const indigoSoft = Color(0xFFEBE9F9);

  static const chipGrey = Color(0xFFF1EDE4);
}

/// Status → (chip bg, chip fg, tile bg, tile icon color)
class StatusVisual {
  final Color chipBg;
  final Color chipFg;
  final Color tileBg;
  final Color tileIcon;
  const StatusVisual(this.chipBg, this.chipFg, this.tileBg, this.tileIcon);

  static StatusVisual of(String status) {
    switch (status) {
      case 'RECEIVED':
        return const StatusVisual(
          AppColors.coralSoft,
          AppColors.coral,
          AppColors.coralSoft,
          AppColors.coral,
        );
      case 'PROCESSING':
        return const StatusVisual(
          AppColors.goldSoft,
          Color(0xFF9A7100),
          AppColors.goldSoft,
          AppColors.gold,
        );
      case 'IN_TRANSIT':
        return const StatusVisual(
          AppColors.blueSoft,
          AppColors.blue,
          AppColors.blueSoft,
          AppColors.blue,
        );
      case 'ARRIVED_LOME':
        return const StatusVisual(
          AppColors.tealSoft,
          AppColors.teal,
          AppColors.tealSoft,
          AppColors.teal,
        );
      case 'READY_FOR_PICKUP':
        return const StatusVisual(
          AppColors.blueSoft,
          AppColors.blue,
          AppColors.blueSoft,
          AppColors.blue,
        );
      case 'DELIVERED':
        return const StatusVisual(
          AppColors.greenSoft,
          AppColors.green,
          AppColors.greenSoft,
          AppColors.green,
        );
      default:
        return const StatusVisual(
          AppColors.chipGrey,
          AppColors.textGrey,
          AppColors.chipGrey,
          AppColors.textGrey,
        );
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'PlusJakartaSans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.coral,
        primary: AppColors.coral,
        secondary: AppColors.gold,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.cream,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.navy,
        displayColor: AppColors.navy,
      ),
      splashFactory: InkSparkle.splashFactory,
      iconTheme: const IconThemeData(color: AppColors.navy, size: 22),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        toolbarHeight: 64,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFCFDFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.textGrey, fontSize: 13),
        prefixIconColor: AppColors.navy,
        suffixIconColor: AppColors.navy,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.coral, width: 1.4),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: AppColors.navy, fontSize: 13),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static const TextStyle display = TextStyle(
    fontFamily: 'PlusJakartaSans',
    color: AppColors.navy,
    fontSize: 34,
    height: 1.12,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.3,
  );

  static const TextStyle heading = TextStyle(
    color: AppColors.navy,
    fontSize: 22,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle sectionTitle = TextStyle(
    color: AppColors.navy,
    fontSize: 17,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle body = TextStyle(
    color: AppColors.navy,
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    color: AppColors.textGrey,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
}
