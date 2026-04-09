import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/theme/colors/app_colors.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _schoolNoController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordHidden = true;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const _emailDomain = '@ogr.sakarya.edu.tr';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _schoolNoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final schoolNo = _schoolNoController.text.trim().toLowerCase();
      final password = _passwordController.text;
      final email = '$schoolNo$_emailDomain';

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        setState(
          () => _errorMessage = 'Giriş başarısız. Bilgilerinizi kontrol edin.',
        );
        return;
      }

      final user = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('school_no', schoolNo)
          .single();

      if (!mounted) return;

      switch (user['role'] as String) {
        case 'student':
          Navigator.pushReplacementNamed(context, '/ogrenci-anasayfa');
          break;
        case 'teacher':
          Navigator.pushReplacementNamed(context, '/ogretmen-anasayfa');
          break;
        case 'admin':
          Navigator.pushReplacementNamed(context, '/admin-panel');
          break;
        default:
          setState(() => _errorMessage = 'Tanımsız kullanıcı rolü.');
      }
    } on AuthException catch (e) {
      debugPrint('Supabase auth error: ${e.message}');
      setState(() => _errorMessage = _translateAuthError(e.message));
    } catch (e) {
      debugPrint('Unexpected login error: $e');
      setState(
        () => _errorMessage =
            'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _translateAuthError(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'Okul numarası veya şifre hatalı.';
    }
    if (message.contains('Email not confirmed')) {
      return 'Hesabınız henüz onaylanmamış.';
    }
    if (message.contains('Too many requests')) {
      return 'Çok fazla deneme yaptınız. Lütfen bekleyin.';
    }
    return 'Giriş yapılamadı. Lütfen tekrar deneyin.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 56),
                      const _LogoSection(),
                      const SizedBox(height: 52),
                      const _LabelText('Okul Numarası'),
                      const SizedBox(height: 8),
                      _SchoolNoField(controller: _schoolNoController),
                      const SizedBox(height: 4),
                      _DomainPreview(controller: _schoolNoController),
                      const SizedBox(height: 16),
                      const _LabelText('Şifre'),
                      const SizedBox(height: 8),
                      _PasswordField(
                        controller: _passwordController,
                        isHidden: _isPasswordHidden,
                        onToggleVisibility: () => setState(
                          () => _isPasswordHidden = !_isPasswordHidden,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/sifre-sifirla'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text(
                            'Şifremi Unuttum',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_errorMessage != null) ...[
                        _ErrorBanner(message: _errorMessage!),
                        const SizedBox(height: 16),
                      ],
                      _LoginButton(isLoading: _isLoading, onPressed: _signIn),
                      const SizedBox(height: 40),
                      const _HelpRow(),
                      const SizedBox(height: 32),
                    ],
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

class _LogoSection extends StatelessWidget {
  const _LogoSection();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderPrimary, width: 1),
          ),
          child: const Icon(
            Icons.wifi_tethering_rounded,
            color: AppColors.primary,
            size: 28,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'RollCall',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Okul numaranız ile giriş yapın',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
      ],
    );
  }
}

class _LabelText extends StatelessWidget {
  final String text;
  const _LabelText(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _DomainPreview extends StatefulWidget {
  final TextEditingController controller;
  const _DomainPreview({required this.controller});
  @override
  State<_DomainPreview> createState() => _DomainPreviewState();
}

class _DomainPreviewState extends State<_DomainPreview> {
  static final _regex = RegExp(r'^[a-zA-Z]\d{9}$');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text.trim().toLowerCase();
    if (value.isEmpty) return const SizedBox.shrink();
    final isValid = _regex.hasMatch(value);
    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle_outline : Icons.info_outline,
          size: 13,
          color: isValid ? AppColors.success : AppColors.textHint,
        ),
        const SizedBox(width: 6),
        Text(
          isValid ? '$value@ogr.sakarya.edu.tr' : 'Format: b221210036',
          style: TextStyle(
            color: isValid ? AppColors.success : AppColors.textHint,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _SchoolNoField extends StatelessWidget {
  final TextEditingController controller;
  static final _regex = RegExp(r'^[a-zA-Z]\d{9}$');
  const _SchoolNoField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      inputFormatters: [
        LengthLimitingTextInputFormatter(10),
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
      ],
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
      ),
      decoration: _buildInputDecoration(
        hint: 'b221210036',
        prefixIcon: Icons.badge_outlined,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Okul numarası boş bırakılamaz';
        }
        if (!_regex.hasMatch(value.trim())) {
          return 'Geçersiz format. Örnek: b221210036';
        }
        return null;
      },
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool isHidden;
  final VoidCallback onToggleVisibility;
  const _PasswordField({
    required this.controller,
    required this.isHidden,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: isHidden,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      decoration: _buildInputDecoration(
        hint: '••••••••',
        prefixIcon: Icons.lock_outline_rounded,
        suffixIcon: IconButton(
          icon: Icon(
            isHidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppColors.textHint,
            size: 20,
          ),
          onPressed: onToggleVisibility,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Şifre boş bırakılamaz';
        if (value.length < 6) return 'Şifre en az 6 karakter olmalıdır';
        return null;
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.errorBorder, width: 1),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.errorText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;
  const _LoginButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.textPrimary,
                  ),
                ),
              )
            : const Text(
                'Giriş Yap',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text.rich(
        TextSpan(
          text: 'Hesabınızla ilgili sorun mu var?  ',
          style: const TextStyle(color: AppColors.textHint, fontSize: 13),
          children: [
            WidgetSpan(
              child: GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/yardim'),
                child: const Text(
                  'Yardım Al',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

InputDecoration _buildInputDecoration({
  required String hint,
  required IconData prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: AppColors.textHint,
      fontSize: 15,
      letterSpacing: 0.5,
    ),
    filled: true,
    fillColor: AppColors.surface,
    prefixIcon: Icon(prefixIcon, color: AppColors.textSecondary, size: 20),
    suffixIcon: suffixIcon,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.borderFocus, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.error, width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.error, width: 1.5),
    ),
    errorStyle: const TextStyle(color: AppColors.errorText, fontSize: 12),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}
