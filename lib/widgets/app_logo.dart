import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final BoxFit fit;
  final BoxShape shape;
  final BorderRadius? borderRadius;

  const AppLogo({
    super.key,
    this.size = 48,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.fit = BoxFit.contain,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : (borderRadius ?? BorderRadius.circular(size * 0.22)),
      ),
      child: Image.asset(
        'assets/app_logo.png',
        fit: fit,
      ),
    );
  }
}
