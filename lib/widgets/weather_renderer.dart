import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum WeatherCondition { sunny, partlyCloudy, cloudy, rainy, thunderstorm, snow, typhoon }

class RealisticWeatherBg extends StatefulWidget {
  final WeatherCondition condition;
  final Widget child; 

  const RealisticWeatherBg({
    super.key,
    required this.condition,
    required this.child,
  });

  @override
  State<RealisticWeatherBg> createState() => _RealisticWeatherBgState();
}

class _RealisticWeatherBgState extends State<RealisticWeatherBg> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<WeatherParticle> _particles = [];
  final Random _rnd = Random();
  final List<StarParticle> _stars = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..addListener(() {
        _updateParticles();
      })
      ..repeat();
  }

  @override
  void didUpdateWidget(RealisticWeatherBg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.condition != widget.condition) {
      _particles.clear(); 
      _stars.clear(); 
    }
  }

  void _updateParticles() {
    final size = MediaQuery.of(context).size;
    if (_particles.isEmpty && size.width > 0) {
      _initParticles(size);
    }
    
    if (_stars.isEmpty && size.width > 0 && _isNightTime()) {
      _initStars(size);
    }

    for (var p in _particles) {
      if (widget.condition == WeatherCondition.typhoon) {
        p.y += p.speed;
        p.x += p.speed * 0.7; 
        if (p.y > size.height + 50 || p.x > size.width + 100) {
          p.y = -50;
          p.x = -size.width * 1.5 + _rnd.nextDouble() * (size.width * 2.5);
        }
      } else if (widget.condition == WeatherCondition.rainy || widget.condition == WeatherCondition.thunderstorm) {
        p.y += p.speed;
        p.x += p.speed * (widget.condition == WeatherCondition.thunderstorm ? 0.25 : 0.15); 
        if (p.y > size.height + 50) {
          p.y = -50;
          p.x = -size.width * 0.5 + _rnd.nextDouble() * (size.width * 1.5);
        }
      } else if (widget.condition == WeatherCondition.snow) {
        p.y += p.speed;
        p.x += sin(p.y * 0.015 + p.speed) * 0.8 + 0.2; 
        if (p.y > size.height + p.size) {
          p.y = -50;
          p.x = -size.width * 0.2 + _rnd.nextDouble() * (size.width * 1.4);
        }
      } else if (widget.condition == WeatherCondition.cloudy || widget.condition == WeatherCondition.partlyCloudy) {
        p.x += p.speed;
        if (p.x - p.size > size.width) {
          p.x = -p.size;
          p.y = -size.height * 0.1 + _rnd.nextDouble() * (size.height * 1.1);
        }
      } else if (widget.condition == WeatherCondition.sunny) {
        p.y -= p.speed;
        p.x += sin(p.y * 0.02) * 0.3; 
        if (p.y < -p.size) {
          p.y = size.height + p.size;
          p.x = _rnd.nextDouble() * size.width;
        }
      }
    }

    for (var s in _stars) {
      s.phase += s.speed;
    }

    setState(() {}); 
  }

  bool _isNightTime() {
    final hour = DateTime.now().hour;
    return hour >= 18 || hour < 6;
  }

  void _initStars(Size size) {
    for (int i = 0; i < 80; i++) {
      _stars.add(StarParticle(
        x: _rnd.nextDouble() * size.width,
        y: _rnd.nextDouble() * (size.height * 0.6), 
        size: 0.5 + _rnd.nextDouble() * 2.0,
        phase: _rnd.nextDouble() * pi * 2, 
        speed: 0.02 + _rnd.nextDouble() * 0.05,
      ));
    }
  }

  void _initParticles(Size size) {
    int count = 0;
    if (widget.condition == WeatherCondition.typhoon) {
      count = 250; 
    } else if (widget.condition == WeatherCondition.thunderstorm) {
      count = 180; 
    } else if (widget.condition == WeatherCondition.rainy) {
      count = 120;
    } else if (widget.condition == WeatherCondition.snow) {
      count = 80;  
    } else if (widget.condition == WeatherCondition.cloudy) {
      count = 60; 
    } else if (widget.condition == WeatherCondition.partlyCloudy) {
      count = 5; 
    } else if (widget.condition == WeatherCondition.sunny) {
      count = 15; 
    }

    for (int i = 0; i < count; i++) {
      double speed = 0, pSize = 0, opacity = 0;
      Color pColor = Colors.white;
      double startY = _rnd.nextDouble() * (size.height * 0.8) - size.height * 0.1;

      if (widget.condition == WeatherCondition.typhoon) {
        speed = 22 + _rnd.nextDouble() * 15; 
        pSize = 25 + _rnd.nextDouble() * 40; 
        opacity = 0.3 + _rnd.nextDouble() * 0.5;
        pColor = _rnd.nextBool() ? Colors.white : const Color(0xFF9EA9B1);
      } else if (widget.condition == WeatherCondition.thunderstorm) {
        speed = 14 + _rnd.nextDouble() * 10; 
        pSize = 18 + _rnd.nextDouble() * 25; 
        opacity = 0.4 + _rnd.nextDouble() * 0.5;
        pColor = _rnd.nextBool() ? Colors.white : const Color(0xFFB0C4DE);
      } else if (widget.condition == WeatherCondition.rainy) {
        speed = 8 + _rnd.nextDouble() * 8; 
        pSize = 10 + _rnd.nextDouble() * 18; 
        opacity = 0.3 + _rnd.nextDouble() * 0.4;
        pColor = _rnd.nextBool() ? Colors.white : const Color(0xFFD4E6F1);
      } else if (widget.condition == WeatherCondition.snow) {
        speed = 1.0 + _rnd.nextDouble() * 2.5; 
        pSize = 4.0 + _rnd.nextDouble() * 8.0; 
        opacity = 0.4 + _rnd.nextDouble() * 0.6; 
        pColor = Colors.white;
      } else if (widget.condition == WeatherCondition.cloudy) {
        bool isFog = _rnd.nextDouble() > 0.6; 
        if (isFog) {
          speed = 0.3 + _rnd.nextDouble() * 0.5;
          pSize = 200 + _rnd.nextDouble() * 250; 
          opacity = 0.15 + _rnd.nextDouble() * 0.25; 
          pColor = const Color(0xFFCFD8DC); 
          startY = size.height * 0.3 + _rnd.nextDouble() * (size.height * 0.7); 
        } else {
          speed = 0.1 + _rnd.nextDouble() * 0.3;
          pSize = 250 + _rnd.nextDouble() * 350; 
          opacity = 0.4 + _rnd.nextDouble() * 0.4; 
          int colorPicker = _rnd.nextInt(3);
          if (colorPicker == 0) {
            pColor = const Color(0xFF5D6D7E);
          } else if (colorPicker == 1) {
            pColor = const Color(0xFF788D9E);
          } else {
            pColor = const Color(0xFF90A4AE);
          }
          startY = -size.height * 0.1 + _rnd.nextDouble() * (size.height * 0.5); 
        }
      } else if (widget.condition == WeatherCondition.partlyCloudy) {
        speed = 0.4 + _rnd.nextDouble() * 0.8;
        pSize = 150 + _rnd.nextDouble() * 150; 
        opacity = 0.08 + _rnd.nextDouble() * 0.12; 
        pColor = Colors.white;
      } else if (widget.condition == WeatherCondition.sunny) {
        speed = 0.3 + _rnd.nextDouble() * 0.6;
        pSize = 40 + _rnd.nextDouble() * 100;
        opacity = 0.03 + _rnd.nextDouble() * 0.08; 
        pColor = Colors.white;
      }

      double startX = _rnd.nextDouble() * size.width;
      if (widget.condition == WeatherCondition.typhoon) {
        startX = -size.width * 1.5 + _rnd.nextDouble() * (size.width * 2.5);
      } else if (widget.condition == WeatherCondition.rainy || widget.condition == WeatherCondition.thunderstorm) {
        startX = -size.width * 0.5 + _rnd.nextDouble() * (size.width * 1.5);
      } else if (widget.condition == WeatherCondition.snow) {
        startX = -size.width * 0.2 + _rnd.nextDouble() * (size.width * 1.4);
      }

      _particles.add(WeatherParticle(
        x: startX,
        y: startY, 
        speed: speed,
        size: pSize,
        opacity: opacity,
        color: pColor,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 🎯 新增：將判斷天空漸層顏色的邏輯抽離，以便餵給 AnimatedContainer
  List<Color> _getBackgroundColors(WeatherCondition condition, double hour) {
    bool isNight = hour >= 18 || hour < 6;

    if (condition == WeatherCondition.typhoon) {
      return [const Color(0xFF141E27), const Color(0xFF2C3E50)];
    } else if (condition == WeatherCondition.thunderstorm || condition == WeatherCondition.rainy || condition == WeatherCondition.cloudy) {
       return isNight
         ? [const Color(0xFF1C2833), const Color(0xFF34495E)]
         : [const Color(0xFF8A95A5), const Color(0xFF5D6D7E)];
    } else if (condition == WeatherCondition.snow) {
       return isNight
         ? [const Color(0xFF2C3E50), const Color(0xFF7F8C8D)]
         : [const Color(0xFF9EACB9), const Color(0xFFD3DDE6)];
    } else {
      if (hour >= 6 && hour < 9) {
        return [const Color(0xFF56CCF2), const Color(0xFF2F80ED)]; // 清晨
      } else if (hour >= 9 && hour < 17) {
        return [const Color(0xFF2E79BA), const Color(0xFF66A6FF)]; // 延長白天藍天至 17:00
      } else if (hour >= 17 && hour < 18) {
        return [const Color(0xFF203A43), const Color(0xFFFDBB2D)]; // 傍晚夕陽
      } else {
        return [const Color(0xFF0F2027), const Color(0xFF203A43)]; // 夜晚
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentHour = now.hour + now.minute / 60.0;
    final bgColors = _getBackgroundColors(widget.condition, currentHour);

    return Stack(
      children: [
        // 🎯 核心修改：使用 AnimatedContainer 來自動處理天空顏色的漸變轉場！
        AnimatedContainer(
          duration: const Duration(seconds: 3), // 天空顏色改變時，會平滑轉場 3 秒
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: bgColors,
            ),
          ),
        ),
        CustomPaint(
          painter: WeatherPainter(
            condition: widget.condition,
            particles: _particles,
            stars: _stars,
            animationValue: _controller.value,
          ),
          size: Size.infinite,
        ),
        SafeArea(
          child: widget.child,
        ),
      ],
    );
  }
}

class WeatherParticle {
  double x, y, speed, size, opacity;
  Color color;
  WeatherParticle({required this.x, required this.y, required this.speed, required this.size, required this.opacity, required this.color});
}

class StarParticle {
  double x, y, size, phase, speed;
  StarParticle({required this.x, required this.y, required this.size, required this.phase, required this.speed});
}

class WeatherPainter extends CustomPainter {
  final WeatherCondition condition;
  final List<WeatherParticle> particles;
  final List<StarParticle> stars; 
  final double animationValue;

  WeatherPainter({required this.condition, required this.particles, required this.stars, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final double currentHour = now.hour + now.minute / 60.0;
    final bool isNight = currentHour >= 18 || currentHour < 6;

    // 🎯 背景漸層已經由外層的 AnimatedContainer 繪製，此處將背景畫筆移除，保留透明畫布繪製日月星辰

    // 如果是夜晚且天氣晴朗，畫星星
    if (isNight && (condition == WeatherCondition.sunny || condition == WeatherCondition.partlyCloudy)) {
      _drawStars(canvas);
    }

    if (condition == WeatherCondition.sunny || condition == WeatherCondition.partlyCloudy) {
       _drawCelestialBody(canvas, size, currentHour, isCloudy: condition == WeatherCondition.partlyCloudy);
    }

    if (condition == WeatherCondition.sunny) {
      _drawBokeh(canvas);
    } else if (condition == WeatherCondition.partlyCloudy) {
      _drawClouds(canvas); 
    } else if (condition == WeatherCondition.cloudy) {
      _drawClouds(canvas); 
    } else if (condition == WeatherCondition.rainy) {
      _drawRain(canvas, slant: 0.15);
    } else if (condition == WeatherCondition.thunderstorm) {
      _drawLightning(canvas, size);
      _drawRain(canvas, slant: 0.25);
    } else if (condition == WeatherCondition.snow) {
      _drawSnow(canvas);
    } else if (condition == WeatherCondition.typhoon) {
      _drawLightning(canvas, size); 
      _drawRain(canvas, slant: 0.7); 
    }
  }
  
  void _drawStars(Canvas canvas) {
    for (var star in stars) {
      final double opacity = (sin(star.phase) + 1) / 2; 
      final Paint starPaint = Paint()
        ..color = Colors.white.withValues(alpha: opacity * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);
      canvas.drawCircle(Offset(star.x, star.y), star.size, starPaint);
    }
  }

  Offset _calculateCelestialPosition(Size size, double hour) {
    double progress = 0.0;
    
    if (hour >= 6 && hour < 18) {
      progress = (hour - 6) / 12.0; 
    } else {
      double nightHour = hour >= 18 ? (hour - 18) : (hour + 6);
      progress = nightHour / 12.0;
    }

    double x = size.width * (0.1 + progress * 0.8);
    // 🎯 讓拋物線的高低落差更大，0.3 讓太陽在早晚會沉得更低，營造「落日」感
    double yOffset = pow((progress - 0.5) * 2, 2).toDouble(); 
    double y = size.height * 0.1 + (size.height * 0.3 * yOffset);

    return Offset(x, y);
  }

  void _drawCelestialBody(Canvas canvas, Size size, double hour, {bool isCloudy = false}) {
    bool isNight = hour >= 18 || hour < 6;
    
    if (!isNight) {
      final Offset pos = _calculateCelestialPosition(size, hour);
      
      // 1. 太陽整體的漸隱透明度 (日出漸亮，日落漸暗)
      double sunOpacity = 1.0;
      if (hour >= 6 && hour < 7) {
        sunOpacity = hour - 6.0; 
      } else if (hour >= 17 && hour < 18) {
        sunOpacity = 18.0 - hour; 
      }
      
      // 🎯 2. 新增：獨立控制刺眼光芒 (Spikes) 與耀斑 (Flare) 的強度
      // 讓傍晚 (16:00 後) 的光芒提早收斂，呈現夕陽溫和清晰的輪廓
      double rayIntensity = 1.0;
      if (hour >= 16.0 && hour < 18.0) {
        rayIntensity = (18.0 - hour) / 2.0; // 16點~18點，光芒從 100% 降至 0%
      } else if (hour >= 6.0 && hour < 8.0) {
        rayIntensity = (hour - 6.0) / 2.0;  // 06點~08點，光芒從 0% 升至 100%
      }
      
      _drawSunRays(canvas, pos, sunOpacity: sunOpacity, rayIntensity: rayIntensity, isCloudy: isCloudy);
    }
  }

  void _drawLightning(Canvas canvas, Size size) {
    double flashAlpha = 0.0;
    
    if (animationValue > 0.30 && animationValue < 0.35) {
      flashAlpha = sin((animationValue - 0.30) * 20 * pi);
    } 
    else if (animationValue > 0.70 && animationValue < 0.78) {
      flashAlpha = sin((animationValue - 0.70) * 25 * pi);
    }

    if (flashAlpha > 0) {
      final Paint ambientFlash = Paint()
        ..color = Colors.white.withValues(alpha: (flashAlpha * 0.3).clamp(0.0, 1.0));
      canvas.drawRect(Offset.zero & size, ambientFlash);

      final Paint strikeGlow = Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.6, -size.height * 0.1), 
          size.width * 0.8,
          [
            Colors.white.withValues(alpha: (flashAlpha * 0.8).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: 0.0)
          ]
        );
      canvas.drawRect(Offset.zero & size, strikeGlow);
    }
  }

  // 🎯 使用 saveLayer 來完美處理太陽與光暈的漸隱效果，不破壞原有的圖層疊加質感
  // 🎯 接收 rayIntensity 參數，將其套用於光芒層
  void _drawSunRays(Canvas canvas, Offset sunPosition, {required double sunOpacity, required double rayIntensity, bool isCloudy = false}) {
    if (sunOpacity <= 0) return; 

    final double pulse = sin(animationValue * pi * 2) * 15;
    
    final Paint layerPaint = Paint()..color = Colors.white.withValues(alpha: sunOpacity);
    canvas.saveLayer(Rect.fromLTWH(0, 0, 10000, 10000), layerPaint); 

    // 🎯 彩色光圈 (Flare Ring) - 套用 rayIntensity，傍晚時完全消失
    if (!isCloudy && rayIntensity > 0) {
      final Paint flareRingPaint = Paint()
        ..shader = ui.Gradient.radial(
          sunPosition, 280 + pulse * 0.5,
          [
            Colors.transparent, 
            Colors.transparent, 
            const Color(0xFF55AAFF).withValues(alpha: 0.0), 
            const Color(0xFF55AAFF).withValues(alpha: 0.13 * rayIntensity), 
            const Color(0xFF55FFAA).withValues(alpha: 0.20 * rayIntensity), 
            const Color(0xFFFF55AA).withValues(alpha: 0.06 * rayIntensity), 
            Colors.transparent
          ],
          [0.0, 0.75, 0.76, 0.82, 0.88, 0.95, 1.0], 
        );
      canvas.drawCircle(sunPosition, 280 + pulse * 0.5, flareRingPaint);
    }

    // 最外層的大範圍光暈 - 傍晚時稍微變柔和，但不完全消失
    final Paint outerGlowPaint = Paint()..shader = ui.Gradient.radial(
      sunPosition, 400 + pulse, 
      [Colors.white.withValues(alpha: (isCloudy ? 0.15 : 0.5) * (0.4 + 0.6 * rayIntensity)), Colors.white.withValues(alpha: 0.0)]
    );
    canvas.drawCircle(sunPosition, 400 + pulse, outerGlowPaint);

    // 🎯 放射狀多角星芒 (Spikes) - 套用 rayIntensity，傍晚時光芒收斂
    if (rayIntensity > 0) {
      final double spikeAlpha = (isCloudy ? 0.35 : 0.7) * rayIntensity;
      final Paint spikePaint = Paint()
        ..shader = ui.Gradient.radial(Offset.zero, 280, [
          Colors.white.withValues(alpha: spikeAlpha), 
          Colors.white.withValues(alpha: 0.0)
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12); 
      
      canvas.save();
      canvas.translate(sunPosition.dx, sunPosition.dy);
      canvas.rotate(animationValue * pi / 2); 

      for (int i = 0; i < 4; i++) {
        canvas.rotate(pi / 4); 
        double spikeLength = (i % 2 == 0) ? 280.0 + pulse : 160.0 + pulse;
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: spikeLength * 2, height: 16), spikePaint);
      }
      canvas.restore(); 
    }

    // 內層光暈 - 保持不變，維持太陽圓球的體積感
    final double innerRadius = isCloudy ? 150 : 140 + pulse * 0.5;
    final Paint innerGlowPaint = Paint()..shader = ui.Gradient.radial(
      sunPosition, innerRadius, 
      [Colors.white.withValues(alpha: isCloudy ? 0.27 : 0.9), Colors.white.withValues(alpha: 0.0)]
    );
    canvas.drawCircle(sunPosition, innerRadius, innerGlowPaint);
    
    // 太陽本體核心 - 保持不變
    final Paint sunCorePaint = Paint()
      ..color = Colors.white.withValues(alpha: isCloudy ? 0.4 : 1.0)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12); 
    canvas.drawCircle(sunPosition, isCloudy ? 60 : 35, sunCorePaint);

    canvas.restore();
  }

  void _drawBokeh(Canvas canvas) {
    for (var p in particles) {
      final Paint bokehPaint = Paint()..shader = ui.Gradient.radial(Offset(p.x, p.y), p.size, [p.color.withValues(alpha: p.opacity), p.color.withValues(alpha: 0.0)]);
      canvas.drawCircle(Offset(p.x, p.y), p.size, bokehPaint);
    }
  }

  void _drawClouds(Canvas canvas) {
    for (var p in particles) {
      final Paint cloudPaint = Paint()..shader = ui.Gradient.radial(Offset(p.x, p.y), p.size, [p.color.withValues(alpha: p.opacity), p.color.withValues(alpha: 0.0)]);
      canvas.drawCircle(Offset(p.x, p.y), p.size, cloudPaint);
    }
  }

  void _drawRain(Canvas canvas, {required double slant}) {
    for (var p in particles) {
      final Offset start = Offset(p.x, p.y);
      final Offset end = Offset(p.x + p.speed * slant, p.y + p.size * 0.6);
      final Paint rainPaint = Paint()
        ..shader = ui.Gradient.linear(start, end, [p.color.withValues(alpha: 0.0), p.color.withValues(alpha: p.opacity)])
        ..strokeWidth = 1.5 + p.size * 0.05 
        ..strokeCap = StrokeCap.round; 
      canvas.drawLine(start, end, rainPaint);
    }
  }

  void _drawSnow(Canvas canvas) {
    for (var p in particles) {
      final Paint snowPaint = Paint()
        ..color = p.color.withValues(alpha: p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5); 
      canvas.drawCircle(Offset(p.x, p.y), p.size, snowPaint);
    }
  }

  @override
  bool shouldRepaint(WeatherPainter oldDelegate) => true; 
}