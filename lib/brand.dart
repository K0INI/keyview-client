import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// KŌINIkeyview brand tokens — extracted live from keys.koini.io (2026-07-17).
/// keys.koini.io is the definitive style reference. Do not restyle.
abstract final class Brand {
  static const noir = Color(0xFF0B0B0E); // page background
  static const surface = Color(0xFF1B1916); // cards
  static const surface2 = Color(0xFF23201A); // raised / hover
  static const warm = Color(0xFFFFFDF5); // primary text
  static const warm2 = Color(0xFFB7B2A6); // secondary text
  static const warm3 = Color(0xFF7C776C); // muted
  static const amber = Color(0xFFF8A800); // accent
  static const amberInk = Color(0xFF1C1402); // text on amber
  static const up = Color(0xFF6FB48E);
  static const down = Color(0xFFE0795A);
  static Color get line => warm.withValues(alpha: .07); // hairlines

  /// Body font: Gotham on the site; Montserrat is the licensed-free equivalent.
  static TextTheme textTheme(TextTheme base) =>
      GoogleFonts.montserratTextTheme(base).apply(
        bodyColor: warm,
        displayColor: warm,
      );

  /// Letterspaced geometric labels ("EYES ON · KEYS OFF") use Jost.
  static TextStyle micro({Color color = warm3, double size = 11}) =>
      GoogleFonts.jost(
        fontSize: size,
        letterSpacing: size * .32,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static ThemeData theme() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: noir,
      colorScheme: base.colorScheme.copyWith(
        primary: amber,
        onPrimary: amberInk,
        surface: surface,
        onSurface: warm,
      ),
      textTheme: textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: noir,
        foregroundColor: warm,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: warm.withValues(alpha: .07)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: amberInk,
          textStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

/// The keyhole mark (bulb over a thin-stroke circle). Mark only at icon scale.
class KeyholeMark extends StatelessWidget {
  final double size;
  final Color color;
  const KeyholeMark({super.key, this.size = 22, this.color = Brand.warm});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * .8, size), painter: _KeyholePainter(color));
}

class _KeyholePainter extends CustomPainter {
  final Color color;
  _KeyholePainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * .055;
    canvas.drawCircle(Offset(w / 2, h * .12), h * .075, fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w / 2, h * .26), width: h * .08, height: h * .14),
            Radius.circular(h * .04)),
        fill);
    canvas.drawCircle(Offset(w / 2, h * .66), h * .27, stroke);
  }

  @override
  bool shouldRepaint(covariant _KeyholePainter old) => old.color != color;
}
