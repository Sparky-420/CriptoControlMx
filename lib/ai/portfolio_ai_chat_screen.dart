import 'package:flutter/material.dart';

/// Chat conversacional aislado: la aplicación le inyecta el analista con
/// contexto de cartera completo; esta pantalla nunca modifica registros.
final class PortfolioAiChatScreen extends StatefulWidget {
  const PortfolioAiChatScreen({super.key, required this.onAsk});
  final Future<String> Function(String question, List<Map<String, String>> history) onAsk;

  @override
  State<PortfolioAiChatScreen> createState() => _PortfolioAiChatScreenState();
}

final class _ChatMessage {
  const _ChatMessage({required this.text, required this.fromUser, this.failed = false});
  final String text;
  final bool fromUser;
  final bool failed;
}

final class _PortfolioAiChatScreenState extends State<PortfolioAiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[
    const _ChatMessage(
      text: 'Soy CriptoControl AI. Puedo analizar tus movimientos, posiciones, costos, comisiones, rendimiento y escenarios hipotéticos. ¿Qué quieres saber de tu cartera?\n\nPrivacidad: al enviar una pregunta, el contexto de tu cartera se transmite a OpenAI para procesarla. CriptoControlMx no guarda esta conversación como historial.',
      fromUser: false,
    ),
  ];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _sending) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text: question, fromUser: true));
      _sending = true;
    });
    _jumpToBottom();
    try {
      final history = _messages
          .take(_messages.length - 1)
          .where((message) => message.text != 'Soy CriptoControl AI. Puedo analizar tus movimientos, posiciones, costos, comisiones, rendimiento y escenarios hipotéticos. ¿Qué quieres saber de tu cartera?')
          .map((message) => <String, String>{
            'role': message.fromUser ? 'user' : 'assistant',
            'content': message.text,
          })
          .toList(growable: false);
      final answer = await widget.onAsk(question, history);
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage(text: answer, fromUser: false)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage(
        text: error.toString().replaceFirst('Exception: ', ''),
        fromUser: false,
        failed: true,
      )));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _jumpToBottom();
      }
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CriptoControl AI'),
            Text('Analista conversacional de tu cartera', style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (_sending && index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Analizando tu cartera…'),
                      ]),
                    ),
                  );
                }
                final message = _messages[index];
                return Align(
                  alignment: message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .88),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    decoration: BoxDecoration(
                      color: message.fromUser ? colors.primaryContainer : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                      border: message.failed ? Border.all(color: colors.error) : null,
                    ),
                    child: SelectableText(
                      message.text,
                      style: TextStyle(
                        color: message.fromUser ? colors.onPrimaryContainer : colors.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Pregunta lo que quieras sobre tu cartera…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar pregunta',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
