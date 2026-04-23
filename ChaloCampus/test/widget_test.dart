import 'package:flutter_test/flutter_test.dart';
import 'package:chalocampus/main.dart';

void main() {
  testWidgets('ChaloCampus Brand & Initial State Smoke Test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ChaloCampusApp());

    // Wait for auto-login check to settle
    await tester.pumpAndSettle();

    // Check for "SHUTTLE TRACKER" subtitle
    expect(find.text('SHUTTLE TRACKER'), findsOneWidget);
    expect(find.text('SHUTTLE TRACKER'), findsOneWidget);

    // Check for the identity selector header
    expect(find.text('IDENTIFY AS'), findsOneWidget);
    
    // Check for the primary sign in button
    expect(find.text('SIGN IN'), findsOneWidget);
  });
}
