import 'package:flutter_test/flutter_test.dart';
import 'package:photo_organizer_flutter/main.dart';

void main() {
  testWidgets('HomeScreen button exists', (WidgetTester tester) async {
    // Build the app
    await tester.pumpWidget(const PhotoOrganizerApp());

    // Wait for frames to settle
    await tester.pumpAndSettle();

    // Verify the HomeScreen button exists
    expect(find.text('Open Photo Explorer'), findsOneWidget);
  });
}
