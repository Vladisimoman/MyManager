import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';

/// Поле вводу початкового балансу (EUR, можна з мінусом).
class InitialBalanceField extends StatelessWidget {
  const InitialBalanceField({
    super.key,
    required this.controller,
    this.errorText,
    this.autofocus = false,
    this.currency = baseCurrency,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool autofocus;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s\-−]')),
      ],
      style: Theme.of(context).textTheme.headlineSmall,
      decoration: InputDecoration(
        labelText: 'Початковий баланс',
        helperText: 'У $currency. Якщо мінус (борг, овердрафт) — напр. -150',
        errorText: errorText,
        suffixText: currencySymbol(currency),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Діалог зміни початкового балансу. Повертає нову суму або null (скасовано).
Future<int?> showInitialBalanceDialog(
  BuildContext context, {
  required int currentCents,
  String currency = baseCurrency,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) =>
        _InitialBalanceDialog(initialCents: currentCents, currency: currency),
  );
}

/// Діалог сам володіє полем вводу: так воно живе, доки діалог анімовано закривається.
class _InitialBalanceDialog extends StatefulWidget {
  const _InitialBalanceDialog({
    required this.initialCents,
    required this.currency,
  });
  final int initialCents;
  final String currency;

  @override
  State<_InitialBalanceDialog> createState() => _InitialBalanceDialogState();
}

class _InitialBalanceDialogState extends State<_InitialBalanceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialCents == 0
        ? ''
        : signedCentsToInput(widget.initialCents),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Початковий баланс, ${widget.currency}'),
      content: InitialBalanceField(
        controller: _controller,
        errorText: _error,
        autofocus: true,
        currency: widget.currency,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Скасувати'),
        ),
        TextButton(
          onPressed: () {
            final text = _controller.text.trim();
            final cents = text.isEmpty ? 0 : parseSignedAmountToCents(text);
            if (cents == null) {
              setState(() => _error = 'Невірна сума, напр. 1250,50');
              return;
            }
            Navigator.pop(context, cents);
          },
          child: const Text('Зберегти'),
        ),
      ],
    );
  }
}
