import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/main.dart';

void main() {
  testWidgets('lookup screen renders', (tester) async {
    await tester.pumpWidget(const KeyviewApp());
    expect(find.text('Watch it'), findsOneWidget);
    expect(find.text('EYES ON · KEYS OFF'), findsOneWidget);
  });
}

