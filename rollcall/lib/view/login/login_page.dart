import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/security_utils.dart';

enum LoginType { student, teacher, admin }

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

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
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
      final schoolNo = _emailController.text.trim();
      final password = _passwordController.text;

      // 1. Okul numarasından e-postayı ve rolü çekiyoruz
      final userData = await Supabase.instance.client
          .from('users')
          .select('email, role, device_id')
          .eq('school_no', schoolNo)
          .maybeSingle();

      if (userData == null) {
        setState(() => _errorMessage = 'Bu okul numarasına ait bir kullanıcı bulunamadı.');
        return;
      }

      final email = userData['email'] as String;
      final role = userData['role'] as String;
      final registeredDeviceId = userData['device_id'] as String?;

      if (_loginType == LoginType.student && role != 'student') {
        setState(() => _errorMessage = 'Bu hesap bir öğrenci hesabı değildir.\nLütfen Akademisyen sekmesini deneyin.');
        return;
      }
      if (_loginType == LoginType.teacher && role != 'teacher') {
        setState(() => _errorMessage = 'Bu hesap bir akademisyen hesabı değildir.\nLütfen Öğrenci sekmesini deneyin.');
        return;
      }
      if (_loginType == LoginType.admin && role != 'admin') {
        setState(() => _errorMessage = 'Bu hesap bir yönetici hesabı değildir.');
        return;
      }

      // 3. Giriş Yap
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        setState(() => _errorMessage = 'Şifre hatalı. Lütfen kontrol edin.');
        return;
      }

      // 4. Cihaz eşleştirme (Sadece öğrenciler için)
      final currentDeviceId = await SecurityUtils.getUniqueDeviceId();
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
            _errorMessage =
                'Bu hesap başka bir cihaza kayıtlıdır.\nLütfen kendi cihazınızdan giriş yapın.';
            _isLoading = false;
          });
          return;
        }
      }

      if (!mounted) return;

      if (role == 'admin') {
        Navigator.pushReplacementNamed(context, '/admin-panel');
      } else if (role == 'teacher') {
        Navigator.pushReplacementNamed(context, '/ogretmen-anasayfa');
      } else if (role == 'student') {
        Navigator.pushReplacementNamed(context, '/ogrenci-anasayfa');
      }
    } on AuthException catch (e) {
      debugPrint('Auth login error: message=${e.message}, status=${e.statusCode}, code=${e.code}');
      setState(() => _errorMessage = 'Giriş başarısız: ${_translateAuthError(e.message)}');
    } catch (e) {
      debugPrint('Login Error: $e');
      setState(() => _errorMessage = 'Hata: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  String _translateAuthError(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'E-posta veya şifre hatalı.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 60),
              _buildLogoHeader(),
              const SizedBox(height: 30),
              _buildLoginCard(),
              const SizedBox(height: 40),
              // Footer links removed as requested
              const SizedBox(height: 20),
            ],
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
            child: Image.asset(
              'assets/images/app_icon.png',
              width: 28,
              height: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'RollCall',
            style: TextStyle(
              fontSize: 22,
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
                  fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1D1F),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sisteme erişmek ve yoklama işlemlerine katılmak için lütfen bilgilerinizi doğrulayın.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6F767E),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            _buildTypeToggle(),
            const SizedBox(height: 32),
            const Text(
              'OKUL NUMARASI',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1D1F),
                letterSpacing: 0.5,
              ),
            ),

            const SizedBox(height: 12),
            _buildTextField(
              controller: _emailController,
              hint: _loginType == LoginType.student
                  ? 'B123456789'
                  : 't123456789',
              prefixIcon: Icons.person_outline_rounded,
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ŞİFRE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1D1F),
                    letterSpacing: 0.5,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                  child: const Text(
                    'Şifremi Unuttum?',
                    style: TextStyle(
                      fontSize: 11,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12, height: 1.4),
                    ),
                    if (_errorMessage!.contains('Şifre hatalı'))
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Şifrenizi mi unuttunuz?',
                          style: TextStyle(
                            color: Color(0xFF1E60D2),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            _buildSignInButton(),
            const SizedBox(height: 32),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/support'),
                child: Text.rich(
                  TextSpan(
                    text: "Bir sorun mu var? ",
                    style: const TextStyle(
                      color: Color(0xFF6F767E),
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text: "Yönetici ile iletişime geçin.",
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
          Expanded(child: _buildToggleItem(LoginType.admin, 'Admin')),
        ],
      ),
    );
  }

  Widget _buildToggleItem(LoginType type, String label) {
    final isSelected = _loginType == type;
    return GestureDetector(
      onTap: () => setState(() => _loginType = type),
      child: Container(
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

        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected
                  ? const Color(0xFF1E60D2)
                  : const Color(0xFF6F767E),
            ),
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
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF1A1D1F),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFA6ADBB), fontSize: 14),
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
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,

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
                      fontSize: 14,
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
}
