import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // 🎯 防抖動標記：確保掃描成功後只回傳一次資料
  bool _isScanned = false; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('掃描設備條碼', style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // 讓 body 延伸到 AppBar 後方，達到全螢幕相機效果
      extendBodyBehindAppBar: true, 
      body: Stack(
        children: [
          MobileScanner(
            // 控制器可設定偵測特定的條碼類型，這裡預設全開
            controller: MobileScannerController(
              detectionSpeed: DetectionSpeed.normal,
              facing: CameraFacing.back,
            ),
            onDetect: (BarcodeCapture capture) {
              // 如果已經掃描過了，就忽略後續的影格
              if (_isScanned) return;

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                _isScanned = true; // 鎖定狀態
                
                final String code = barcodes.first.rawValue!;
                // 將掃描到的字串 (code) 裝在 pop 裡帶回上一頁
                Navigator.pop(context, code);
              }
            },
          ),
          // 加上一個簡單的掃描框視覺輔助 (選擇性)
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.tealAccent, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Text(
              '請將條碼對準方框內',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}