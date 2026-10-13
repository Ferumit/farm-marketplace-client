import 'package:et_core/et_core.dart';
import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'lot_screen.dart';
import 'notifications_screen.dart';

/// The catalogue - leadership's windows 1.1 and 1.2, as the website now does them.
///
/// Meat first, farm second: a buyer arrives wanting beef or horse, not a particular hozyaystvo.
/// The farm is shown on every carcass and has its own page, but it is not what is chosen first.
class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key, this.initialMeat});

  final String? initialMeat;

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  final _repo = CatalogueRepo();
  final _search = TextEditingController();

  CatalogueSnapshot? _data;
  bool _loading = true;
  String? _error;

  String? _meat;
  bool _onlyAvailable = true;

  @override
  void initState() {
    super.initState();
    _meat = widget.initialMeat;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить каталог. Проверьте связь.';
      });
    }
  }

  List<Lot> get _filtered {
    final data = _data;
    if (data == null) return const [];
    final query = _search.text.trim().toLowerCase();
    return data.lots.where((lot) {
      if (_meat != null && data.meatTypeOf(lot) != _meat) return false;
      if (_onlyAvailable && bestOffer(lot) == null) return false;
      if (query.isEmpty) return true;
      // Meat and region belong in the search too: "конина" is the most obvious thing to type and
      // it appears in none of the stored fields - only as a label.
      final animal = data.firstAnimalOf(lot);
      final haystack = [
        lot.name,
        lot.description,
        lot.location ?? '',
        animal?.breed ?? '',
        data.farmOf(lot)?.displayName ?? '',
        meatLabel[data.meatTypeOf(lot)] ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  /// The bell counts what this buyer has not read. Signed out, there is nothing to count.
  Stream<int>? _unread(BuildContext context) {
    final uid = context.watch<AuthService>().uid;
    return uid == null ? null : NotificationsRepo().unreadCount(uid);
  }

  @override
  Widget build(BuildContext context) {
    final lots = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мясо от хозяйств'),
        actions: [
          EtBell(
            unread: _unread(context),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(EtShape.gutter, 0, EtShape.gutter, 28),
          children: [
            _filters(),
            const SizedBox(height: EtShape.gap),
            if (_loading) ...[
              const EtSkeleton(height: 210),
              const SizedBox(height: EtShape.gap),
              const EtSkeleton(height: 210),
            ] else if (_error != null)
              EtEmpty(
                title: 'Каталог не загрузился',
                text: _error,
                icon: Icons.cloud_off,
                action: FilledButton(onPressed: _load, child: const Text('Повторить')),
              )
            else if (lots.isEmpty)
              const EtEmpty(
                title: 'Пока ничего не найдено',
                text: 'Попробуйте снять фильтры — или загляните позже: хозяйства выставляют туши каждую неделю.',
                icon: Icons.search_off,
                illustrated: true,
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${lots.length} ${pluralRu(lots.length, 'туша', 'туши', 'туш')} в продаже',
                  style: context.texts.bodySmall?.copyWith(color: context.et.inkDim),
                ),
              ),
              for (var i = 0; i < lots.length; i++)
                EtReveal(
                  index: i,
                  child: LotCard(
                    lot: lots[i],
                    farm: _data!.farmOf(lots[i]),
                    animal: _data!.firstAnimalOf(lots[i]),
                    meatType: _data!.meatTypeOf(lots[i]),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Column(
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Порода, хозяйство, регион',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _chip('Всё мясо', _meat == null, () => setState(() => _meat = null)),
            const SizedBox(width: 8),
            _chip('Говядина', _meat == 'cattle', () => setState(() => _meat = 'cattle')),
            const SizedBox(width: 8),
            _chip('Конина', _meat == 'horse', () => setState(() => _meat = 'horse')),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Checkbox(
              value: _onlyAvailable,
              onChanged: (value) => setState(() => _onlyAvailable = value ?? true),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _onlyAvailable = !_onlyAvailable),
                child: Text(
                  'Только то, что можно заказать',
                  style: context.texts.bodySmall?.copyWith(color: context.et.inkDim),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final c = context.et;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.greenSurface : c.surfaceRaised,
            borderRadius: BorderRadius.circular(EtShape.radiusPill),
            border: Border.all(color: selected ? c.greenSurface : c.line),
          ),
          child: Text(
            label,
            style: context.texts.labelLarge?.copyWith(
              color: selected ? c.onGreen : c.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// One carcass in a list: what it is, whose it is, what is left of it and what a half costs.
class LotCard extends StatelessWidget {
  const LotCard({
    super.key,
    required this.lot,
    required this.farm,
    required this.animal,
    required this.meatType,
  });

  final Lot lot;
  final Partner? farm;
  final Animal? animal;
  final String meatType;

  @override
  Widget build(BuildContext context) {
    final c = context.et;
    final offer = bestOffer(lot);
    final taken = lot.totalShares == 0 ? 0.0 : lot.bookedShares / lot.totalShares;

    return Padding(
      padding: const EdgeInsets.only(bottom: EtShape.gap),
      child: EtCard(
        padding: EdgeInsets.zero,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LotScreen(lotId: lot.id)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EtHero(
              label: meatLabel[meatType] ?? 'Мясо',
              meatType: meatType,
              imageUrl: lot.imageUrl,
              note: lot.totalWeight > 0 ? weightLabel(lot.totalWeight) : null,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lot.name, style: context.texts.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    [
                      farm?.displayName ?? '',
                      lot.location ?? '',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: context.texts.bodySmall?.copyWith(color: c.inkDim),
                  ),
                  const SizedBox(height: 10),
                  // Вид мяса не повторяется плашкой: он крупно написан на самой шапке карточки.
                  // Остаются факты, которых там нет: порода и проверенные бумаги.
                  if (farm?.certified == true || animal?.breed.isNotEmpty == true)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (animal?.breed.isNotEmpty == true) _tag(context, animal!.breed),
                        if (farm?.certified == true)
                          _tag(context, 'сертификаты', accent: true, icon: Icons.verified_outlined),
                      ],
                    ),
                  const SizedBox(height: 12),
                  EtProgress(
                    percent: taken,
                    label: availabilityLabel(lot),
                    trailing: taken == 0 ? null : 'занято ${(taken * 100).round()} %',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              offer == null ? 'Нет свободных частей' : offer.label,
                              style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                            ),
                            if (offer != null)
                              // Цена — то, ради чего карточку и открывают: заголовочным шрифтом,
                              // а не как ещё одна строчка мелочей.
                              Text(
                                formatTenge(offer.meat),
                                style: context.texts.headlineSmall?.copyWith(fontSize: 26),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward, color: c.green),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Плашка с необязательным значком: «сертификаты» — это обещание платформы, и печать рядом
  /// со словом делает его проверкой, а не ещё одним ярлыком.
  Widget _tag(BuildContext context, String text, {bool accent = false, IconData? icon}) {
    final c = context.et;
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 5, 10, 5),
      decoration: BoxDecoration(
        color: accent ? c.greenTint : c.fillTrack,
        borderRadius: BorderRadius.circular(EtShape.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: accent ? c.green : c.inkDim),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: context.texts.labelSmall?.copyWith(
              color: accent ? c.green : c.inkDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
