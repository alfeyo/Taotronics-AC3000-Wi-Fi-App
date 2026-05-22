import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/main.dart';

void main() {
  testWidgets('App launches correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const TTRouterApp());
    expect(find.text('TT Router'), findsOneWidget);
  });
}
