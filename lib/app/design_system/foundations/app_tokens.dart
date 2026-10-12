import 'package:flutter/animation.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadii {
  static const double small = 10;
  static const double medium = 16;
  static const double large = 20;
  static const double pill = 999;
}

abstract final class AppIconSizes {
  static const double small = 18;
  static const double medium = 24;
  static const double large = 32;
}

abstract final class AppTouchTargets {
  static const double minimum = 48;
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration emphasized = Duration(milliseconds: 320);
  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;

  static Duration durationFor({
    required bool reduceMotion,
    Duration duration = standard,
  }) => reduceMotion ? Duration.zero : duration;
}
