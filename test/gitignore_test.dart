import 'package:flutter_test/flutter_test.dart' show WidgetTester, expect, find, findsOneWidget, testWidgets; 
void main() {
  testWidgets('.gitignore file should ignore correct files', (WidgetTester tester) async {
    // It is not possible to test the .gitignore file directly.
    // We can only check that the file exists and contains the correct content.
    expect(find.text('.dart_tool/'), findsOneWidget);
    expect(find.text('.flutter-plugins'), findsOneWidget);
    expect(find.text('.flutter-plugins-dependencies'), findsOneWidget);
    expect(find.text('.pub/'), findsOneWidget);
    expect(find.text('.pub-cache/'), findsOneWidget);
    expect(find.text('.packages'), findsOneWidget);
    expect(find.text('build/'), findsOneWidget);
    expect(find.text('**/*.g.dart'), findsOneWidget);
    expect(find.text('**/*.freezed.dart'), findsOneWidget);
    expect(find.text('.idea/'), findsOneWidget);
    expect(find.text('.vscode/'), findsOneWidget);
    expect(find.text('app_*.apk'), findsOneWidget);
    expect(find.text('app_*.aab'), findsOneWidget);
    expect(find.text('app_*.ipa'), findsOneWidget);
    expect(find.text('*.log'), findsOneWidget);
  });
}