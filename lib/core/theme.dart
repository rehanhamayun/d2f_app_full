import 'package:flutter/material.dart';

/// D2F Global design tokens, extracted from the approved UI screens
/// (cream canvas, deep navy type, coral primary, gold + sky-blue accents).
class AppColors {
  AppColors._();

  static const cream = Color(0xFFFFFCF6); // warm ivory reference canvas
  static const deepBlue = Color(0xFF12365C);
  static const deepTeal = Color(0xFF104D55);
  static const deepPurple = Color(0xFF45315D);
  static const navy = Color(0xFF071541); // reference navy headings
  static const textGrey = Color(0xFF697080); // secondary text
  static const border = Color(0xFFE8E6E1); // warm card hairline

  static const coral = Color(0xFFFF5139); // primary actions
  static const coralSoft = Color(0xFFFFEEE9);

  static const gold = Color(0xFFF2B824); // accents / arrows
  static const goldSoft = Color(0xFFFFF4C9);

  static const blue = Color(0xFF0065EE); // info / tracking
  static const blueSoft = Color(0xFFE7F4FF);

  static const green = Color(0xFF159553); // success
  static const greenSoft = Color(0xFFE1F4E9);

  static const teal = Color(0xFF0E8F8A);
  static const tealSoft = Color(0xFFE0F2F1);

  static const indigo = Color(0xFF5B4FC9);
  static const indigoSoft = Color(0xFFEBE9F9);

  static const surface = Colors.white;
  static const primary = coral;
  static const primarySoft = coralSoft;
  static const yellow = Color(0xFFFFDA45);
  static const muted = textGrey;
  static const subtle = Color(0xFFF6F4EE);
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
      case 'REQUESTED':
        return const StatusVisual(
          AppColors.goldSoft,
          Color(0xFF9A7100),
          AppColors.goldSoft,
          AppColors.gold,
        );
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
      case 'ARRIVED_DESTINATION':
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
      case 'RELEASED':
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
        surface: AppColors.cream,
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
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.navy),
        titleTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: AppColors.navy,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        toolbarHeight: 58,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
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
          borderSide: const BorderSide(color: AppColors.blue, width: 1.4),
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
    fontSize: 30,
    height: 1.12,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.1,
  );

  static const TextStyle heading = TextStyle(
    color: AppColors.navy,
    fontSize: 22,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle sectionTitle = TextStyle(
    color: AppColors.navy,
    fontSize: 18,
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

/// Shared spacing and surface geometry derived from all five references.
class AppSpacing {
  AppSpacing._();
  static const double page = 18;
  static const double section = 20;
  static const double gap = 12;
  static const double radius = 18;
  static const double fieldRadius = 14;
  static const double maxWidth = 600;
  static const pageInsets = EdgeInsets.fromLTRB(page, 12, page, 24);
}
