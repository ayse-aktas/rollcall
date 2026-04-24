import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/security_utils.dart';

enum LoginType { student, teacher }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  LoginType _loginType = LoginType.student;
  bool _isPasswordHidden = true;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
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
      final input = _emailController.text.trim();
      final password = _passwordController.text;

      // Auto-append domain for student if only number is entered
      String email = input;
      if (_loginType == LoginType.student && !input.contains('@')) {
        email = '$input@ogr.sakarya.edu.tr';
      }

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

      // Fetch profile and check device binding
      final currentDeviceId = await SecurityUtils.getUniqueDeviceId();
      final profile = await Supabase.instance.client
          .from('users')
          .select('role, device_id')
          .eq('id', response.user!.id)
          .single();

      final role = profile['role'] as String;
      final registeredDeviceId = profile['device_id'] as String?;

      if (role == 'student') {
        if (registeredDeviceId == null || registeredDeviceId.isEmpty) {
          // First time login - Bind the device
          await Supabase.instance.client
              .from('users')
              .update({'device_id': currentDeviceId})
              .eq('id', response.user!.id);
        } else if (registeredDeviceId != currentDeviceId) {
          // Device mismatch - Security Breach
          await Supabase.instance.client.auth.signOut();
          if (!mounted) return;
          setState(() {
            _errorMessage = 'Bu hesap başka bir cihaza kayıtlıdır.\nLütfen kendi cihazınızdan giriş yapın.';
            _isLoading = false;
          });
          return;
        }
      }

      if (!mounted) return;

      if (role == 'student') {
        Navigator.pushReplacementNamed(context, '/ogrenci-anasayfa');
      } else if (role == 'teacher') {
        Navigator.pushReplacementNamed(context, '/ogretmen-anasayfa');
      } else if (role == 'admin') {
        Navigator.pushReplacementNamed(context, '/admin-panel');
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = _translateAuthError(e.message));
    } catch (e) {
      debugPrint('Login Error: $e');
      setState(() => _errorMessage = 'Giriş işlemi sırasında bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _translateAuthError(String message) {
    if (message.contains('Invalid login credentials'))
      return 'E-posta veya şifre hatalı.';
    return 'Giriş yapılamadı. Lütfen tekrar deneyin.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 60),
                _buildLogoHeader(),
                const SizedBox(height: 30),
                _buildLoginCard(),
                const SizedBox(height: 40),
                _buildFooterLinks(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0052D4).withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.wifi_tethering_rounded,
              color: Color(0xFF1E60D2),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'RollCall',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF003CBF),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RollCall\'a Hoş Geldiniz',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1D1F),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sisteme erişmek ve yoklama işlemlerine katılmak için lütfen bilgilerinizi doğrulayın.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6F767E),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            _buildTypeToggle(),
            const SizedBox(height: 32),
            const Text(
              'KURUMSAL E-POSTA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1D1F),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _emailController,
              hint: _loginType == LoginType.student
                  ? 'b221210036@ogr.sakarya.edu.tr'
                  : 'ad.soyad@universite.edu.tr',
              prefixIcon: Icons.email_outlined,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ŞİFRE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1D1F),
                    letterSpacing: 0.5,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    'Şifremi Unuttum?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E60D2),
                    ),
                  ),
                ),
              ],
            ),
            _buildTextField(
              controller: _passwordController,
              hint: '••••••••',
              isPassword: true,
              prefixIcon: Icons.lock_outline_rounded,
            ),
            const SizedBox(height: 32),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            _buildSignInButton(),
            const SizedBox(height: 32),
            Center(
              child: Text.rich(
                TextSpan(
                  text: "Hesabınız yok mu? ",
                  style: const TextStyle(
                    color: Color(0xFF6F767E),
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: "Bölümünüzden erişim talep edin.",
                      style: const TextStyle(
                        color: Color(0xFF1E60D2),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _buildToggleItem(LoginType.student, 'Öğrenci')),
          Expanded(child: _buildToggleItem(LoginType.teacher, 'Akademisyen')),
        ],
      ),
    );
  }

  Widget _buildToggleItem(LoginType type, String label) {
    final isSelected = _loginType == type;
    return GestureDetector(
      onTap: () => setState(() => _loginType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isSelected
                ? const Color(0xFF1E60D2)
                : const Color(0xFF6F767E),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    bool isPassword = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && _isPasswordHidden,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: Color(0xFF1A1D1F),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFA6ADBB), fontSize: 15),
        filled: true,
        fillColor: const Color(0xFFE8F0FE),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _isPasswordHidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF6F767E),
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _isPasswordHidden = !_isPasswordHidden),
              )
            : null,
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A56CC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'GİRİŞ YAP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFooterLinks() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _footerIcon(Icons.link),
            const SizedBox(width: 20),
            _footerIcon(Icons.language),
            const SizedBox(width: 20),
            _footerIcon(Icons.home_outlined),
          ],
        ),
        const SizedBox(height: 40),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _footerText('© 2024 ROLLCALL SİSTEMLERİ.', width: 100),
                  _footerText('GİZLİLİK POLİTİKASI'),
                  _footerText('SİSTEM DURUMU'),
                  _footerText('BEACON AĞI ÇEVRİMİÇİ'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footerIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFBCC1CD),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _footerText(String text, {double? width}) {
    return SizedBox(
      width: width ?? 60,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6F767E),
          height: 1.4,
        ),
      ),
    );
  }
}
