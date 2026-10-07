import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebSessionTimeoutListener extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final VoidCallback onTimeout;

  const WebSessionTimeoutListener({
    super.key,
    required this.child,
    required this.duration,
    required this.onTimeout,
  });

  @override
  State<WebSessionTimeoutListener> createState() => _WebSessionTimeoutListenerState();
}

class _WebSessionTimeoutListenerState extends State<WebSessionTimeoutListener> {
  Timer? _idleTimer;
  Timer? _warningCountdownTimer;
  bool _isWarningDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _startIdleTimer();
  }

  void _startIdleTimer() {
    // 只有網頁版才啟用閒置偵測
    if (!kIsWeb) return;
    
    // 如果對話框正在顯示，就不要重置 5 分鐘計時器
    if (_isWarningDialogShowing) return;

    _idleTimer?.cancel();
    _warningCountdownTimer?.cancel();
    
    _idleTimer = Timer(widget.duration, _showTimeoutWarningDialog);
  }

  void _handleUserInteraction([_]) {
    _startIdleTimer();
  }

  void _showTimeoutWarningDialog() {
    if (!mounted || _isWarningDialogShowing) return;

    setState(() {
      _isWarningDialogShowing = true;
    });

    int remainingSeconds = 15;
    StateSetter? dialogSetState; // 🎯 用來單獨更新對話框畫面的 StateSetter

    // 🎯 啟動每秒觸發一次的週期性計時器
    _warningCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds > 1) {
        remainingSeconds--;
        // 呼叫對話框的 setState 來更新秒數
        if (dialogSetState != null) {
          dialogSetState!(() {}); 
        }
      } else {
        // 時間到 0 秒，關閉計時器與對話框，並執行登出
        timer.cancel();
        if (mounted && _isWarningDialogShowing) {
          Navigator.of(context).pop(); 
          setState(() {
            _isWarningDialogShowing = false;
          });
          widget.onTimeout(); // 觸發登出
        }
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false, // 禁止點擊對話框外部關閉
      builder: (dialogContext) {
        // 🎯 透過 StatefulBuilder 讓對話框可以獨立刷新畫面
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            dialogSetState = setDialogState;
            
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text('是否繼續使用？', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '您已閒置超過一段時間。\n\n若未進行任何操作，將在 '),
                    // 🎯 將動態秒數標紅加粗
                    TextSpan(
                      text: '$remainingSeconds',
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const TextSpan(text: ' 秒後自動登出確保資訊安全，請問是否繼續使用？'),
                  ],
                ),
                style: const TextStyle(height: 1.5, fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _warningCountdownTimer?.cancel();
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _isWarningDialogShowing = false;
                    });
                    widget.onTimeout(); // 立即登出
                  },
                  child: const Text('立即登出', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    _warningCountdownTimer?.cancel();
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _isWarningDialogShowing = false;
                    });
                    _startIdleTimer(); // 重新計算 5 分鐘
                  },
                  child: const Text('繼續使用', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _warningCountdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return widget.child;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleUserInteraction,
      onPointerMove: _handleUserInteraction,
      onPointerUp: _handleUserInteraction,
      child: widget.child,
    );
  }
}