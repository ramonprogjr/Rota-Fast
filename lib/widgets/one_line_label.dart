import 'package:flutter/material.dart';

/// Rótulo de botão que nunca quebra em duas linhas: em telas estreitas a
/// fonte diminui um pouco em vez de empurrar o texto para baixo.
class OneLineLabel extends StatelessWidget {
  const OneLineLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}
