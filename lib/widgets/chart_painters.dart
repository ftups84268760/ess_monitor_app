import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:path_drawing/path_drawing.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;
import '../models/energy_path_config.dart';

class EnergyFlowPainter extends CustomPainter {
  final double progress;
  final int dcAcPowerDirection;
  final int linePowerDirection;
  final int batteryPowerDirection;
  final double loadPower;

  EnergyFlowPainter({
    required this.progress,
    this.dcAcPowerDirection = 1,
    this.linePowerDirection = 1,
    this.batteryPowerDirection = 1,
    this.loadPower = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const String pathPvToInverter = "M576 422V300L676 257";
    const String pathInverterToLoad = "M642 549L832 626.5V763.5";
    const String pathGridToInverter = "M518.5 499L224 377.5";
    const String pathInverterToBat = "M516 588L467.5 568.5V702L489.5 711";

    final Color darkLineColor = const Color(0xFF334155).withValues(alpha: 0.65);

    final List<EnergyPathConfig> pathConfigs = [
      EnergyPathConfig(
        svgPath: pathPvToInverter,
        baseLineColor: darkLineColor,
        particleColor: const Color(0xFFF59E0B),
        isReverse: true,
        isActive: dcAcPowerDirection != 0,
      ),
      EnergyPathConfig(
        svgPath: pathGridToInverter,
        baseLineColor: darkLineColor,
        particleColor: const Color(0xFF38BDF8),
        isReverse: linePowerDirection == 1,
        isActive: linePowerDirection != 0,
      ),
      EnergyPathConfig(
        svgPath: pathInverterToLoad,
        baseLineColor: darkLineColor,
        particleColor: const Color(0xFF2DD4BF),
        isReverse: false,
        isActive: loadPower > 0.01,
      ),
      EnergyPathConfig(
        svgPath: pathInverterToBat,
        baseLineColor: darkLineColor,
        particleColor: const Color(0xFF10B981),
        isReverse: batteryPowerDirection == 2,
        isActive: batteryPowerDirection != 0,
      ),
    ];

    const double designWidth = 2063.0;
    const double designHeight = 1344.0;
    final double scaleX = size.width / designWidth;
    final double scaleY = size.height / designHeight;

    final Matrix4 scaleMatrix = Matrix4.identity()..scaleByVector3(vector_math.Vector3(scaleX, scaleY, 1.0));

    for (var config in pathConfigs) {
      Path originalPath = parseSvgPathData(config.svgPath);
      Path finalPath = originalPath.transform(scaleMatrix.storage);
      final Path shadowPath = finalPath.shift(const Offset(5.5, 2.0));

      // 🎯 需求 2 解決：使用多層線條疊加模擬網頁版發光陰影
      if (!kIsWeb) {
        // 手機版：維持原本的高效硬體模糊濾鏡
        final shadowPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawPath(shadowPath, shadowPaint);
      } else {
        // 網頁版：使用 3 層遞減透明度與遞增寬度的線條疊加
        for (double w = 7.0; w >= 3.0; w -= 2.0) {
          final webShadow = Paint()
            ..color = Colors.black.withValues(alpha: 0.08)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round;
          canvas.drawPath(shadowPath, webShadow);
        }
      }

      final baseLinePaint = Paint()
        ..color = config.baseLineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(finalPath, baseLinePaint);

      if (!config.isActive) continue;

      PathMetrics pathMetrics = finalPath.computeMetrics();
      for (PathMetric pathMetric in pathMetrics) {
        double totalLength = pathMetric.length;
        if (totalLength <= 0) continue;

        const double beamLength = 85.0;
        double curP = config.isReverse ? (1.0 - progress) : progress;
        double headDist = (curP * totalLength) % totalLength;

        double normalizedPos = headDist / totalLength;
        double fadeAlpha = 1.0;
        const double fadeZone = 0.10; 

        if (normalizedPos < fadeZone) {
          fadeAlpha = normalizedPos / fadeZone; 
        } else if (normalizedPos > 1.0 - fadeZone) {
          fadeAlpha = (1.0 - normalizedPos) / fadeZone; 
        }

        double startDist = headDist - beamLength;
        if (startDist >= 0) {
          Path segment = pathMetric.extractPath(startDist, headDist);
          _drawGlowBeam(canvas, segment, config.particleColor, fadeAlpha); 
        } else {
          Path headSegment = pathMetric.extractPath(0, headDist);
          Path tailSegment = pathMetric.extractPath(totalLength + startDist, totalLength);
          _drawGlowBeam(canvas, headSegment, config.particleColor, fadeAlpha);
          _drawGlowBeam(canvas, tailSegment, config.particleColor, fadeAlpha);
        }

        Tangent? headTangent = pathMetric.getTangentForOffset(headDist);
        if (headTangent != null) {
          Offset headPos = headTangent.position;

          Paint headGlow = Paint()
            ..color = config.particleColor.withValues(alpha: 0.85 * fadeAlpha);

          if (!kIsWeb) {
            headGlow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
          }

          canvas.drawCircle(headPos, 6.0, headGlow);

          Paint headCore = Paint()..color = Colors.white.withValues(alpha: fadeAlpha);
          canvas.drawCircle(headPos, 2.2, headCore);
        }
      }
    }
  }

  void _drawGlowBeam(Canvas canvas, Path path, Color color, double fadeAlpha) {
    // 🎯 核心修改：判斷是否為網頁環境
    if (!kIsWeb) {
      // 手機版：維持原本具有透明度光暈效果的筆刷
      Paint blurGlowPaint = Paint()
        ..color = color.withValues(alpha: 0.45 * fadeAlpha) 
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, blurGlowPaint);
    }

      // 核心光束 (Core Beam) 不受影響，網頁版只畫這個
      Paint coreBeamPaint = Paint()
        ..color = color.withValues(alpha: 1.0 * fadeAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, coreBeamPaint);
  }

