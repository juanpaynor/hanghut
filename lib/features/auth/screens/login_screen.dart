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
        body: ParticleLoginBody(),
      ),
    );
  }
}

class ParticleLoginBody extends StatefulWidget {
  const ParticleLoginBody({super.key});

  @override
  State<ParticleLoginBody> createState() => _ParticleLoginBodyState();
}

class _ParticleLoginBodyState extends State<ParticleLoginBody>
    with SingleTickerProviderStateMixin {
  // Animation & Physics
  late AnimationController _ticker;
  final _physicsEngine = ParticleEngine();
  StreamSubscription? _sensorSub;

  // Inputs
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  // Entrance Animations
  double _cardOpacity = 0.0;
  Offset _cardOffset = const Offset(0, 0.1);

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
        _cardOpacity = 1.0;
        _cardOffset = Offset.zero;
      });
    });
  }

  void _initSensors() {
    // Smooth gyro reaction
    _sensorSub = gyroscopeEventStream().listen((event) {
      // Sensitivity
      const double sensitivity = 5.0;
      _physicsEngine.updateSensorForce(
        Offset(event.y * sensitivity, event.x * sensitivity),
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
    // Explode particles on tap
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
    // Explode particles on tap
    _physicsEngine.explode();

    final authProvider = context.read<AuthProvider>();

    try {
      // Launch OAuth flow in external browser
      // The actual authentication will complete via deep link callback
      // and AuthProvider will listen to auth state changes automatically
      await authProvider.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to launch Google Sign-In: $e'),
            backgroundColor: const Color(0xFF3F51B5), // Indigo
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    const indigo = Color(0xFF3F51B5);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          // 1. Interactive Particle Network (Background)
          CustomPaint(
            size: Size.infinite,
            painter: ParticlePainter(_physicsEngine.particles),
          ),

          // 2. Foreground Content
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0, // Fill screen, rely on padding for insets
            left: 0,
            right: 0,
            child: Center(
              child: SingleChildScrollView(
                // Ensure content pushes up when keyboard appears
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: bottomInset > 0 ? bottomInset + 20 : 20,
                  top: 20,
                ),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  opacity: _cardOpacity,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    offset: _cardOffset,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: indigo.withOpacity(0.15),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // HERO SECTION
                            Center(
                              child: Image.asset(
                                'assets/images/Hanghut.png',
                                height: 220, // Increased a bit as requested
                                width: 220,
                                fit: BoxFit.contain,
                              ),
                            ),
                            // "Hanghut" text removed for cleaner look
                            const SizedBox(height: 12),
                            Text(
                              'Meet new people.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: indigo.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 24), // Reduced from 32
                            // INPUTS
                            _IndigoInput(
                              controller: _emailController,
                              hint: 'Email',
                              icon: Icons.email_outlined,
                              validator: (v) => v!.contains('@')
                                  ? null
                                  : 'Enter a valid email',
                            ),
                            const SizedBox(height: 12),
                            _IndigoInput(
                              controller: _passwordController,
                              hint: 'Password',
                              icon: Icons.lock_outline,
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
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    color: indigo.withOpacity(0.8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

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
                                      vertical: 18,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 10,
                                    shadowColor: indigo.withOpacity(0.4),
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
                                          'Connect',
                                          style: GoogleFonts.outfit(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                );
                              },
                            ),

                            const SizedBox(height: 24),

                            // GOOGLE SIGN IN
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                return OutlinedButton.icon(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () => _handleGoogleLogin(context),
                                  icon: Image.asset(
                                    'assets/images/google_logo.png',
                                    height: 24,
                                    width: 24,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.g_mobiledata),
                                  ),
                                  label: const Text('Sign in with Google'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    side: BorderSide(
                                      color: indigo.withOpacity(0.2),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    textStyle: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    foregroundColor: Colors.black87,
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 24),

                            // FOOTER
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "New to Hanghut? ",
                                  style: TextStyle(
                                    color: indigo.withOpacity(0.6),
                                  ),
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
                                    "Join Here",
                                    style: TextStyle(
                                      color: indigo,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

class _IndigoInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final bool? isVisible;
  final VoidCallback? onVisibilityChanged;
  final String? Function(String?)? validator;

  const _IndigoInput({
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
    const indigo = Color(0xFF3F51B5);
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !(isVisible ?? false),
      style: const TextStyle(color: indigo, fontWeight: FontWeight.w600),
      cursorColor: indigo,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: indigo.withOpacity(0.4)),
        prefixIcon: Icon(icon, color: indigo.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.grey[50], // Very subtle off-white
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: indigo.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: indigo, width: 2),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isVisible! ? Icons.visibility : Icons.visibility_off,
                  color: indigo.withOpacity(0.6),
                ),
                onPressed: onVisibilityChanged,
              )
            : null,
      ),
      validator: validator,
    );
  }
}

// --- PARTICLE ENGINE ---

class ParticleEngine {
  final List<Particle> particles = [];
  final Random _rnd = Random();
  Offset _sensorForce = Offset.zero;

  void init(Size size) {
    particles.clear();
    // Create ~60 particles for performance/aesthetic balance
    for (int i = 0; i < 60; i++) {
      particles.add(
        Particle(
          position: Offset(
            _rnd.nextDouble() * size.width,
            _rnd.nextDouble() * size.height,
          ),
          velocity: Offset(
            (_rnd.nextDouble() - 0.5) * 0.5, // Slow drifting
            (_rnd.nextDouble() - 0.5) * 0.5,
          ),
          radius: _rnd.nextDouble() * 3 + 1, // 1-4px
        ),
      );
    }
  }

  void updateSensorForce(Offset force) {
    // Smooth interpolation could go here, but direct is responsive
    _sensorForce = force;
  }

  void explode() {
    for (var p in particles) {
      p.velocity += Offset(
        (_rnd.nextDouble() - 0.5) * 10,
        (_rnd.nextDouble() - 0.5) * 10,
      );
    }
  }

  void update(Size size) {
    for (var p in particles) {
      // Apply Velocity + Sensor Parallax
      // We add sensor force to position directly for parallax feel,
      // or to velocity for physics feel. Let's do velocity for "swarming".
      p.velocity += _sensorForce * 0.01;

      // Drag/Friction to stop infinite acceleration
      p.velocity *= 0.98;

      // Keep a minimum drift
      if (p.velocity.distance < 0.2) {
        p.velocity += Offset(
          (_rnd.nextDouble() - 0.5) * 0.02,
          (_rnd.nextDouble() - 0.5) * 0.02,
        );
      }

      p.position += p.velocity;

      // Wrap around screen
      if (p.position.dx < -50)
        p.position = Offset(size.width + 50, p.position.dy);
      if (p.position.dx > size.width + 50)
        p.position = Offset(-50, p.position.dy);
      if (p.position.dy < -50)
        p.position = Offset(p.position.dx, size.height + 50);
      if (p.position.dy > size.height + 50)
        p.position = Offset(p.position.dx, -50);
    }
  }
}

class Particle {
  Offset position;
  Offset velocity;
  double radius;

  Particle({
    required this.position,
    required this.velocity,
    required this.radius,
  });
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  static const indigo = Color(0xFF3F51B5);

  ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = indigo.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = indigo
          .withOpacity(0.15) // Faint connections
      ..strokeWidth = 1.0;

    // Draw Particles & Connections
    for (int i = 0; i < particles.length; i++) {
      final p1 = particles[i];

      // Draw Dot
      canvas.drawCircle(p1.position, p1.radius, dotPaint);

      // Connect to neighbors
      for (int j = i + 1; j < particles.length; j++) {
        final p2 = particles[j];
        final dx = p1.position.dx - p2.position.dx;
        final dy = p1.position.dy - p2.position.dy;
        final distSq = dx * dx + dy * dy;

        // Connect if close enough (within 100px approx => 10000 sq)
        if (distSq < 15000) {
          canvas.drawLine(p1.position, p2.position, linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => true;
}
