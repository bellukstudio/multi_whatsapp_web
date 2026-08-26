import 'package:flutter/material.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({
    super.key,
    required this.onFinished,
    this.iconAsset = 'assets/icon.png',
    this.appName,
    this.backgroundColor,
    this.iconSize = 140,
    this.minDuration = const Duration(milliseconds: 2200),
  });

  final VoidCallback onFinished;

  final String iconAsset;

  final String? appName;

  final Color? backgroundColor;

  final double iconSize;

  final Duration minDuration;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounceOffset;
  late final Animation<double> _fade;
  late final Animation<double> _textFade;

  bool _finishedCalled = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _bounceOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: -260.0,
          end: 24.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 38,
      ),

      TweenSequenceItem(
        tween: Tween(
          begin: 24.0,
          end: -60.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -60.0,
          end: 10.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 15,
      ),

      TweenSequenceItem(
        tween: Tween(
          begin: 10.0,
          end: -24.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -24.0,
          end: 4.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 10,
      ),

      TweenSequenceItem(
        tween: Tween(
          begin: 4.0,
          end: -8.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 6,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -8.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 6,
      ),
    ]).animate(_controller);

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.15, curve: Curves.easeIn),
    );

    _textFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
    );

    _controller.forward();
    _scheduleFinish();
  }

  void _scheduleFinish() async {
    final animationDone = _controller.forward().orCancel;
    final minWait = Future<void>.delayed(widget.minDuration);
    try {
      await Future.wait([animationDone, minWait]);
    } catch (_) {
      return;
    }
    if (!mounted || _finishedCalled) return;
    _finishedCalled = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? theme.scaffoldBackgroundColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _fade,
                  child: Transform.translate(
                    offset: Offset(0, _bounceOffset.value),
                    child: child,
                  ),
                ),
                if (widget.appName != null) ...[
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _textFade,
                    child: Text(
                      widget.appName!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },

          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.iconSize * 0.22),
            child: Image.asset(
              widget.iconAsset,
              width: widget.iconSize,
              height: widget.iconSize,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}
