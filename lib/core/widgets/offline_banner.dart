import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bitemates/core/services/connectivity_service.dart';

class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _slideAnim;
  StreamSubscription<bool>? _sub;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _isOnline = ConnectivityService().isOnline;
    if (!_isOnline) _animController.value = 1.0;

    _sub = ConnectivityService().onConnectivityChanged.listen((online) {
      if (!mounted) return;
      setState(() => _isOnline = online);
      if (!online) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizeTransition(
          sizeFactor: _slideAnim,
          axisAlignment: -1,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              color: const Color(0xFF1A1A2E),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 6,
                bottom: 8,
                left: 16,
                right: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off_rounded, size: 14, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    'No internet connection',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
