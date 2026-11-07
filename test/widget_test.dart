import 'package:flutter_test/flutter_test.dart';

import 'package:herotrak/presentation/app.dart';

void main() {
  testWidgets('HeroTrak shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const HeroTrakApp());

    expect(find.text('HeroTrak'), findsOneWidget);
  });
}
