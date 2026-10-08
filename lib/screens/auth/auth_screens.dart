import 'dart:async';
import 'dart:io';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import '/utils/audit_logger.dart';

// ==========================================
// 1. 登入畫面
// ==========================================
class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool rememberPassword = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  bool _isServerConnected = false; 
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _loadSavedCredentials();
    _startHeartbeatCheck(); 
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHeartbeatCheck();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _heartbeatTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _heartbeatTimer?.cancel(); 
    super.dispose();
  }

  void _startHeartbeatCheck() {
    _heartbeatTimer?.cancel(); 
    _checkConnection(); 
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    if (kIsWeb) {
      if (!_isServerConnected && mounted) {
        setState(() => _isServerConnected = true);
      }
      return;
    }

    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        if (!_isServerConnected && mounted) {
          setState(() => _isServerConnected = true); 
        }
      }
    } on SocketException catch (_) {
      if (_isServerConnected && mounted) {
        setState(() => _isServerConnected = false); 
      }
    }
  }

  Widget _buildConnectionStatusLight() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isServerConnected ? Colors.greenAccent : Colors.redAccent,
            boxShadow: [
              BoxShadow(
                color: (_isServerConnected ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.6),
                blurRadius: 8,
                spreadRadius: 2,
              )
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _isServerConnected ? '已連線' : '無連線，請確認網路是否可用',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _isServerConnected ? Colors.teal.shade700 : Colors.redAccent,
          ),
        ),
      ],
    );
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      rememberPassword = prefs.getBool('remember_password') ?? false;
      if (rememberPassword) {
        _emailController.text = prefs.getString('saved_email') ?? '';
        _passwordController.text = prefs.getString('saved_password') ?? '';
      }
    });
  }

  Future<void> _handleLogin() async {
    if (!_isServerConnected) {
      _showErrorDialog('目前無網路連線，請檢查您的 WiFi 或行動網路設定。');
      return;
    }

    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showErrorDialog('請輸入電子郵件與密碼');
      return;
    }

    setState(() { _isLoading = true; });
    try {
      final AuthResponse res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.session != null) {
        String platform = kIsWeb ? '網頁版管理平台' : '手機APP';
        await logUserAction(
          '登入', 
          details: '使用者透過 $platform 成功登入'
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_password', rememberPassword);

        if (rememberPassword) {
          await prefs.setString('saved_email', _emailController.text.trim());
          await prefs.setString('saved_password', _passwordController.text.trim());
        } else {
          await prefs.remove('saved_email');
          await prefs.remove('saved_password');
        }

        widget.onLoginSuccess();
      }
    } on AuthException catch (error) {
      _showErrorDialog(error.message);
    } catch (error) {
      _showErrorDialog('發生未知錯誤，請稍後再試。');
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _handleForgotPassword() async {
    final TextEditingController resetEmailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Colors.black.withValues(alpha: 0.6), 
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5), 
          ),
          title: const Text('重設密碼', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: resetEmailController,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '請輸入您註冊的電子郵件',
              labelStyle: TextStyle(color: Colors.white54, fontSize: 13),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: Colors.grey))
            ),
            TextButton(
              onPressed: () async {
                final emailText = resetEmailController.text.trim();
                if (emailText.isEmpty) return;
                
                Navigator.pop(context); 
                _sendOtpAndShowVerificationDialog(emailText); 
              },
              child: const Text('發送驗證碼', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendOtpAndShowVerificationDialog(String email) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.clearSnackBars(); 
    
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('驗證碼已發送至您的信箱！'), backgroundColor: Colors.teal));
    } catch (e) {
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('發送失敗，請確認信箱是否正確。'), backgroundColor: Colors.redAccent));
      return;
    }

    if (!mounted) return;
    final TextEditingController otpController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
              ),
              title: const Text('輸入驗證碼', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('我們已寄送8位數驗證碼至 $email', style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: otpController,
                    style: const TextStyle(color: Colors.tealAccent, letterSpacing: 8.0, fontSize: 20, fontWeight: FontWeight.bold),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      hintText: '00000000',
                      hintStyle: TextStyle(color: Colors.white24, letterSpacing: 8.0),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(context),
                  child: const Text('取消', style: TextStyle(color: Colors.grey))
                ),
                TextButton(
                  onPressed: isVerifying ? null : () async {
                    final token = otpController.text.trim();
                    if (token.length != 8) { 
                      scaffoldMessenger.clearSnackBars(); 
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('請輸入完整的8位數驗證碼')));
                      return;
                    }

                    setStateDialog(() { isVerifying = true; });

                    try {
                      await Supabase.instance.client.auth.verifyOTP(
                        email: email,
                        token: token,
                        type: OtpType.recovery,
                      );
                      
                      if (!context.mounted) return;
                      Navigator.pop(context); 
                      _showUpdatePasswordDialog(); 

                    } on AuthException catch (e) {
                      scaffoldMessenger.clearSnackBars(); 
                      scaffoldMessenger.showSnackBar(SnackBar(content: Text('驗證失敗：${e.message}'), backgroundColor: Colors.redAccent));
                    } catch (e) {
                      scaffoldMessenger.clearSnackBars(); 
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('發生未知錯誤'), backgroundColor: Colors.redAccent));
                    } finally {
                      setStateDialog(() { isVerifying = false; });
                    }
                  },
                  child: isVerifying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.tealAccent, strokeWidth: 2))
                    : const Text('驗證', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _showUpdatePasswordDialog() {
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    bool isUpdating = false;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
              ),
              title: const Text('設定全新密碼', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('驗證成功，請輸入您的新密碼', style: TextStyle(color: Colors.tealAccent, fontSize: 13)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '新密碼(最少6個字元)',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 13),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '再次確認新密碼',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 13),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.pop(context),
                  child: const Text('取消', style: TextStyle(color: Colors.grey))
                ),
                TextButton(
                  onPressed: isUpdating ? null : () async {
                    final p1 = newPasswordController.text.trim();
                    final p2 = confirmPasswordController.text.trim();

                    if (p1.isEmpty || p2.isEmpty) {
                      ScaffoldMessenger.of(context).clearSnackBars(); 
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密碼欄位不可為空')));
                      return;
                    }
                    if (p1 != p2) {
                      ScaffoldMessenger.of(context).clearSnackBars(); 
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('兩次輸入的密碼不一致')));
                      return;
                    }
                    if (p1.length < 6) {
                      ScaffoldMessenger.of(context).clearSnackBars(); 
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密碼長度至少需要6個字元')));
                      return;
                    }

                    setStateDialog(() { isUpdating = true; });

                    try {
                      await Supabase.instance.client.auth.updateUser(UserAttributes(password: p1));
                      
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).clearSnackBars(); 
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('密碼修改成功，請使用新密碼重新登入'), backgroundColor: Colors.teal)
                      );
                      
                      await Supabase.instance.client.auth.signOut();
                      
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).clearSnackBars(); 
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('密碼更新失敗，請稍後再試'), backgroundColor: Colors.redAccent)
                      );
                    } finally {
                      setStateDialog(() { isUpdating = false; });
                    }
                  },
                  child: isUpdating 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.tealAccent, strokeWidth: 2))
                    : const Text('確認修改', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Colors.black.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
          ),
          title: const Text('登入失敗', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
          content: Text(message, style: const TextStyle(color: Colors.white70, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('確定', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              isWideScreen ? 'assets/web_login_bg.png' : 'assets/login_full_bg.png', 
              fit: BoxFit.cover,
            ),
          ),
          
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight, 
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            isWideScreen ? const Spacer() : const SizedBox(height: 200), 
                            
                            Padding(
                              padding: EdgeInsets.only(
                                left: 24.0, 
                                right: isWideScreen ? 120.0 : 24.0,
                              ),
                              child: Align( 
                                alignment: isWideScreen ? Alignment.centerRight : Alignment.center,
                                child: ConstrainedBox( 
                                  constraints: const BoxConstraints(maxWidth: 400),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), 
                                      child: Container(
                                        padding: const EdgeInsets.all(24.0),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.6), 
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.only(bottom: 24.0),
                                              child: Text(
                                                'FTESS Home',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.normal,
                                                  color: Colors.teal,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                            ),
                                            TextField(
                                              controller: _emailController,
                                              keyboardType: TextInputType.emailAddress,
                                              textInputAction: TextInputAction.next,
                                              style: const TextStyle(fontSize: 13),
                                              decoration: const InputDecoration(labelText: '電子郵件 (Email)', labelStyle: TextStyle(fontSize: 13), prefixIcon: Icon(Icons.email, size: 20), border: OutlineInputBorder()),
                                            ),
                                            const SizedBox(height: 16),
                                            TextField(
                                              controller: _passwordController,
                                              obscureText: _obscurePassword,
                                              textInputAction: TextInputAction.done, 
                                              onSubmitted: (_) {                     
                                                if (!_isLoading) _handleLogin();
                                              },
                                              style: const TextStyle(fontSize: 13),
                                              decoration: InputDecoration(
                                                labelText: '密碼', 
                                                labelStyle: const TextStyle(fontSize: 13), 
                                                prefixIcon: const Icon(Icons.lock, size: 20), 
                                                border: const OutlineInputBorder(),
                                                suffixIcon: IconButton(
                                                  icon: Icon(
                                                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                                    size: 20,
                                                    color: Colors.grey,
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      _obscurePassword = !_obscurePassword;
                                                    });
                                                  },
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            // 🎯 修改區塊：移除自動登入，並將忘記密碼移至此處
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    Checkbox(value: rememberPassword, activeColor: Colors.teal, onChanged: (value) { setState(() { rememberPassword = value ?? false; }); }),
                                                    const Text('記住密碼', style: TextStyle(color: Colors.black87, fontSize: 12)),
                                                  ],
                                                ),
                                                TextButton(
                                                  style: TextButton.styleFrom(
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: const Size(50, 30),
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                  onPressed: _handleForgotPassword, 
                                                  child: const Text('忘記密碼？', style: TextStyle(color: Colors.black54, fontSize: 12, decoration: TextDecoration.underline))
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                              onPressed: _isLoading ? null : _handleLogin,
                                              child: _isLoading
                                                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2))
                                                : const Text('登入', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
                                            ),
                                            const SizedBox(height: 12),
                                            // 🎯 修改區塊：將註冊按鈕獨立放在此處，使其透過外層自動延展為等寬
                                            OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(vertical: 14), 
                                                side: const BorderSide(color: Colors.teal), 
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                              ),
                                              onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen())); },
                                              child: const Text('註冊新帳號', style: TextStyle(fontSize: 14, color: Colors.teal, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            
                            const Spacer(),
                            
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: _buildConnectionStatusLight(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. 註冊帳號畫面
// ==========================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _agreeTerms = false;
  bool _isLoading = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _handleRegister() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) { _showSnackBar('請填寫所有欄位'); return; }
    if (password != confirmPassword) { _showSnackBar('兩次輸入的密碼不一致'); return; }
    if (password.length < 6) { _showSnackBar('密碼長度至少需要 6 個字元'); return; }
    if (!_agreeTerms) { _showSnackBar('請先閱讀並同意使用者服務條款'); return; }

    setState(() { _isLoading = true; });
    try {
      await Supabase.instance.client.auth.signUp(email: email, password: password);
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('註冊成功', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
          content: Text('驗證郵件已發送至 $email。\n請前往信箱點擊驗證連結以啟用您的帳號。'),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              child: const Text('回到登入頁面', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );
    } on AuthException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('註冊時發生未知錯誤。');
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars(); 
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('註冊新帳號', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('請填寫下方資訊以註冊您的帳號', style: TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 24),
              TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: '電子郵件 (Email)', prefixIcon: Icon(Icons.email), border: OutlineInputBorder())),
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordController, 
                obscureText: _obscurePassword, 
                decoration: InputDecoration(
                  labelText: '請輸入您的密碼', 
                  prefixIcon: const Icon(Icons.lock_outline), 
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20, color: Colors.grey),
                    onPressed: () { setState(() { _obscurePassword = !_obscurePassword; }); },
                  ),
                )
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _confirmPasswordController, 
                obscureText: _obscureConfirmPassword, 
                decoration: InputDecoration(
                  labelText: '請再次輸入密碼', 
                  prefixIcon: const Icon(Icons.lock), 
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, size: 20, color: Colors.grey),
                    onPressed: () { setState(() { _obscureConfirmPassword = !_obscureConfirmPassword; }); },
                  ),
                )
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(value: _agreeTerms, activeColor: Colors.teal, onChanged: (value) { setState(() { _agreeTerms = value ?? false; }); }),
                  const Text('我已閱讀並同意 ', style: TextStyle(fontSize: 13, color: Colors.black54)),
                  GestureDetector(
                    onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const TermsScreen())); },
                    child: const Text('使用者服務條款', style: TextStyle(fontSize: 13, color: Colors.teal, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: _isLoading ? null : _handleRegister,
                child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2))
                  : const Text('註冊帳號', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. 服務條款畫面
// ==========================================
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});
  Future<String> _loadTermsText() async {
    try {
      return await rootBundle.loadString('assets/terms.txt');
    } catch (e) {
      return '無法載入條款檔案，請確認 assets/terms.txt 是否正確放置。';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('使用者服務與隱私權條款', style: TextStyle(color: Colors.black87, fontSize: 16, fontStyle: FontStyle.normal, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _loadTermsText(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)));
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
                child: Text(snapshot.data ?? '', style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.6)),
              ),
            );
          },
        ),
      ),
    );
  }
}