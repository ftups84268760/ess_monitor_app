import 'package:flutter/material.dart';

// 能流圖軌跡結構類別定義
class EnergyPathConfig {
  final String svgPath;
  final Color baseLineColor;
  final Color particleColor;
  final bool isReverse;
  final bool isActive;

  EnergyPathConfig({
    required this.svgPath,
    required this.baseLineColor,
    required this.particleColor,
    this.isReverse = false,
    this.isActive = true,
  });
}