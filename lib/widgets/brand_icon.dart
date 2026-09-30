import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Ícono de marca en SVG (assets/icons/), teñido a un solo tono para que
/// combine con el resto de la UI — sirve tanto para la barra de
/// navegación como para las tarjetas de Home, cambiando solo el color.
class BrandIcon extends StatelessWidget {
  final String asset;
  final double size;
  final Color color;

  const BrandIcon(this.asset, {super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/$asset',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
