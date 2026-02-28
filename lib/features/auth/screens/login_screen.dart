import 'dart:async';
import 'dart:math';

import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/auth/screens/forgot_password_screen.dart';
import 'package:bitemates/features/auth/screens/signup_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Force Light Theme for White/Indigo contrast
    return Theme(
      data: AppTheme.lightTheme,
      child: const Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        body: EmojiLoginBody(),
      ),
    );
  }
}

class EmojiLoginBody extends StatefulWidget {
  const EmojiLoginBody({super.key});

  @override
  State<EmojiLoginBody> createState() => _EmojiLoginBodyState();
}

class _EmojiLoginBodyState extends State<EmojiLoginBody>
    with SingleTickerProviderStateMixin {
  // Animation & Physics
  late AnimationController _ticker;
  final _physicsEngine = EmojiEngine();
  StreamSubscription? _sensorSub;

  // Inputs
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  // Entrance Animations
  double _contentOpacity = 0.0;
  Offset _contentOffset = const Offset(0, 0.1);

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _ticker.addListener(_onTick);

    _initSensors();

    // Trigger Entrance
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _physicsEngine.init(MediaQuery.of(context).size);
      setState(() {
        _contentOpacity = 1.0;
        _contentOffset = Offset.zero;
      });
    });
  }

  void _initSensors() {
    // Smooth gyro reaction for parallax wind
    _sensorSub = gyroscopeEventStream().listen((event) {
      // Sensitivity
      const double sensitivity = 2.0;
      _physicsEngine.updateSensorForce(
        Offset(event.y * sensitivity, 0), // Only influence X sway
      );
    });
  }

  void _onTick() {
    _physicsEngine.update(MediaQuery.of(context).size);
    setState(() {}); // Redraw painter
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sensorSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.mediumImpact();
    // Explode emojis on tap
    _physicsEngine.explode();

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, __, ___) => const MainNavigationScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else if (mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Login failed'),
          backgroundColor: const Color(0xFF3F51B5), // Indigo
        ),
      );
    }
  }

  Future<void> _handleGoogleLogin(BuildContext context) async {
    HapticFeedback.mediumImpact();
    _physicsEngine.explode();

    final authProvider = context.read<AuthProvider>();

    try {
      await authProvider.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to launch Google Sign-In: $e'),
            backgroundColor: const Color(0xFF3F51B5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    const indigo = Color(0xFF6B7FFF); // Vibrant Indigo from AppTheme
    final size = MediaQuery.of(context).size;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          // 1. Emoji Rain Layer
          CustomPaint(
            size: Size.infinite,
            painter: EmojiPainter(_physicsEngine.particles),
          ),

          // 2. Foreground Content
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            right: 0,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: size.height),
                child: IntrinsicHeight(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOut,
                    opacity: _contentOpacity,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOutCubic,
                      offset: _contentOffset,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Spacer(flex: 2),
                            // HERO TEXT
                            Text(
                              'hello.',
                              style: GoogleFonts.inter(
                                fontSize: 64,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -3.0,
                                color: indigo, // indigo
                                height: 1.0,
                              ),
                            ),
                            Text(
                              'Welcome back.',
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[500],
                                letterSpacing: -0.5,
                              ),
                            ),
                            const Spacer(flex: 1),

                            // INPUTS
                            _MinimalInput(
                              controller: _emailController,
                              hint: 'Email',
                              icon: Icons.alternate_email,
                              validator: (v) => v!.contains('@')
                                  ? null
                                  : 'Enter a valid email',
                            ),
                            const SizedBox(height: 16),
                            _MinimalInput(
                              controller: _passwordController,
                              hint: 'Password',
                              icon: Icons.lock_outline_rounded,
                              isPassword: true,
                              isVisible: _isPasswordVisible,
                              onVisibilityChanged: () => setState(
                                () => _isPasswordVisible = !_isPasswordVisible,
                              ),
                              validator: (v) =>
                                  v!.length > 5 ? null : 'Password too short',
                            ),

                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ForgotPasswordScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Forgot Password?',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: indigo,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 32),

                            // ACTION BUTTON
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                return ElevatedButton(
                                  onPressed: auth.isLoading
                                      ? null
                                      : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: indigo,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    elevation: 0, // Flat
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: auth.isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                      : Text(
                                          'Sign In',
                                          style: GoogleFonts.inter(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                );
                              },
                            ),

                            const SizedBox(height: 20),

                            // GOOGLE SIGN IN
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                return OutlinedButton.icon(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () => _handleGoogleLogin(context),
                                  icon: Image.asset(
                                    'assets/images/google_logo.png',
                                    height: 20,
                                    width: 20,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.g_mobiledata),
                                  ),
                                  label: const Text('Continue with Google'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                    side: BorderSide(
                                      color: Colors.grey[200]!,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    textStyle: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    foregroundColor: Colors.black87,
                                  ),
                                );
                              },
                            ),

                            const Spacer(flex: 2),

                            // FOOTER
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "New here? ",
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const SignupScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    "Create Account",
                                    style: TextStyle(
                                      color: indigo,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MinimalInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final bool? isVisible;
  final VoidCallback? onVisibilityChanged;
  final String? Function(String?)? validator;

  const _MinimalInput({
    required this.controller,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.isVisible,
    this.onVisibilityChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    const indigo = Color(0xFF6B7FFF);
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !(isVisible ?? false),
      style: const TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      cursorColor: indigo,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontWeight: FontWeight.normal,
        ),
        prefixIcon: Icon(icon, color: Colors.grey[400], size: 22),
        // Minimalist: No fill, just background color of scaffold
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none, // Clean look
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: indigo, width: 2),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isVisible!
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.grey[400],
                  size: 20,
                ),
                onPressed: onVisibilityChanged,
              )
            : null,
      ),
      validator: validator,
    );
  }
}

