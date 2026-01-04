import 'package:flutter/material.dart';

class DraggableChatBubble extends StatefulWidget {
  final VoidCallback onTap;
  final double initialY;

  const DraggableChatBubble({
    super.key,
    required this.onTap,
    this.initialY = 100,
  });

  @override
  State<DraggableChatBubble> createState() => _DraggableChatBubbleState();
}

class _DraggableChatBubbleState extends State<DraggableChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  double _left = 0; // Will be set in init
  double _top = 0;
  bool _initialized = false;

  // Design constants
  final double _bubbleSize = 60.0;
  final double _margin = 16.0;

  @override
  void initState() {
    super.initState();
    _top = widget.initialY;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controller.addListener(() {
      setState(() {
        _left = _animation.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final size = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;
      _left =
          size.width - _bubbleSize - _margin; // Initial position: Right side

      // Initial position: Bottom right, just above where the navbar/FAB area starts
      // Navbar height is approx 80 + bottom padding. We give it extra clearance.
      _top = size.height - padding.bottom - 100 - _bubbleSize - _margin;

      _initialized = true;
    }
  }

  void _snapToSide(double screenWidth) {
    final centerX = _left + (_bubbleSize / 2);
    final targetX = centerX < screenWidth / 2
        ? _margin
        : screenWidth - _bubbleSize - _margin;

    _animation = Tween<double>(
      begin: _left,
      end: targetX,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        Positioned(
          left: _left,
          top: _top,
          child: GestureDetector(
            onPanStart: (_) {
              _controller.stop();
            },
            onPanUpdate: (details) {
              setState(() {
                _left += details.delta.dx;
                _top += details.delta.dy;

                // Clamp to screen bounds
                _top = _top.clamp(
                  MediaQuery.of(context).padding.top + _margin,
                  size.height - _bubbleSize - _margin - 80, // Avoid nav bar
                );
              });
            },
            onPanEnd: (details) {
              // Add simple velocity check if needed, but simple snap is often cleaner
              _snapToSide(size.width);
            },
            onTap: widget.onTap,
            child: Hero(
              tag: 'quick_chat_bubble',
              child: Material(
                color: Colors
                    .transparent, // Material handles the clip/color during flight
                child: Container(
                  width: _bubbleSize,
                  height: _bubbleSize,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // TODO: Show user avatar or unread count
                      const Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.white,
                        size: 28,
                      ),
                    ],
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