  @override
  bool shouldRepaint(covariant EnergyFlowPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.dcAcPowerDirection != dcAcPowerDirection ||
      oldDelegate.linePowerDirection != linePowerDirection ||
      oldDelegate.batteryPowerDirection != batteryPowerDirection ||
      oldDelegate.loadPower != loadPower;
}

class DualAxisPowerChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> historyTest;
  final List<Map<String, dynamic>> historyInvPs;
  final String chartMode;
  final Offset? touchPosition;
  final double? maxY;
  
  final String tariffMode;      
  final DateTime selectedDate;  

  DualAxisPowerChartPainter({
    required this.historyTest,
    required this.historyInvPs,
    required this.chartMode,
    required this.touchPosition,
    this.maxY,
    required this.tariffMode,
    required this.selectedDate,
  });

  double _calcX(String rawTime, double leftMargin, double chartWidth) {
    if (rawTime.length < 19) return leftMargin;
    int hour = int.tryParse(rawTime.substring(11, 13)) ?? 0;
    int minute = int.tryParse(rawTime.substring(14, 16)) ?? 0;
    int second = int.tryParse(rawTime.substring(17, 19)) ?? 0;
    double fraction = (hour * 3600 + minute * 60 + second) / 86400.0;
    return leftMargin + chartWidth * fraction;
  }

