import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board_example/main.dart';

void main() {
  testWidgets('example app starts', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Modern Chess Board demo'), findsOneWidget);
  });
}
