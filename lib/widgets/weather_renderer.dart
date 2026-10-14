import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// 🎯 1. 擴充天氣 Enum，加入 snow 與 typhoon
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
    }
  }

  void _updateParticles() {
    final size = MediaQuery.of(context).size;
    if (_particles.isEmpty && size.width > 0) {
      _initParticles(size);
    }

    for (var p in _particles) {
      if (widget.condition == WeatherCondition.typhoon) {
        // 🌪️ 颱風：極端的下墜與強烈的水平風切 (X軸位移係數高達 0.7)
        p.y += p.speed;
        p.x += p.speed * 0.7; 
        if (p.y > size.height + 50 || p.x > size.width + 100) {
          p.y = -50;
          // 為了避免左側無雨，X軸起始點退得非常深
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
        // ❄️ 下雪：緩慢下墜，並加入 Sine 函數製造左右飄移的空氣感
        p.y += p.speed;
        p.x += sin(p.y * 0.015 + p.speed) * 0.8 + 0.2; // 0.2 是微弱的環境風向
        if (p.y > size.height + p.size) {
          p.y = -50;
          p.x = -size.width * 0.2 + _rnd.nextDouble() * (size.width * 1.4);
        }
      } else if (widget.condition == WeatherCondition.cloudy || widget.condition == WeatherCondition.partlyCloudy) {
        p.x += p.speed;
        // 🎯 修正：使用 p.size 取代固定數值 250
        // 確保巨大的透明雲霧「完全」離開畫面右側邊緣後，才從左側邊緣外圍重生
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

    setState(() {}); 
  }

  void _initParticles(Size size) {
    int count = 0;
    if (widget.condition == WeatherCondition.typhoon) {
      count = 250; // 🌪️ 颱風粒子最多，製造暴風雨遮蔽感
    } else if (widget.condition == WeatherCondition.thunderstorm) {
      count = 180; 
    } else if (widget.condition == WeatherCondition.rainy) {
      count = 120;
    } else if (widget.condition == WeatherCondition.snow) {
      count = 80;  // ❄️ 雪花數量中等，太多會顯得凌亂
    } else if (widget.condition == WeatherCondition.cloudy) {
      count = 60; 
    } else if (widget.condition == WeatherCondition.partlyCloudy) {
      count = 10; 
    } else if (widget.condition == WeatherCondition.sunny) {
      count = 15; 
    }

    for (int i = 0; i < count; i++) {
      double speed = 0, pSize = 0, opacity = 0;
      Color pColor = Colors.white;
      double startY = _rnd.nextDouble() * (size.height * 0.8) - size.height * 0.1;

      if (widget.condition == WeatherCondition.typhoon) {
        speed = 22 + _rnd.nextDouble() * 15; // 極速
        pSize = 25 + _rnd.nextDouble() * 40; // 雨滴被強風拉得很長
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
        speed = 1.0 + _rnd.nextDouble() * 2.5; // 極慢的飄落速度
        pSize = 4.0 + _rnd.nextDouble() * 8.0; // 雪花的大小 (半徑)
        opacity = 0.4 + _rnd.nextDouble() * 0.6; // 稍微不透明一點以凸顯雪白
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
        pSize = 180 + _rnd.nextDouble() * 250; 
        opacity = 0.15 + _rnd.nextDouble() * 0.20; 
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          painter: WeatherPainter(
            condition: widget.condition,
            particles: _particles,
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

class WeatherPainter extends CustomPainter {
  final WeatherCondition condition;
  final List<WeatherParticle> particles;
  final double animationValue;

  WeatherPainter({required this.condition, required this.particles, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackgroundGradient(canvas, size);

    if (condition == WeatherCondition.sunny) {
      _drawSunRays(canvas, size, isCloudy: false);
      _drawBokeh(canvas);
    } else if (condition == WeatherCondition.partlyCloudy) {
      _drawSunRays(canvas, size, isCloudy: false); 
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
      _drawLightning(canvas, size); // 颱風天也伴隨微弱環境閃電
      _drawRain(canvas, slant: 0.7); // 極端傾斜的暴雨
    }
  }

  void _drawBackgroundGradient(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    List<Color> colors;

    switch (condition) {
      case WeatherCondition.sunny:
        colors = [const Color(0xFF2E79BA), const Color(0xFF66A6FF)];
        break;
      case WeatherCondition.partlyCloudy:
        colors = [const Color(0xFF4A90E2), const Color(0xFF8BBFFA)];
        break;
      case WeatherCondition.cloudy:
      case WeatherCondition.rainy:
      case WeatherCondition.thunderstorm: 
        colors = [const Color(0xFF8A95A5), const Color(0xFF5D6D7E)];
        break;
      case WeatherCondition.snow:
        // ❄️ 下雪背景：冰冷、透亮的灰藍色
        colors = [const Color(0xFF9EACB9), const Color(0xFFD3DDE6)];
        break;
      case WeatherCondition.typhoon:
        // 🌪️ 颱風背景：極度陰暗詭譎的深青灰色
        colors = [const Color(0xFF141E27), const Color(0xFF2C3E50)];
        break;
    }

    final Paint bgPaint = Paint()
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, colors);
    canvas.drawRect(rect, bgPaint);
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

  void _drawSunRays(Canvas canvas, Size size, {bool isCloudy = false}) {
    final Offset sunPosition = Offset(size.width * 0.75, size.height * 0.12);
    final double pulse = sin(animationValue * pi * 2) * 15;
    final double alphaFactor = isCloudy ? 0.3 : 1.0;

    if (!isCloudy) {
      final Paint flareRingPaint = Paint()
        ..shader = ui.Gradient.radial(
          sunPosition, 280 + pulse * 0.5,
          [Colors.transparent, Colors.transparent, const Color(0x0055AAFF), const Color(0x2255AAFF), const Color(0x3355FFAA), const Color(0x11FF55AA), Colors.transparent],
          [0.0, 0.75, 0.76, 0.82, 0.88, 0.95, 1.0], 
        );
      canvas.drawCircle(sunPosition, 280 + pulse * 0.5, flareRingPaint);
    }

    final Paint outerGlowPaint = Paint()..shader = ui.Gradient.radial(sunPosition, 400 + pulse, [Colors.white.withValues(alpha: 0.5 * alphaFactor), Colors.white.withValues(alpha: 0.0)]);
    canvas.drawCircle(sunPosition, 400 + pulse, outerGlowPaint);

    if (!isCloudy) {
      final Paint spikePaint = Paint()
        ..shader = ui.Gradient.radial(Offset.zero, 280, [Colors.white.withValues(alpha: 0.7), Colors.white.withValues(alpha: 0.0)])
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

    final double innerRadius = isCloudy ? 150 : 140 + pulse * 0.5;
    final Paint innerGlowPaint = Paint()..shader = ui.Gradient.radial(sunPosition, innerRadius, [Colors.white.withValues(alpha: 0.9 * alphaFactor), Colors.white.withValues(alpha: 0.0)]);
    canvas.drawCircle(sunPosition, innerRadius, innerGlowPaint);
    final Paint sunCorePaint = Paint()..color = Colors.white.withValues(alpha: isCloudy ? 0.25 : 1.0)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12); 
    canvas.drawCircle(sunPosition, isCloudy ? 60 : 35, sunCorePaint);
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

  // 🎯 支援傳入斜率(slant)的通用降雨繪製函式
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

  // ❄️ 繪製帶有柔焦效果的雪花
  void _drawSnow(Canvas canvas) {
    for (var p in particles) {
      final Paint snowPaint = Paint()
        ..color = p.color.withValues(alpha: p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5); // 讓雪花邊緣微微模糊，看起來更像棉絮
      canvas.drawCircle(Offset(p.x, p.y), p.size, snowPaint);
    }
  }

  @override
  bool shouldRepaint(WeatherPainter oldDelegate) => true; 
}