  Color _getTouBackgroundColor(int hour) {
    if (tariffMode == '一般累進表燈(住商)') return Colors.transparent;

    final int month = selectedDate.month;
    final int weekday = selectedDate.weekday; 
    final bool isSummer = (month >= 6 && month <= 9);

    final Color peakColor = Colors.redAccent.withValues(alpha: 0.08);
    final Color midPeakColor = Colors.orangeAccent.withValues(alpha: 0.08);
    final Color offPeakColor = Colors.teal.withValues(alpha: 0.08);

    if (tariffMode == '簡易型(二段式)') {
      if (isSummer) {
        if (weekday <= 5 && hour >= 9) return peakColor;
        return offPeakColor;
      } else {
        if (weekday <= 5 && ((hour >= 6 && hour < 11) || (hour >= 14))) return peakColor;
        return offPeakColor;
      }
    } else if (tariffMode == '簡易型(三段式)') {
      if (isSummer) {
        if (weekday <= 5) {
          if (hour >= 16) return peakColor;
          if (hour >= 9) return midPeakColor;
          return offPeakColor;
        }
        return offPeakColor;
      } else {
        if (weekday <= 5 && ((hour >= 6 && hour < 11) || (hour >= 14))) return midPeakColor;
        return offPeakColor;
      }
    } else if (tariffMode == '標準型(二段式)') {
      if (isSummer) {
        if (weekday <= 5 && hour >= 9) return peakColor;
        if (weekday == 6 && hour >= 9) return midPeakColor;
        return offPeakColor;
      } else {
        if (weekday <= 5 && ((hour >= 6 && hour < 11) || (hour >= 14))) return peakColor;
        if (weekday == 6 && ((hour >= 6 && hour < 11) || (hour >= 14))) return midPeakColor;
        return offPeakColor;
      }
    } else if (tariffMode == '標準型(三段式)') {
      if (isSummer) {
        if (weekday <= 5) {
          if (hour >= 16) return peakColor;
          if (hour >= 9) return midPeakColor;
          return offPeakColor;
        }
        if (weekday == 6 && hour >= 9) return midPeakColor;
        return offPeakColor;
      } else {
        if (weekday <= 5 && ((hour >= 6 && hour < 11) || (hour >= 14))) return midPeakColor;
        if (weekday == 6 && ((hour >= 6 && hour < 11) || (hour >= 14))) return midPeakColor;
        return offPeakColor;
      }
    }
    return Colors.transparent;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double leftMargin = 30.0;
    final double rightMargin = 20.0;
    final double topMargin = 20.0;
    final double bottomMargin = 30.0;

    final double chartWidth = size.width - leftMargin - rightMargin;
    final double chartHeight = size.height - topMargin - bottomMargin;
    final double midY = topMargin + (chartHeight / 2.0);

    double computedMaxKw = maxY ?? 12.0; 
    double computedMaxTemp = 40.0;
    double computedMinTemp = 0.0;
    
    if (chartMode == 'overview') {
      double maxW = 0.0;
      double maxTemp = -100.0; 
      double minTemp = 100.0;  

      for (var item in historyInvPs) {
        double load = (double.tryParse((item['ac_out_total_active_power'] ?? 0).toString()) ?? 0.0).abs();
        double s1 = (double.tryParse((item['solar1_input_power'] ?? 0).toString()) ?? 0.0).abs();
        double s2 = (double.tryParse((item['solar2_input_power'] ?? 0).toString()) ?? 0.0).abs();
        double acIn = (double.tryParse((item['ac_in_total_active_power'] ?? 0).toString()) ?? 0.0).abs();
        
        if (load > maxW) maxW = load;
        if ((s1 + s2) > maxW) maxW = (s1 + s2);
        if (acIn > maxW) maxW = acIn;
      }
      for (var item in historyTest) {
        double batV = (double.tryParse((item['battery_voltage'] ?? 0).toString()) ?? 0.0).abs();
        double batI = (double.tryParse((item['battery_current'] ?? 0).toString()) ?? 0.0).abs();
        if ((batV * batI) > maxW) maxW = batV * batI;

        double temp = double.tryParse((item['inner_temp'] ?? 0).toString()) ?? 0.0;
        if (temp > maxTemp) maxTemp = temp;
        if (temp < minTemp) minTemp = temp;
      }
      
      double maxKwVal = maxW / 1000.0;
      
      // 🎯 動態邊界邏輯：
      // 如果最大值很小 (低於 1kW)，就以 0.5kW 為一個級距來抓取上限，避免圖表太空曠
      // 如果最大值超過 1kW，則直接無條件進位到下一個整數 kW (例如 2.4kW -> 3.0kW)
      if (maxKwVal <= 0.0) {
        computedMaxKw = 1.0; // 預設最小邊界
      } else if (maxKwVal < 1.0) {
        computedMaxKw = (maxKwVal * 2).ceil() / 2.0; 
      } else {
        computedMaxKw = maxKwVal.ceilToDouble(); 
      }

      if (maxTemp != -100.0 && minTemp != 100.0) {
        computedMaxTemp = ((maxTemp / 10.0).ceil() * 10.0).clamp(-30.0, 100.0);
        computedMinTemp = ((minTemp / 10.0).floor() * 10.0).clamp(-30.0, 100.0);
        
        if (computedMaxTemp == computedMinTemp) {
          computedMaxTemp = (computedMaxTemp + 10.0).clamp(-30.0, 100.0);
          computedMinTemp = (computedMinTemp - 10.0).clamp(-30.0, 100.0);
        }
      }

    } else if (chartMode == 'home' || chartMode == 'grid') {
      double maxW = 0.0;
      for (var item in historyInvPs) {
        double power = (double.tryParse((item[chartMode == 'home' ? 'ac_out_total_active_power' : 'ac_in_total_active_power'] ?? 0).toString()) ?? 0.0).abs();
        if (power > maxW) maxW = power;
      }
      double maxKwVal = maxW / 1000.0;
      computedMaxKw = maxKwVal <= 0 ? 15.0 : (maxKwVal.ceilToDouble() + 2.0).clamp(0.0, 15.0);
    }

    if (tariffMode != '一般累進表燈(住商)') {
      for (int h = 0; h < 24; h++) {
        Color bgColor = _getTouBackgroundColor(h);
        if (bgColor != Colors.transparent) {
          double startX = leftMargin + chartWidth * (h / 24.0);
          double endX = leftMargin + chartWidth * ((h + 1) / 24.0);
          Rect rect = Rect.fromLTRB(startX, topMargin, endX, topMargin + chartHeight);
          canvas.drawRect(rect, Paint()..color = bgColor);
        }
      }
    }

    Paint defaultGridPaint = Paint()..color = Colors.grey.withValues(alpha: 0.15)..strokeWidth = 1.0;
    Paint zeroGridPaint = Paint()..color = Colors.grey.withValues(alpha: 0.45)..strokeWidth = 1.2;

    if (chartMode == 'battery') {
      for (int i = 0; i <= 4; i++) {
        double y = topMargin + (chartHeight / 4.0) * i;
        Paint currentPaint = (i == 2) ? zeroGridPaint : defaultGridPaint; 
        canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), currentPaint);
        _drawText(canvas, '${100 - i * 25}', Offset(5, y - 6), Colors.black38, 9);
        _drawText(canvas, '${100 - i * 50}', Offset(size.width - rightMargin + 5, y - 6), Colors.black38, 9);
      }
      _drawText(canvas, '%', Offset(10, 0), Colors.black38, 9);
      _drawText(canvas, 'A', Offset(size.width - rightMargin + 10, 0), Colors.black38, 9);
      
    } else if (chartMode == 'overview') {
      for (int i = 0; i <= 4; i++) {
        double y = topMargin + (chartHeight / 4.0) * i;
        double val = computedMaxKw - i * (computedMaxKw / 2.0); 
        
        Paint currentPaint = (val.abs() < 0.01) ? zeroGridPaint : defaultGridPaint; 
        canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), currentPaint);
        
        String label = val.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
        _drawText(canvas, label, Offset(5, y - 6), Colors.black38, 9);

        double tempVal = computedMaxTemp - i * ((computedMaxTemp - computedMinTemp) / 4.0);
        _drawText(canvas, '${tempVal.toInt()}', Offset(size.width - rightMargin + 5, y - 6), Colors.black38, 9);
      }
      _drawText(canvas, 'kW', Offset(10, 0), Colors.black38, 9);
      _drawText(canvas, '°C', Offset(size.width - rightMargin + 10, 0), Colors.black38, 9); 
      
    } else if (chartMode == 'grid' || chartMode == 'home') {
      for (int i = 0; i <= 5; i++) {
        double y = topMargin + (chartHeight / 5.0) * i;
        Paint currentPaint = (i == 5) ? zeroGridPaint : defaultGridPaint; 
        canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), currentPaint);
        
        double ratio = (5 - i) / 5.0;
        _drawText(canvas, '${(240 * ratio).toInt()}', Offset(5, y - 6), Colors.black38, 9);
        
        double kwVal = computedMaxKw * ratio;
        String label = kwVal.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
        _drawText(canvas, label, Offset(size.width - rightMargin + 5, y - 6), Colors.black38, 9);
      }
      _drawText(canvas, 'V', Offset(10, 0), Colors.black38, 9);
      _drawText(canvas, 'kW', Offset(size.width - rightMargin + 10, 0), Colors.black38, 9);

    } else {
      for (int i = 0; i <= 5; i++) {
        double y = topMargin + (chartHeight / 5.0) * i;
        Paint currentPaint = (i == 5) ? zeroGridPaint : defaultGridPaint;
        canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), currentPaint);
        double ratio = (5 - i) / 5.0;
        
        if (chartMode == 'solar') {
          double maxLeft = maxY ?? 6000.0;
          _drawText(canvas, '${(maxLeft * ratio).toInt()}', Offset(5, y - 6), Colors.black38, 9);
        } 
      }
      if (chartMode == 'solar') {
        _drawText(canvas, 'W', Offset(10, 0), Colors.black38, 9);
      }
    }

    List<String> timeLabels = ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '24:00'];
    for (int i = 0; i < timeLabels.length; i++) {
      double x = leftMargin + (chartWidth / (timeLabels.length - 1)) * i;
      _drawText(canvas, timeLabels[i], Offset(x - 14, topMargin + chartHeight + 6), Colors.black38, 9);
    }

    List<Offset> line1Points = [];
    List<Offset> line2Points = [];
    List<Offset> line3Points = [];
    List<Offset> line4Points = [];
    List<Offset> line5Points = [];

    double clampY(double y) => y.clamp(topMargin, topMargin + chartHeight);

    for (var item in historyInvPs) {
      double x = _calcX(item['created_at']?.toString() ?? '', leftMargin, chartWidth);
      if (chartMode == 'overview') {
        double load = double.tryParse((item['ac_out_total_active_power'] ?? 0).toString()) ?? 0.0;
        double s1 = double.tryParse((item['solar1_input_power'] ?? 0).toString()) ?? 0.0;
        double s2 = double.tryParse((item['solar2_input_power'] ?? 0).toString()) ?? 0.0;
        double acIn = double.tryParse((item['ac_in_total_active_power'] ?? 0).toString()) ?? 0.0;
        
        double maxKw = computedMaxKw; 
        
        line1Points.add(Offset(x, clampY(midY - ((load / 1000.0) / maxKw) * (chartHeight / 2.0))));
        line2Points.add(Offset(x, clampY(midY - (((s1 + s2) / 1000.0) / maxKw) * (chartHeight / 2.0))));
        line3Points.add(Offset(x, clampY(midY - ((acIn / 1000.0) / maxKw) * (chartHeight / 2.0))));

      } else if (chartMode == 'home') {
        double loadW = double.tryParse((item['ac_out_total_active_power'] ?? 0).toString()) ?? 0.0;
        line3Points.add(Offset(x, clampY(topMargin + chartHeight - ((loadW / 1000.0) / computedMaxKw) * chartHeight)));
        
      } else if (chartMode == 'solar') {
        double s1 = double.tryParse((item['solar1_input_power'] ?? 0).toString()) ?? 0.0;
        double s2 = double.tryParse((item['solar2_input_power'] ?? 0).toString()) ?? 0.0;
        double maxLeft = maxY ?? 6000.0;
        line1Points.add(Offset(x, topMargin + chartHeight - (s1 / maxLeft) * chartHeight));
        line2Points.add(Offset(x, topMargin + chartHeight - (s2 / maxLeft) * chartHeight));
        
      } else if (chartMode == 'grid') {
        double acInW = double.tryParse((item['ac_in_total_active_power'] ?? 0).toString()) ?? 0.0;
        line3Points.add(Offset(x, clampY(topMargin + chartHeight - ((acInW / 1000.0) / computedMaxKw) * chartHeight)));
      }
    }

    for (var item in historyTest) {
      double x = _calcX(item['created_at']?.toString() ?? '', leftMargin, chartWidth);
      if (chartMode == 'battery') {
        double cap = double.tryParse((item['battery_capacity'] ?? 0).toString()) ?? 0.0;
        double batI = double.tryParse((item['battery_current'] ?? 0).toString()) ?? 0.0;
        line1Points.add(Offset(x, topMargin + chartHeight - (cap / 100.0) * chartHeight));
        line2Points.add(Offset(x, clampY(midY - (batI / 100.0) * (chartHeight / 2.0))));
      } else if (chartMode == 'home') {
        double vR = double.tryParse((item['ac_out_v_r'] ?? 0).toString()) ?? 0.0;
        double vS = double.tryParse((item['ac_out_v_s'] ?? 0).toString()) ?? 0.0;
        line1Points.add(Offset(x, topMargin + chartHeight - (vR / 240.0) * chartHeight));
        line2Points.add(Offset(x, topMargin + chartHeight - (vS / 240.0) * chartHeight));
      } else if (chartMode == 'grid') {
        double vR = double.tryParse((item['ac_in_v_r'] ?? 0).toString()) ?? 0.0;
        double vS = double.tryParse((item['ac_in_v_s'] ?? 0).toString()) ?? 0.0;
        line1Points.add(Offset(x, topMargin + chartHeight - (vR / 240.0) * chartHeight));
        line2Points.add(Offset(x, topMargin + chartHeight - (vS / 240.0) * chartHeight));
      } else if (chartMode == 'overview') {
        double batV = double.tryParse((item['battery_voltage'] ?? 0).toString()) ?? 0.0;
        double batI = double.tryParse((item['battery_current'] ?? 0).toString()) ?? 0.0;
        double batP = batV * batI;
        double maxKw = computedMaxKw;

        line4Points.add(Offset(x, clampY(midY - ((batP / 1000.0) / maxKw) * (chartHeight / 2.0))));
        
        double temp = double.tryParse((item['inner_temp'] ?? 0).toString()) ?? 0.0;
        double tempRatio = (temp - computedMinTemp) / (computedMaxTemp - computedMinTemp);
        line5Points.add(Offset(x, clampY(topMargin + chartHeight - (tempRatio * chartHeight))));
      }
    }

    double bottomY = topMargin + chartHeight;

    if (chartMode == 'battery') {
      _drawSmoothCurve(canvas, line1Points, const Color(0xFF0D9488), bottomY);
      _drawSmoothCurve(canvas, line2Points, const Color(0xFF7C3AED), midY);
      
    } else if (chartMode == 'grid') {
      _drawSmoothCurve(canvas, line1Points, const Color(0xFF9E9E9E), bottomY); 
      _drawSmoothCurve(canvas, line2Points, const Color(0xFFE0E0E0), bottomY); 
      _drawSmoothCurve(canvas, line3Points, const Color(0xFFFF5252), bottomY); 
      
    } else if (chartMode == 'home') {
      _drawSmoothCurve(canvas, line1Points, const Color(0xFFC4A484), bottomY); 
      _drawSmoothCurve(canvas, line2Points, const Color(0xFFE5D3B3), bottomY); 
      _drawSmoothCurve(canvas, line3Points, const Color(0xFF2563EB), bottomY); 
      
    } else if (chartMode == 'solar') {
      _drawSmoothCurve(canvas, line1Points, const Color(0xFFF97316), bottomY);
      _drawSmoothCurve(canvas, line2Points, const Color(0xFF2563EB), bottomY);
    } else if (chartMode == 'overview') {
      _drawSmoothCurve(canvas, line1Points, const Color(0xFF3B82F6), midY); 
      _drawSmoothCurve(canvas, line2Points, const Color(0xFFF59E0B), midY); 
      _drawSmoothCurve(canvas, line3Points, const Color(0xFFFF5252), midY); 
      _drawSmoothCurve(canvas, line4Points, const Color(0xFF10B981), midY); 
      
      _drawSmoothCurve(canvas, line5Points, const Color(0xFF424242), bottomY, isDashed: true, showFill: false); 
    }

    if (touchPosition != null) {
      double touchX = touchPosition!.dx;
      if (touchX >= leftMargin && touchX <= size.width - rightMargin) {
        double minDistance = double.infinity;
        int closestIndex = -1;
        
        for (int i = 0; i < line1Points.length; i++) {
          double dist = (line1Points[i].dx - touchX).abs();
          if (dist < minDistance) { minDistance = dist; closestIndex = i; }
        }

        if (closestIndex != -1) {
          double targetX = line1Points[closestIndex].dx;
          canvas.drawLine(Offset(targetX, topMargin), Offset(targetX, topMargin + chartHeight), Paint()..color = Colors.teal.withValues(alpha: 0.7)..strokeWidth = 1.2);

          Map<String, dynamic> itemData;
          if (chartMode == 'overview' || chartMode == 'solar') {
            int idx = closestIndex < historyInvPs.length ? closestIndex : historyInvPs.length - 1;
            itemData = historyInvPs.isNotEmpty ? historyInvPs[idx] : {};
          } else {
            int idx = closestIndex < historyTest.length ? closestIndex : historyTest.length - 1;
            itemData = historyTest.isNotEmpty ? historyTest[idx] : {};
          }
          
          String rawTime = itemData['created_at']?.toString() ?? '';
          String timeStr = rawTime.length >= 19 ? rawTime.substring(11, 19) : '00:00:00';

          double tooltipW = 150.0;
          double tooltipH = chartMode == 'overview' ? 122.0 : (chartMode == 'solar' ? 65.0 : 85.0); 
          double tooltipX = (targetX + tooltipW + 10 > size.width) ? targetX - tooltipW - 10 : targetX + 10;
          double tooltipY = topMargin + 10;
          RRect tooltipRRect = RRect.fromRectAndRadius(Rect.fromLTWH(tooltipX, tooltipY, tooltipW, tooltipH), const Radius.circular(8));
          
          canvas.drawRRect(tooltipRRect, Paint()..color = Colors.white.withValues(alpha: 0.90));
          canvas.drawRRect(tooltipRRect, Paint()..color = Colors.grey.withValues(alpha: 0.2)..style = PaintingStyle.stroke);

          _drawText(canvas, '🕒 $timeStr', Offset(tooltipX + 10, tooltipY + 8), Colors.black87, 10);

          if (chartMode == 'battery') {
            _drawText(canvas, '電池容量: ${itemData['battery_capacity'] ?? '--'} %', Offset(tooltipX + 10, tooltipY + 28), Colors.teal.shade700, 10);
            _drawText(canvas, '電池電流: ${itemData['battery_current'] ?? '--'} A', Offset(tooltipX + 10, tooltipY + 48), Colors.purple.shade700, 10);
            
          } else if (chartMode == 'home') {
            _drawText(canvas, 'L1輸出電壓: ${itemData['ac_out_v_r'] ?? '--'} V', Offset(tooltipX + 10, tooltipY + 26), const Color(0xFFC4A484), 10);
            _drawText(canvas, 'L2輸出電壓: ${itemData['ac_out_v_s'] ?? '--'} V', Offset(tooltipX + 10, tooltipY + 42), const Color(0xFFE5D3B3), 10);
            
            String outPower = '--';
            if (historyInvPs.isNotEmpty) {
              int idx = closestIndex < historyInvPs.length ? closestIndex : historyInvPs.length - 1;
              outPower = historyInvPs[idx]['ac_out_total_active_power']?.toString() ?? '--';
            }
            _drawText(canvas, '輸出功率: $outPower W', Offset(tooltipX + 10, tooltipY + 58), const Color(0xFF2563EB), 10);
            
          } else if (chartMode == 'grid') {
            _drawText(canvas, 'L1輸入電壓: ${itemData['ac_in_v_r'] ?? '--'} V', Offset(tooltipX + 10, tooltipY + 26), const Color(0xFF9E9E9E), 10);
            _drawText(canvas, 'L2輸入電壓: ${itemData['ac_in_v_s'] ?? '--'} V', Offset(tooltipX + 10, tooltipY + 42), const Color(0xFFE0E0E0), 10);
            
            String inPower = '--';
            if (historyInvPs.isNotEmpty) {
              int idx = closestIndex < historyInvPs.length ? closestIndex : historyInvPs.length - 1;
              inPower = historyInvPs[idx]['ac_in_total_active_power']?.toString() ?? '--';
            }
            _drawText(canvas, '輸入功率: $inPower W', Offset(tooltipX + 10, tooltipY + 58), const Color(0xFFFF5252), 10);
            
          } else if (chartMode == 'solar') {
            _drawText(canvas, 'MPPT 1: ${itemData['solar1_input_power'] ?? '--'} W', Offset(tooltipX + 10, tooltipY + 26), Colors.orange.shade800, 10);
            _drawText(canvas, 'MPPT 2: ${itemData['solar2_input_power'] ?? '--'} W', Offset(tooltipX + 10, tooltipY + 42), Colors.blue.shade800, 10);
            
          } else if (chartMode == 'overview') {
            double load = double.tryParse((itemData['ac_out_total_active_power'] ?? 0).toString()) ?? 0.0;
            double s1 = double.tryParse((itemData['solar1_input_power'] ?? 0).toString()) ?? 0.0;
            double s2 = double.tryParse((itemData['solar2_input_power'] ?? 0).toString()) ?? 0.0;
            
            double acIn = 0.0;
            if (historyInvPs.isNotEmpty) {
              int idx = closestIndex < historyInvPs.length ? closestIndex : historyInvPs.length - 1;
              acIn = double.tryParse((historyInvPs[idx]['ac_in_total_active_power'] ?? 0).toString()) ?? 0.0;
            }
            
            double batP = 0.0;
            double tempVal = 0.0; 
            if (historyTest.isNotEmpty && line4Points.isNotEmpty) {
              int bestTestIdx = 0;
              double minXDiff = double.infinity;
              for (int i = 0; i < line4Points.length; i++) {
                double diff = (line4Points[i].dx - targetX).abs();
                if (diff < minXDiff) { minXDiff = diff; bestTestIdx = i; }
              }
              double v = double.tryParse((historyTest[bestTestIdx]['battery_voltage'] ?? 0).toString()) ?? 0.0;
              double current = double.tryParse((historyTest[bestTestIdx]['battery_current'] ?? 0).toString()) ?? 0.0;
              batP = v * current;
              tempVal = double.tryParse((historyTest[bestTestIdx]['inner_temp'] ?? 0).toString()) ?? 0.0;
            }

            _drawText(canvas, '電網: ${acIn.toStringAsFixed(0)} W', Offset(tooltipX + 10, tooltipY + 26), const Color(0xFFFF5252), 10);
            _drawText(canvas, '負載: ${load.toStringAsFixed(0)} W', Offset(tooltipX + 10, tooltipY + 42), const Color(0xFF3B82F6), 10);
            _drawText(canvas, '太陽能: ${(s1+s2).toStringAsFixed(0)} W', Offset(tooltipX + 10, tooltipY + 58), const Color(0xFFF59E0B), 10);
            _drawText(canvas, '電池: ${batP.toStringAsFixed(0)} W', Offset(tooltipX + 10, tooltipY + 74), const Color(0xFF10B981), 10);
            _drawText(canvas, '內部溫度: ${tempVal.toStringAsFixed(1)} °C', Offset(tooltipX + 10, tooltipY + 90), const Color(0xFF424242), 10);
          }
        }
      }
    }
  }

  void _drawSmoothCurve(Canvas canvas, List<Offset> points, Color color, double baselineY, {bool isDashed = false, bool showFill = true}) {
    if (points.isEmpty) return;

    // 🎯 徹底移除「移動平均 (Moving Average)」演算法
    // 直接使用原始的 points 進行精準連線，確保任何瞬間的尖峰(如 12kW)都能 100% 頂到對應的刻度線
    Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    if (showFill) {
      Path fillPath = Path.from(path);
      fillPath.lineTo(points.last.dx, baselineY);
      fillPath.lineTo(points.first.dx, baselineY);
      fillPath.close();

      final Rect bounds = fillPath.getBounds();
      Paint fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.35), 
            color.withValues(alpha: 0.05), 
          ],
          stops: const [0.0, 1.0],
        ).createShader(bounds);
        
      canvas.drawPath(fillPath, fillPaint);
    }

    Paint strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round; // 保留圓角接合，讓直線轉折處不刺眼
    
    if (isDashed) {
      canvas.drawPath(dashPath(path, dashArray: CircularIntervalList<double>([4.0, 4.0])), strokePaint);
    } else {
      canvas.drawPath(path, strokePaint);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double fontSize) {
    TextPainter tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr);
    tp.layout(); tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant DualAxisPowerChartPainter oldDelegate) => true;
}

class SavingsBarChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> savingsData;
  final Offset? touchPosition;
  final double maxSavings;

  SavingsBarChartPainter({
    required this.savingsData,
    required this.touchPosition,
    required this.maxSavings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double leftMargin = 30.0;
    final double rightMargin = 20.0;
    final double topMargin = 20.0;
    final double bottomMargin = 25.0;

    final double chartWidth = size.width - leftMargin - rightMargin;
    final double chartHeight = size.height - topMargin - bottomMargin;

    Paint gridPaint = Paint()..color = Colors.grey.withValues(alpha: 0.15)..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      double y = topMargin + (chartHeight / 4.0) * i;
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), gridPaint);
      double val = maxSavings * (4 - i) / 4.0;
      _drawText(canvas, val.toStringAsFixed(1), Offset(0, y - 6), Colors.black38, 9);
    }

    for (int i = 0; i <= 24; i += 4) {
      double x = leftMargin + (chartWidth / 24.0) * i;
      _drawText(canvas, '${i.toString().padLeft(2, '0')}:00', Offset(x - 12, topMargin + chartHeight + 8), Colors.black38, 9);
    }

    double barWidth = (chartWidth / 24.0) * 0.6; 
    
    for (var item in savingsData) {
      int hour = item['hour'];
      double saved = item['saved'];
      String period = item['period'];

      double x = leftMargin + (chartWidth / 24.0) * hour + (chartWidth / 24.0) / 2.0;
      double barH = (saved / maxSavings) * chartHeight;
      if (barH < 2 && saved > 0) barH = 2.0;

      Color barColor = Colors.teal.shade300;
      if (period == '尖峰') barColor = Colors.redAccent.shade200;
      if (period == '半尖峰') barColor = Colors.orangeAccent;

      RRect barRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, topMargin + chartHeight - barH / 2.0), width: barWidth, height: barH),
        const Radius.circular(3)
      );
      canvas.drawRRect(barRect, Paint()..color = barColor);
    }

    if (touchPosition != null) {
      double touchX = touchPosition!.dx;
      if (touchX >= leftMargin && touchX <= size.width - rightMargin) {
        int hoveredHour = ((touchX - leftMargin) / (chartWidth / 24.0)).floor();
        hoveredHour = hoveredHour.clamp(0, 23);

        var hoveredItem = savingsData.where((e) => e['hour'] == hoveredHour).toList();
        if (hoveredItem.isNotEmpty) {
          var item = hoveredItem.first;
          double targetX = leftMargin + (chartWidth / 24.0) * hoveredHour + (chartWidth / 24.0) / 2.0;
          
          canvas.drawLine(Offset(targetX, topMargin), Offset(targetX, topMargin + chartHeight), Paint()..color = Colors.teal.withValues(alpha: 0.15)..strokeWidth = barWidth * 1.5);

          double tooltipW = 110.0;
          double tooltipH = 50.0;
          double tooltipX = (targetX + tooltipW + 10 > size.width) ? targetX - tooltipW - 10 : targetX + 10;
          double tooltipY = topMargin + 10;
          
          RRect tooltipRRect = RRect.fromRectAndRadius(Rect.fromLTWH(tooltipX, tooltipY, tooltipW, tooltipH), const Radius.circular(8));
          canvas.drawRRect(tooltipRRect, Paint()..color = Colors.white.withValues(alpha: 0.95));
          canvas.drawRRect(tooltipRRect, Paint()..color = Colors.grey.withValues(alpha: 0.3)..style = PaintingStyle.stroke);

          _drawText(canvas, '${hoveredHour.toString().padLeft(2, '0')}:00 - ${hoveredHour+1}:00', Offset(tooltipX + 10, tooltipY + 8), Colors.black54, 10);
          _drawText(canvas, '收益: NT\$ ${item['saved'].toStringAsFixed(1)}', Offset(tooltipX + 10, tooltipY + 26), Colors.teal.shade700, 11);
        }
      }
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double fontSize) {
    TextPainter tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr);
    tp.layout(); tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant SavingsBarChartPainter oldDelegate) => true;
}