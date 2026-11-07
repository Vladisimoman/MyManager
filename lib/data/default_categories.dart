import 'database.dart';

class DefaultCategory {
  const DefaultCategory(this.id, this.type, this.name, this.icon, this.color);
  final String id;
  final EntryType type;
  final String name;
  final String icon;
  final int color;
}

/// Стартовий набір із ТЗ: 12 категорій витрат і 5 надходжень (+ 2 інвестиційні з етапу 8).
const defaultCategories = <DefaultCategory>[
  DefaultCategory('exp-groceries', EntryType.expense, 'Продукти', 'groceries', 0xFF43A047),
  DefaultCategory('exp-restaurant', EntryType.expense, 'Кафе й ресторани', 'restaurant', 0xFFFB8C00),
  DefaultCategory('exp-transport', EntryType.expense, 'Транспорт', 'transport', 0xFF1E88E5),
  DefaultCategory('exp-home', EntryType.expense, 'Житло й комунальні', 'home', 0xFF6D4C41),
  DefaultCategory('exp-phone', EntryType.expense, "Зв'язок та інтернет", 'phone', 0xFF00ACC1),
  DefaultCategory('exp-health', EntryType.expense, "Здоров'я", 'health', 0xFFE53935),
  DefaultCategory('exp-clothes', EntryType.expense, 'Одяг', 'clothes', 0xFF8E24AA),
  DefaultCategory('exp-fun', EntryType.expense, 'Розваги', 'fun', 0xFFD81B60),
  DefaultCategory('exp-subscriptions', EntryType.expense, 'Підписки', 'subscriptions', 0xFF3949AB),
  DefaultCategory('exp-gift', EntryType.expense, 'Подарунки', 'gift', 0xFFF4511E),
  DefaultCategory('exp-education', EntryType.expense, 'Освіта', 'education', 0xFF00897B),
  DefaultCategory('exp-other', EntryType.expense, 'Інше', 'other', 0xFF757575),
  DefaultCategory('inc-salary', EntryType.income, 'Зарплата', 'salary', 0xFF2E7D32),
  DefaultCategory('inc-side', EntryType.income, 'Підробіток', 'side', 0xFF00897B),
  DefaultCategory('inc-gift', EntryType.income, 'Подарунки', 'gift', 0xFFF4511E),
  DefaultCategory('inc-refund', EntryType.income, 'Повернення коштів', 'refund', 0xFF1E88E5),
  DefaultCategory('inc-other', EntryType.income, 'Інше', 'other', 0xFF757575),
  // Етап 8: різниця при продажі активу. Створюються автоматично.
  DefaultCategory('inc-invest', EntryType.income, 'Інвестиційний прибуток', 'investment', 0xFF43A047),
  DefaultCategory('exp-invest', EntryType.expense, 'Інвестиційний збиток', 'investment', 0xFFE53935),
  // Етап 9: гроші від продажу речей (пасивів). Видима — можна обирати й вручну.
  DefaultCategory('inc-sale', EntryType.income, 'Продаж речей', 'sale', 0xFF7CB342),
];
