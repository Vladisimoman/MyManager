import 'package:flutter/material.dart';

import '../../../core/category_icons.dart';
import '../../../data/database.dart';

/// Кругла іконка категорії в її кольорі.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 40});

  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = category == null ? Colors.grey : Color(category!.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        category == null ? Icons.help_outline : categoryIcon(category!.icon),
        color: color,
        size: size * 0.55,
      ),
    );
  }
}
