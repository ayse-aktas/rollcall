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
  final _okulNoController = TextEditingController();
  final _sifreController = TextEditingController();

  bool _sifreGizli = true;
  bool _yukleniyor = false;
  String? _hataMessaji;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static final _okulNoRegex = RegExp(r'^[a-zA-Z]\d{9}$');
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
    _okulNoController.dispose();
    _sifreController.dispose();
    super.dispose();
  }

  Future<void> _girisYap() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _yukleniyor = true;
      _hataMessaji = null;
    });

    try {
      final okulNo = _okulNoController.text.trim().toLowerCase();
      final sifre = _sifreController.text;
      final email = '$okulNo$_emailDomain';

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: sifre,
      );

      if (response.user == null) {
        setState(
          () => _hataMessaji = 'Giriş başarısız. Bilgilerinizi kontrol edin.',
        );
        return;
      }

      // ✅ Düzeltildi: 'kullanicilar' → 'users', 'rol' → 'role'
      final kullanici = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('id', response.user!.id)
          .single();

      if (!mounted) return;

      // ✅ Düzeltildi: 'ogrenci' → 'student', 'ogretmen' → 'teacher'
      switch (kullanici['role'] as String) {
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
          setState(() => _hataMessaji = 'Tanımsız kullanıcı rolü.');
      }
    } on AuthException catch (e) {
      setState(() => _hataMessaji = _hataMesajiCevir(e.message));
    } catch (e) {
      setState(
        () => _hataMessaji =
            'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.',
      );
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  String _hataMesajiCevir(String mesaj) {
    if (mesaj.contains('Invalid login credentials'))
      return 'Okul numarası veya şifre hatalı.';
    if (mesaj.contains('Email not confirmed'))
      return 'Hesabınız henüz onaylanmamış.';
    if (mesaj.contains('Too many requests'))
      return 'Çok fazla deneme yaptınız. Lütfen bekleyin.';
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
                      const _LogoBolumu(),
                      const SizedBox(height: 52),
                      const _EtiketText('Okul Numarası'),
                      const SizedBox(height: 8),
                      _OkulNoAlani(controller: _okulNoController),
                      const SizedBox(height: 4),
                      _DomainOnizleme(controller: _okulNoController),
                      const SizedBox(height: 16),
                      const _EtiketText('Şifre'),
                      const SizedBox(height: 8),
                      _SifreAlani(
                        controller: _sifreController,
                        gizli: _sifreGizli,
                        onGizliToggle: () =>
                            setState(() => _sifreGizli = !_sifreGizli),
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
                      if (_hataMessaji != null) ...[
                        _HataMesaji(mesaj: _hataMessaji!),
                        const SizedBox(height: 16),
                      ],
                      _GirisButonu(
                        yukleniyor: _yukleniyor,
                        onPressed: _girisYap,
                      ),
                      const SizedBox(height: 40),
                      const _YardimSatiri(),
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

class _LogoBolumu extends StatelessWidget {
  const _LogoBolumu();
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
          'BEACONTrack',
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

class _EtiketText extends StatelessWidget {
  final String metin;
  const _EtiketText(this.metin);
  @override
  Widget build(BuildContext context) {
    return Text(
      metin,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _DomainOnizleme extends StatefulWidget {
  final TextEditingController controller;
  const _DomainOnizleme({required this.controller});
  @override
  State<_DomainOnizleme> createState() => _DomainOnizlemeState();
}

class _DomainOnizlemeState extends State<_DomainOnizleme> {
  static final _regex = RegExp(r'^[a-zA-Z]\d{9}$');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final val = widget.controller.text.trim().toLowerCase();
    if (val.isEmpty) return const SizedBox.shrink();
    final gecerli = _regex.hasMatch(val);
    return Row(
      children: [
        Icon(
          gecerli ? Icons.check_circle_outline : Icons.info_outline,
          size: 13,
          color: gecerli ? AppColors.success : AppColors.textHint,
        ),
        const SizedBox(width: 6),
        Text(
          gecerli ? '$val@ogr.sakarya.edu.tr' : 'Format: b221210036',
          style: TextStyle(
            color: gecerli ? AppColors.success : AppColors.textHint,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _OkulNoAlani extends StatelessWidget {
  final TextEditingController controller;
  static final _regex = RegExp(r'^[a-zA-Z]\d{9}$');
  const _OkulNoAlani({required this.controller});

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
      decoration: _inputDecoration(
        hint: 'b221210036',
        prefixIcon: Icons.badge_outlined,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty)
          return 'Okul numarası boş bırakılamaz';
        if (!_regex.hasMatch(v.trim()))
          return 'Geçersiz format. Örnek: b221210036';
        return null;
      },
    );
  }
}

class _SifreAlani extends StatelessWidget {
  final TextEditingController controller;
  final bool gizli;
  final VoidCallback onGizliToggle;
  const _SifreAlani({
    required this.controller,
    required this.gizli,
    required this.onGizliToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: gizli,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      decoration: _inputDecoration(
        hint: '••••••••',
        prefixIcon: Icons.lock_outline_rounded,
        suffixIcon: IconButton(
          icon: Icon(
            gizli ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.textHint,
            size: 20,
          ),
          onPressed: onGizliToggle,
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Şifre boş bırakılamaz';
        if (v.length < 6) return 'Şifre en az 6 karakter olmalıdır';
        return null;
      },
    );
  }
}

class _HataMesaji extends StatelessWidget {
  final String mesaj;
  const _HataMesaji({required this.mesaj});
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
              mesaj,
              style: const TextStyle(color: AppColors.errorText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _GirisButonu extends StatelessWidget {
  final bool yukleniyor;
  final VoidCallback onPressed;
  const _GirisButonu({required this.yukleniyor, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: yukleniyor ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: yukleniyor
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

class _YardimSatiri extends StatelessWidget {
  const _YardimSatiri();
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

InputDecoration _inputDecoration({
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
