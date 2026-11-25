import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_lock/main.dart';

void main() {
  testWidgets('ScrollLockApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ScrollLockApp());

    // Verify title is rendered
    expect(find.text('ScrollLock'), findsOneWidget);
  });
}
