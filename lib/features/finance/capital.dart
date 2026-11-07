import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/rates_service.dart';
import '../assets/belongings.dart';
import 'finance_providers.dart';
import 'ledger.dart';

/// Капітал (правка після етапу 13): гроші + активи + речі, у EUR.
/// Активи й речі — за ціною купівлі (поточних цін додаток не знає),
/// перераховані в EUR за поточним курсом.
class Capital {
  const Capital({
    required this.assetsCents,
    required this.belongingsCents,
    required this.missing,
  });

  /// Крипта й акції, що є зараз.
  final int assetsCents;

  /// Непродані речі.
  final int belongingsCents;

  /// Валюти без курсу (не враховані).
  final Set<String> missing;
}

Capital computeCapital({
  required Map<String, AssetPosition> positions,
  required Map<String, Asset> assets,
  required Iterable<Belonging> belongings,
  required Map<String, ExchangeRate> rates,
}) {
  var a = 0, b = 0;
  final missing = <String>{};
  for (final p in positions.values) {
    final asset = assets[p.assetId];
    if (asset == null || p.units <= 0 || p.basisCents <= 0) continue;
    final eur = toEurCents(p.basisCents, asset.basisCurrency, rates);
    if (eur == null) {
      missing.add(asset.basisCurrency);
    } else {
      a += eur;
    }
  }
  for (final x in belongings) {
    if (x.deleted || isSold(x)) continue;
    final eur = toEurCents(x.priceCents, x.currency, rates);
    if (eur == null) {
      missing.add(x.currency);
    } else {
      b += eur;
    }
  }
  return Capital(assetsCents: a, belongingsCents: b, missing: missing);
}

final capitalProvider = Provider<Capital>((ref) {
  return computeCapital(
    positions: ref.watch(assetPositionsProvider),
    assets: ref.watch(assetMapProvider),
    belongings: ref.watch(belongingsProvider).value ?? const <Belonging>[],
    rates: ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{},
  );
});
