import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobileApp;
  final Widget webAdmin;

  const ResponsiveLayout({
    super.key,
    required this.mobileApp,
    required this.webAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 🎯 設定斷點：寬度大於 800 像素時，判定為桌機環境，顯示網頁版後台
        if (constraints.maxWidth > 800) {
          return webAdmin;
        }
        // 否則顯示原本的手機版 APP
        return mobileApp;
      },
    );
  }
}