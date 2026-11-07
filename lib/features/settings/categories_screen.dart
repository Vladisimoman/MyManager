import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../data/database.dart';
import '../finance/finance_providers.dart';
import '../finance/widgets/category_avatar.dart';

final manageableCategoriesProvider = StreamProvider.family<List<Category>, EntryType>(
  (ref, type) => ref.watch(databaseProvider).watchManageableCategories(type),
);

/// Керування категоріями: дві вкладки, «+» додає нову, тап — редагування.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Категорії'),
            bottom: const TabBar(tabs: [Tab(text: 'Витрати'), Tab(text: 'Надходження')]),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Нова категорія',
            onPressed: () {
              final type = DefaultTabController.of(context).index == 0
                  ? EntryType.expense
                  : EntryType.income;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CategoryEditScreen(type: type),
              ));
            },
            child: const Icon(Icons.add),
          ),
          body: const TabBarView(
            children: [
              _CategoryList(type: EntryType.expense),
              _CategoryList(type: EntryType.income),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.type});
  final EntryType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ref.watch(manageableCategoriesProvider(type)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Помилка: $e')),
          data: (list) => ListView(
            padding: const EdgeInsets.only(bottom: 88, top: 8),
            children: [
              // Інвестиційний прибуток / збиток створюються автоматично — не показуємо.
              for (final c in list.where((c) => !c.id.endsWith('-invest')))
                Opacity(
                  opacity: c.hidden ? 0.5 : 1,
                  child: ListTile(
                    leading: CategoryAvatar(category: c),
                    title: Text(c.name),
                    subtitle: c.hidden
                        ? Text('Прихована', style: TextStyle(color: scheme.onSurfaceVariant))
                        : null,
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CategoryEditScreen(type: type, category: c),
                    )),
                  ),
                ),
            ],
          ),
        );
  }
}

/// Нова категорія ([category] == null) або редагування наявної.
class CategoryEditScreen extends ConsumerStatefulWidget {
  const CategoryEditScreen({super.key, required this.type, this.category});

  final EntryType type;
  final Category? category;

  @override
  ConsumerState<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends ConsumerState<CategoryEditScreen> {
  late final TextEditingController _name;
  late String _icon;
  late int _color;
  late bool _hidden;
  String? _nameError;
  bool _saving = false;

  bool get _isNew => widget.category == null;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _name = TextEditingController(text: c?.name ?? '');
    _icon = c?.icon ?? 'other';
    _color = c?.color ?? categoryColors.first;
    _hidden = c?.hidden ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final preview = Category(
      id: '',
      type: widget.type,
      name: _name.text,
      icon: _icon,
      color: _color,
      sortOrder: 0,
      hidden: _hidden,
      updatedAt: DateTime(2000),
      deleted: false,
    );

    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Нова категорія' : 'Категорія')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                CategoryAvatar(category: preview, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: _isNew,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Назва',
                      errorText: _nameError,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _nameError = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Колір', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in categoryColors)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: c == _color
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Іконка', style: text.titleMedium),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final key in categoryIcons.keys)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = key),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: key == _icon ? Color(_color).withValues(alpha: 0.15) : null,
                        border: Border.all(
                          color: key == _icon ? Color(_color) : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        categoryIcons[key],
                        color: key == _icon ? Color(_color) : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (!_isNew) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Приховати'),
                subtitle: const Text(
                  'Не показувати під час додавання записів. Старі записи й статистика зберігаються.',
                ),
                value: _hidden,
                onChanged: (v) => setState(() => _hidden = v),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Зберегти', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введи назву');
      return;
    }
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    try {
      if (_isNew) {
        await db.addCategory(type: widget.type, name: name, icon: _icon, color: _color);
      } else {
        await db.updateCategory(
          widget.category!.id,
          name: name,
          icon: _icon,
          color: _color,
          hidden: _hidden,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не вдалося зберегти категорію: $e')),
      );
    }
  }
}
