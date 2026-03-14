import 'dart:math' as math;

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/auth_store.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _AuthMode { login, register }

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController(text: 'password');
  final _confirmPassword = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _loading = false;
  String? _error;

  bool get _isLogin => _mode == _AuthMode.login;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _error = null;
      if (mode == _AuthMode.login) {
        _confirmPassword.clear();
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await context.read<AuthStore>().login(_username.text.trim(), _password.text);
      } else {
        await AuthService.register(
          username: _username.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('注册成功，请登录')),
        );
        setState(() {
          _mode = _AuthMode.login;
          _password.clear();
          _confirmPassword.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF111827), Color(0xFF000000)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 8,
                color: const Color(0xCC111827),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: SvgPicture.asset(
                              'assets/logo.svg',
                              fit: BoxFit.contain,
                              placeholderBuilder: (_) => const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Emby MVP',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        AnimatedTextKit(
                          key: ValueKey(_mode),
                          isRepeatingAnimation: false,
                          totalRepeatCount: 1,
                          animatedTexts: [
                            TypewriterAnimatedText(
                              _isLogin ? '登录后开始你的媒体之旅' : '注册账号后开始你的媒体之旅',
                              textAlign: TextAlign.center,
                              speed: const Duration(milliseconds: 55),
                              textStyle: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 360),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final rotate = Tween<double>(begin: math.pi / 2, end: 0).animate(animation);
                            return AnimatedBuilder(
                              animation: animation,
                              child: child,
                              builder: (context, c) {
                                final t = Matrix4.identity()
                                  ..setEntry(3, 2, 0.001)
                                  ..rotateY(rotate.value);
                                return Opacity(
                                  opacity: animation.value.clamp(0.0, 1.0),
                                  child: Transform(
                                    alignment: Alignment.center,
                                    transform: t,
                                    child: c,
                                  ),
                                );
                              },
                            );
                          },
                          child: _isLogin
                              ? Column(
                                  key: const ValueKey('login_mode'),
                                  children: [
                                    TextFormField(
                                      controller: _username,
                                      decoration: const InputDecoration(
                                        labelText: '用户名',
                                        prefixIcon: Icon(Icons.person_outline),
                                      ),
                                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _password,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: '密码',
                                        prefixIcon: Icon(Icons.lock_outline),
                                      ),
                                      validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      height: 48,
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: _loading ? null : _submit,
                                        child: _loading
                                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator())
                                            : const Text('登录', style: TextStyle(fontSize: 16)),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text('还没有账号？', style: TextStyle(color: Colors.white70)),
                                        GestureDetector(
                                          onTap: _loading ? null : () => _switchMode(_AuthMode.register),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Text(
                                              '注册',
                                              style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              : Column(
                                  key: const ValueKey('register_mode'),
                                  children: [
                                    TextFormField(
                                      controller: _username,
                                      decoration: const InputDecoration(
                                        labelText: '用户名',
                                        prefixIcon: Icon(Icons.person_outline),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return '请输入用户名';
                                        if (v.trim().length < 3) return '用户名至少3位';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _password,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: '密码',
                                        prefixIcon: Icon(Icons.lock_outline),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return '请输入密码';
                                        if (v.length < 6) return '密码至少6位';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _confirmPassword,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: '确认密码',
                                        prefixIcon: Icon(Icons.verified_user_outlined),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return '请再次输入密码';
                                        if (v != _password.text) return '两次密码不一致';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      height: 48,
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: _loading ? null : _submit,
                                        child: _loading
                                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator())
                                            : const Text('注册', style: TextStyle(fontSize: 16)),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text('已有账号？', style: TextStyle(color: Colors.white70)),
                                        GestureDetector(
                                          onTap: _loading ? null : () => _switchMode(_AuthMode.login),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Text(
                                              '登录',
                                              style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
