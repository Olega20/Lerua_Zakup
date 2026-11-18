import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app.dart';

void main() {
  testWidgets('Lerua Zakup app starts without the Flutter demo counter', (tester) async {
    await tester.pumpWidget(const LeruaZakupApp());

    expect(find.text('Lerua Zakup'), findsOneWidget);
    expect(find.text('Flutter Demo Home Page'), findsNothing);
    expect(find.text('You have pushed the button this many times:'), findsNothing);
  });
}
