import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

class PinPadWidget extends StatefulWidget {
  final String title;
  final String? profileName;
  final Function(String) onCompleted;
  final VoidCallback onCancel;

  const PinPadWidget({
    super.key,
    required this.title,
    this.profileName,
    required this.onCompleted,
    required this.onCancel,
  });

  @override
  State<PinPadWidget> createState() => PinPadWidgetState();
}

class PinPadWidgetState extends State<PinPadWidget> with SingleTickerProviderStateMixin {
  String _currentPin = "";
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _shakeController.reverse();
        }
      });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _handleKey(String key) {
    if (_currentPin.length < 4) {
      setState(() {
        _currentPin += key;
      });
      if (_currentPin.length == 4) {
        Future.delayed(const Duration(milliseconds: 200), () {
          widget.onCompleted(_currentPin);
        });
      }
    }
  }

  void triggerShake() {
    _shakeController.forward();
    setState(() {
      _currentPin = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_shakeAnimation.value * (_shakeController.value > 0.5 ? 1 : -1), 0),
              child: child,
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70,
                ),
              ),
              if (widget.profileName != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.profileName!,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
              const SizedBox(height: 40),
              
              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      color: index < _currentPin.length ? Colors.white : Colors.transparent,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 60),

              // PIN Grid
              Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 25,
                  children: [
                    ...List.generate(9, (index) => _PinKey(
                      label: "${index + 1}", 
                      onTap: () => _handleKey("${index + 1}"),
                      autofocus: index == 0,
                    )),
                    const SizedBox.shrink(),
                    _PinKey(label: "0", onTap: () => _handleKey("0")),
                    const SizedBox.shrink(),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              
              TextButton(
                onPressed: widget.onCancel,
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  const _PinKey({required this.label, required this.onTap, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return _TVFocusWrapper(
      autofocus: autofocus,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w300,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrapper para manejar el foco en Android TV / Video Beam (Reutilizable)
class _TVFocusWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;

  const _TVFocusWrapper({
    required this.child,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_TVFocusWrapper> createState() => _TVFocusWrapperState();
}

class _TVFocusWrapperState extends State<_TVFocusWrapper> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
            (event.logicalKey == LogicalKeyboardKey.select || 
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _isFocused ? const Color(0xFFBB86FC) : Colors.transparent,
                width: 3,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFFBB86FC).withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
