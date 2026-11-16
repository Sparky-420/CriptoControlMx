import 'package:cripto_control_mx/ai/portfolio_ai_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat sends previous turns and discloses portfolio data transfer', (tester) async {
    final histories = <List<Map<String, String>>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PortfolioAiChatScreen(
          onAsk: (question, history) async {
            histories.add(List<Map<String, String>>.of(history));
            return 'Respuesta a: $question';
          },
        ),
      ),
    );

    expect(find.textContaining('Privacidad:'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '¿Cómo va mi cartera?');
    await tester.tap(find.byTooltip('Enviar pregunta'));
    await tester.pumpAndSettle();

    expect(histories, hasLength(1));
    expect(histories.first, isEmpty);
    expect(find.text('Respuesta a: ¿Cómo va mi cartera?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '¿Y qué pasa si compro BTC?');
    await tester.tap(find.byTooltip('Enviar pregunta'));
    await tester.pumpAndSettle();

    expect(histories, hasLength(2));
    expect(histories.last, hasLength(2));
    expect(histories.last[0], <String, String>{
      'role': 'user',
      'content': '¿Cómo va mi cartera?',
    });
    expect(histories.last[1], <String, String>{
      'role': 'assistant',
      'content': 'Respuesta a: ¿Cómo va mi cartera?',
    });
    expect(find.text('Respuesta a: ¿Y qué pasa si compro BTC?'), findsOneWidget);
  });
}
