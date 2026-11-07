import 'package:flutter/material.dart';

/// Іконки категорій за текстовим ключем (ключ зберігається в базі).
/// Мапа константна, щоб Flutter міг вирізати невикористані іконки зі збірки.
/// Нові ключі можна лише додавати: старі вже записані в базі й на Drive.
const categoryIcons = <String, IconData>{
  // Стартові категорії
  'groceries': Icons.shopping_basket_outlined,
  'restaurant': Icons.restaurant_outlined,
  'transport': Icons.directions_bus_outlined,
  'home': Icons.home_outlined,
  'phone': Icons.wifi_outlined,
  'health': Icons.favorite_border,
  'clothes': Icons.checkroom_outlined,
  'fun': Icons.sports_esports_outlined,
  'subscriptions': Icons.subscriptions_outlined,
  'gift': Icons.card_giftcard_outlined,
  'education': Icons.school_outlined,
  'other': Icons.more_horiz,
  'salary': Icons.work_outline,
  'side': Icons.handyman_outlined,
  'refund': Icons.replay_outlined,
  // Додаткові (етап 6)
  'car': Icons.directions_car_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'taxi': Icons.local_taxi_outlined,
  'flight': Icons.flight_outlined,
  'travel': Icons.luggage_outlined,
  'coffee': Icons.local_cafe_outlined,
  'bar': Icons.local_bar_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'electronics': Icons.devices_outlined,
  'pets': Icons.pets_outlined,
  'kids': Icons.child_friendly_outlined,
  'sport': Icons.fitness_center_outlined,
  'beauty': Icons.spa_outlined,
  'pharmacy': Icons.medication_outlined,
  'electricity': Icons.bolt_outlined,
  'water': Icons.water_drop_outlined,
  'repair': Icons.build_outlined,
  'books': Icons.menu_book_outlined,
  'music': Icons.music_note_outlined,
  'movie': Icons.movie_outlined,
  'charity': Icons.volunteer_activism_outlined,
  'taxes': Icons.account_balance_outlined,
  'insurance': Icons.shield_outlined,
  'savings': Icons.savings_outlined,
  'investment': Icons.trending_up,
  'crypto': Icons.currency_bitcoin,
  'cash': Icons.payments_outlined,
  'card': Icons.credit_card_outlined,
  'business': Icons.business_center_outlined,
  'rent_income': Icons.apartment_outlined,
  'sale': Icons.sell_outlined,
};

IconData categoryIcon(String key) => categoryIcons[key] ?? Icons.label_outline;

/// Палітра для категорій (ARGB).
const categoryColors = <int>[
  0xFF43A047, 0xFF2E7D32, 0xFF00897B, 0xFF00ACC1, 0xFF1E88E5, 0xFF3949AB,
  0xFF5E35B1, 0xFF8E24AA, 0xFFD81B60, 0xFFE53935, 0xFFF4511E, 0xFFFB8C00,
  0xFFF9A825, 0xFF6D4C41, 0xFF546E7A, 0xFF757575,
];
