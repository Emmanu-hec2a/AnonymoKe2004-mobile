import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:anonymoke/app.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('auth screen renders the approved passwordless entry points', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AnonymoKEApp()));
    await tester.pumpAndSettle();

    expect(find.text('Meet the person\nfirst.'), findsOneWidget);
    expect(find.text('Send magic link'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
  });
}