// --- EMOJI PHYSICS ENGINE ---

class EmojiEngine {
  final List<FallingObject> particles = [];
  final Random _rnd = Random();
  Offset _sensorForce = Offset.zero;

  // Social & Food Emojis
  static const List<String> _emojis = [
    '🍕', '🍔', '🍟', '🍦', '🥂', '🍻', '🍹', // Food/Drink
    '🎉', '🎈', '✨', '👋', '🔥', '👀', // Social
    '🎱', '🎳', '🎮', '🎤', '🎲', // Activities
  ];

  // Brand Icons to mix in
  static final List<IconData> _icons = [
    Icons.music_note_rounded,
    Icons.star_rounded,
    Icons.favorite_rounded,
    Icons.bolt_rounded,
    Icons.local_bar_rounded,
    Icons.auto_awesome_rounded,
  ];

  void init(Size size) {
    particles.clear();
    // Create ~25 particles (mixed)
    for (int i = 0; i < 25; i++) {
      _spawnParticle(size, randomY: true);
    }
  }

  void _spawnParticle(Size size, {bool randomY = false}) {
    // 70% Emoji, 30% Brand Icons
    final isEmoji = _rnd.nextDouble() > 0.3;

    particles.add(
      FallingObject(
        content: isEmoji
            ? _emojis[_rnd.nextInt(_emojis.length)]
            : String.fromCharCode(
                _icons[_rnd.nextInt(_icons.length)].codePoint,
              ),
        isIcon: !isEmoji,
        position: Offset(
          _rnd.nextDouble() * size.width,
          randomY ? _rnd.nextDouble() * size.height : -50.0,
        ),
        velocity: Offset(
          (_rnd.nextDouble() - 0.5) * 0.5,
          _rnd.nextDouble() * 1.5 + 0.5,
        ),
        size: _rnd.nextDouble() * (isEmoji ? 20 : 30) + 20,
        rotation: _rnd.nextDouble() * pi * 2,
        rotationSpeed: (_rnd.nextDouble() - 0.5) * 0.1,
        color: !isEmoji
            ? const Color(0xFF6B7FFF).withOpacity(0.4)
            : null, // Transparent Indigo for icons
      ),
    );
  }

  void updateSensorForce(Offset force) {
    _sensorForce = force;
  }

  void explode() {
    for (var p in particles) {
      p.velocity += Offset(
        (_rnd.nextDouble() - 0.5) * 15,
        -_rnd.nextDouble() * 10 - 5,
      );
    }
  }

  void update(Size size) {
    for (int i = particles.length - 1; i >= 0; i--) {
      var p = particles[i];

      // Apply Gravity & Sensor
      p.velocity += Offset(_sensorForce.dx * 0.05, 0);
      p.position += p.velocity;

      // Update Rotation
      p.rotation += p.rotationSpeed;

      // Wrap / Respawn logic
      if (p.position.dy > size.height + 50) {
        p.position = Offset(_rnd.nextDouble() * size.width, -50);
        p.velocity = Offset(
          (_rnd.nextDouble() - 0.5) * 0.5,
          _rnd.nextDouble() * 1.5 + 0.5,
        );
      }

      if (p.position.dx < -50)
        p.position = Offset(size.width + 50, p.position.dy);
      if (p.position.dx > size.width + 50)
        p.position = Offset(-50, p.position.dy);
    }
  }
}

class FallingObject {
  String content; // Emoji char or Icon codePoint
  bool isIcon;
  Offset position;
  Offset velocity;
  double size;
  double rotation;
  double rotationSpeed;
  Color? color;

  FallingObject({
    required this.content,
    required this.isIcon,
    required this.position,
    required this.velocity,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
    this.color,
  });
}

class EmojiPainter extends CustomPainter {
  final List<FallingObject> particles;

  EmojiPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (var p in particles) {
      if (p.isIcon) {
        _drawIcon(canvas, p);
      } else {
        _drawText(canvas, p);
      }
    }
  }

  void _drawText(Canvas canvas, FallingObject p) {
    final textSpan = TextSpan(
      text: p.content,
      style: TextStyle(fontSize: p.size, height: 1.0),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    canvas.save();
    canvas.translate(p.position.dx, p.position.dy);
    canvas.rotate(p.rotation);
    canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  void _drawIcon(Canvas canvas, FallingObject p) {
    final textSpan = TextSpan(
      text: p.content,
      style: TextStyle(
        fontSize: p.size,
        height: 1.0,
        fontFamily: 'MaterialIcons', // Crucial for rendering IconData chars
        color: p.color,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    canvas.save();
    canvas.translate(p.position.dx, p.position.dy);
    canvas.rotate(p.rotation);
    canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EmojiPainter oldDelegate) => true;
}
