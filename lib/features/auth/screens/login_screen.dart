import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/auth/screens/signup_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Force Light Theme for this screen
    return Theme(
      data: AppTheme.lightTheme,
      child: const Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset:
            false, // Handle keyboard manually or avoid resize
        body: PhysicsLoginBody(),
      ),
    );
  }
}

class PhysicsLoginBody extends StatefulWidget {
  const PhysicsLoginBody({super.key});

  @override
  State<PhysicsLoginBody> createState() => _PhysicsLoginBodyState();
}

class _PhysicsLoginBodyState extends State<PhysicsLoginBody>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final _physicsEngine = PhysicsEngine();
  StreamSubscription? _accelerometerSub;

  // Form State
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  // Layout Logic
  final GlobalKey _cardKey = GlobalKey();
  Rect? _staticBodyRect; // The Login Card

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _initSensors();

    // Initial Spawn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _physicsEngine.spawnInitalNodes(MediaQuery.of(context).size);
      _updateStaticBody();
    });
  }

  void _initSensors() {
    _accelerometerSub = accelerometerEventStream().listen((event) {
      // Sensitivity factor
      const sensitivity = 2.0;
      // Invert X for natural feel (tilt left = slide left)
      // Y force adds to gravity or counteracts it
      _physicsEngine.updateSensorForce(
        Offset(-event.x * sensitivity, event.y * sensitivity),
      );
    });
  }

  void _onTick(Duration elapsed) {
    // Update Static Body every frame just in case of layout shifts (keyboard)
    // Optimization: only do this if size changes
    _updateStaticBody();

    _physicsEngine.update(MediaQuery.of(context).size, _staticBodyRect);
    setState(() {}); // Redraw
  }

  void _updateStaticBody() {
    final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      // Define the "Roof" of the card as the static collision body
      // We extend it strictly to the bottom of screen to treat it as solid block
      final screenHeight = MediaQuery.of(context).size.height;
      _staticBodyRect = Rect.fromLTWH(
        position.dx,
        position.dy,
        size.width,
        screenHeight - position.dy, // Extends to bottom
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _accelerometerSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    // Tap Effect: Explosion!
    _physicsEngine.explode();

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Login failed'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Physics Layer (Background)
        CustomPaint(
          size: Size.infinite,
          painter: PhysicsPainter(_physicsEngine.nodes),
        ),

        // 2. Foreground UI (Login Card)
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    key: _cardKey,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Branding
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'BITEMATES',
                                style: GoogleFonts.outfit(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('👋', style: TextStyle(fontSize: 24)),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Email
                          TextFormField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              hintText: 'Email',
                              prefixIcon: const Icon(Icons.email_outlined),
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (v) =>
                                v!.contains('@') ? null : 'Invalid email',
                          ),
                          const SizedBox(height: 16),

                          // Password
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () => setState(
                                  () =>
                                      _isPasswordVisible = !_isPasswordVisible,
                                ),
                              ),
                            ),
                            validator: (v) =>
                                v!.length > 5 ? null : 'Short password',
                          ),
                          const SizedBox(height: 24),

                          // Login Button
                          Consumer<AuthProvider>(
                            builder: (context, auth, _) {
                              return ElevatedButton(
                                onPressed: auth.isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.accentColor,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: auth.isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Enter the Hub',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              );
                            },
                          ),

                          // Socials
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              'or continue with',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _SocialButton(icon: Icons.apple, onTap: () {}),
                              const SizedBox(width: 16),
                              _SocialButton(
                                icon: Icons.g_mobiledata,
                                onTap: () {},
                              ),
                            ],
                          ),

                          // Sign Up
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "New here? ",
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SignupScreen(),
                                  ),
                                ),
                                child: Text(
                                  "Join",
                                  style: TextStyle(
                                    color: AppTheme.accentColor,
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
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SocialButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Indigo Circle for buttons too? User said Indigo circles for emojis
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(icon, color: Colors.black),
      ),
    );
  }
}

// --- PHYSICS ENGINE ---

class PhysicsEngine {
  final List<PhysicsNode> nodes = [];
  final Random _rnd = Random();
  Offset _sensorForce = Offset.zero;

  // Emojis: Hiking, Basketball, Food, etc.
  final List<String> _emojis = [
    '🏀', '⚽', '🎾', '🚵', '🧗', '🏄', // Activities
    '🍔', '🍕', '🌭', '🍺', '☕', // Food
    '🌮', '🍦', '🍩', '🥑',
  ];

  void updateSensorForce(Offset force) {
    _sensorForce = force;
  }

  void spawnInitalNodes(Size screenSize) {
    nodes.clear();
    // Spawn 15-20 nodes
    for (int i = 0; i < 20; i++) {
      nodes.add(
        PhysicsNode(
          position: Offset(
            _rnd.nextDouble() * screenSize.width,
            -_rnd.nextDouble() * 500 - 50, // Start above screen
          ),
          velocity: Offset(
            (_rnd.nextDouble() - 0.5) * 5, // Random X spread
            _rnd.nextDouble() * 5, // Initial drop speed
          ),
          emoji: _emojis[_rnd.nextInt(_emojis.length)],
          radius: 24.0 + _rnd.nextDouble() * 10, // Random size
        ),
      );
    }
  }

