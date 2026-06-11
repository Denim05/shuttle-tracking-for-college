import 'package:flutter_test/flutter_test.dart';
import 'package:sistecchalo/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SISTecChalo Brand & Initial State Smoke Test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SISTecChaloApp());

    // Check for "SISTecChalo" brand title on splash screen
    expect(find.text('SISTecChalo'), findsOneWidget);
  });
}