  void explode() {
    // Push everything UP and OUT
    for (var node in nodes) {
      node.velocity = Offset(
        (node.velocity.dx + (node.position.dx % 10 - 5)) * 5,
        -20.0 - _rnd.nextDouble() * 10, // Big Jump
      );
    }
  }

  void update(Size size, Rect? staticBody) {
    const gravity = 0.5;
    const friction = 0.98;
    const bounce = -0.7;

    for (var node in nodes) {
      // 1. Apply Forces
      node.velocity += Offset(_sensorForce.dx, gravity + _sensorForce.dy);
      node.velocity *= friction;
      node.position += node.velocity;

      // 2. Screen Collisions
      // Floor
      if (node.position.dy > size.height - node.radius) {
        node.position = Offset(node.position.dx, size.height - node.radius);
        node.velocity = Offset(node.velocity.dx, node.velocity.dy * bounce);
      }
      // Walls
      if (node.position.dx < node.radius) {
        node.position = Offset(node.radius, node.position.dy);
        node.velocity = Offset(node.velocity.dx * bounce, node.velocity.dy);
      }
      if (node.position.dx > size.width - node.radius) {
        node.position = Offset(size.width - node.radius, node.position.dy);
        node.velocity = Offset(node.velocity.dx * bounce, node.velocity.dy);
      }

      // 3. Static Body Collision (Login Card) - DISABLED per user request
      // if (staticBody != null) {
      //   _resolveStaticCollision(node, staticBody, bounce);
      // }
    }

    // 4. Node-to-Node Collision (Optional, expensive but nice)
    // skipping for performance/simplicity or can add cheap version
    _resolveNodeCollisions();
  }

  void _resolveStaticCollision(PhysicsNode node, Rect body, double bounce) {
    // Simple AABB-ish check for "Landing on roof" or "Hitting side"
    // We treat the body as a solid block.

    // Check overlap
    final circleRect = Rect.fromCircle(
      center: node.position,
      radius: node.radius,
    );
    if (!circleRect.overlaps(body)) return;

    // Determine nearest edge

    // Since we only really care about landing ON TOP or bouncing OFF SIDES:
    // We prioritize Top collision if barely overlapping Y

    if (node.position.dy < body.top + node.radius &&
        node.position.dx > body.left &&
        node.position.dx < body.right) {
      // Top Hit
      node.position = Offset(node.position.dx, body.top - node.radius);
      node.velocity = Offset(node.velocity.dx, node.velocity.dy * bounce);

      // SLIDE OFF: Push away from center if sitting on top
      if (node.position.dx < body.center.dx) {
        node.velocity -= const Offset(2.0, 0); // Push Left
      } else {
        node.velocity += const Offset(2.0, 0); // Push Right
      }
    } else if (node.position.dx < body.center.dx) {
      // Left Hit (push out left)
      if (node.position.dx > body.left - node.radius) {
        // Penetrated
        node.position = Offset(body.left - node.radius, node.position.dy);
        node.velocity = Offset(node.velocity.dx * bounce, node.velocity.dy);
      }
    } else {
      // Right Hit
      if (node.position.dx < body.right + node.radius) {
        node.position = Offset(body.right + node.radius, node.position.dy);
        node.velocity = Offset(node.velocity.dx * bounce, node.velocity.dy);
      }
    }
  }

  void _resolveNodeCollisions() {
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final n1 = nodes[i];
        final n2 = nodes[j];
        final dx = n2.position.dx - n1.position.dx;
        final dy = n2.position.dy - n1.position.dy;
        final distSq = dx * dx + dy * dy;
        final radSum = n1.radius + n2.radius;

        if (distSq < radSum * radSum && distSq > 0) {
          final dist = sqrt(distSq);
          final overlap = radSum - dist;
          final nx = dx / dist;
          final ny = dy / dist;

          // Separate
          final separation = overlap * 0.5;
          n1.position -= Offset(nx * separation, ny * separation);
          n2.position += Offset(nx * separation, ny * separation);

          // Bounce (simplistic exchange)
          // Just swapping velocities slightly or creating impulse
          // Real physics is complex, let's just push them apart for "stacking" feel
        }
      }
    }
  }
}

class PhysicsNode {
  Offset position;
  Offset velocity;
  final String emoji;
  final double radius;

  PhysicsNode({
    required this.position,
    required this.velocity,
    required this.emoji,
    required this.radius,
  });
}

class PhysicsPainter extends CustomPainter {
  final List<PhysicsNode> nodes;
  PhysicsPainter(this.nodes);

  @override
  void paint(Canvas canvas, Size size) {
    // User requested Indigo circles
    final paint = Paint()..color = Colors.indigo;

    for (var node in nodes) {
      // Draw Circle
      canvas.drawCircle(node.position, node.radius, paint);

      // Draw Emoji
      final textSpan = TextSpan(
        text: node.emoji,
        style: TextStyle(
          fontSize: node.radius * 1.2, // Fit inside
          height: 1, // Fix text height issues
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        node.position - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PhysicsPainter oldDelegate) => true; // Always repaint for physics
}
