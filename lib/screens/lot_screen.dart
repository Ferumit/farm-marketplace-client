import 'package:et_core/et_core.dart';
import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'group_screen.dart';
import 'order_detail_screen.dart';
import 'order_sheet.dart';

/// One carcass - leadership's window 1.3.
///
/// What it is, whose it is, what is still free of it, and what each format costs. Ordering itself
/// happens in the sheet (order_sheet.dart), which prices the choice with the same arithmetic the
/// server will use.
class LotScreen extends StatefulWidget {
  const LotScreen({super.key, required this.lotId});

  final String lotId;

  @override
  State<LotScreen> createState() => _LotScreenState();
}

class _LotScreenState extends State<LotScreen> {
  final _repo = CatalogueRepo();

  Lot? _lot;
  Partner? _farm;
  Animal? _animal;
  List<Review> _reviews = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lot = await _repo.lot(widget.lotId);
      final farm = lot == null ? null : await _repo.partner(lot.partnerId);
      final animals = lot == null ? <String, Animal>{} : await _repo.animalsByIds(lot.animalIds);
      final reviews = farm == null
          ? <Review>[]
          : await _repo.reviewsOf(farm.id).catchError((_) => <Review>[]);
      if (!mounted) return;
      setState(() {
        _lot = lot;
        _farm = farm;
        _animal = animals.values.isEmpty ? null : animals.values.first;
        _reviews = reviews;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _order() async {
    final result = await showOrderSheet(context, lotId: widget.lotId);
    if (result == null || !mounted) return;

    // A gathering has its own page from the moment it is created: that is the link to send.
    if (result.groupId != null) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => GroupScreen(groupId: result.groupId!)));
      if (mounted) await _load();
      return;
    }
    // Заказ создан — а что дальше, решает сервер: по одним заказам покупатель платит картой,
    // по другим расчёт идёт напрямую с хозяйством. Это написано на экране заказа, туда и ведём.
    // Оставить человека на туше со словами «хозяйство подтвердит» нельзя: по оплачиваемому
    // заказу хозяйство как раз ничего не подтвердит, пока не придут деньги.
    if (result.orderId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          settings: RouteSettings(name: 'order/${result.orderId}'),
          builder: (_) => OrderDetailScreen(orderId: result.orderId!),
        ),
      );
      if (mounted) await _load();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Добавлено в корзину. Оформить можно вместе с другими тушами.'),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lot = _lot;
    return Scaffold(
      appBar: AppBar(title: const Text('Туша')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(EtShape.gutter), child: EtSkeleton(height: 260))
          : lot == null
          ? const EtEmpty(
              title: 'Туша не найдена',
              text: 'Возможно, её уже сняли с продажи.',
              icon: Icons.search_off,
            )
          : _body(lot),
      bottomNavigationBar: lot == null || bestOffer(lot) == null
          ? null
          : EtBottomBar(
              caption: Row(
                children: [
                  Expanded(
                    child: Text(
                      bestOffer(lot)!.label,
                      style: context.texts.bodySmall?.copyWith(color: context.et.inkFaint),
                    ),
                  ),
                  Text(formatTenge(bestOffer(lot)!.meat), style: context.texts.titleMedium),
                ],
              ),
              child: FilledButton(
                onPressed: _order,
                child: const Text('Выбрать формат и заказать'),
              ),
            ),
    );
  }

  Widget _body(Lot lot) {
    final c = context.et;
    final farm = _farm;
    final offers = formatsOf(lot);
    final storefront = farm?.storefront ?? const Storefront();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        EtHero(
          label: meatLabel[_animal?.type ?? lot.meatType ?? 'cattle'] ?? 'Мясо',
          meatType: _animal?.type ?? lot.meatType ?? 'cattle',
          imageUrl: lot.imageUrl,
          height: 120,
          rounded: false,
          note: lot.totalWeight > 0 ? weightLabel(lot.totalWeight) : null,
        ),
        Padding(
          padding: const EdgeInsets.all(EtShape.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lot.name, style: context.texts.headlineSmall),
              const SizedBox(height: 6),
              Text(
                [
                  farm?.displayName ?? '',
                  lot.location ?? '',
                ].where((s) => s.isNotEmpty).join(' · '),
                style: context.texts.bodyMedium?.copyWith(color: c.inkDim),
              ),
              const SizedBox(height: 16),

              EtCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EtProgress(
                      percent: lot.totalShares == 0 ? 0 : lot.bookedShares / lot.totalShares,
                      label: availabilityLabel(lot),
                      trailing: lot.pricePerKg > 0 ? '${formatTenge(lot.pricePerKg)}/кг' : null,
                    ),
                    const SizedBox(height: 14),
                    for (final format in ['half', 'whole'])
                      if (offers[format]!.sellable)
                        EtRow(
                          label: offers[format]!.label,
                          sub: [
                            weightLabel(offers[format]!.weight),
                            if (!offers[format]!.available) 'уже забронирована',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          value: formatTenge(offers[format]!.meat),
                          valueColor: offers[format]!.available ? null : c.inkFaint,
                        ),
                  ],
                ),
              ),

              if (lot.description.isNotEmpty) ...[
                const SizedBox(height: EtShape.gap),
                EtCard(child: Text(lot.description, style: context.texts.bodyMedium)),
              ],

              const SizedBox(height: EtShape.gap),
              EtCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Животное', style: context.texts.titleSmall),
                    const SizedBox(height: 4),
                    EtRow(
                      label: 'Вид',
                      value: meatLabel[_animal?.type ?? lot.meatType ?? 'cattle'] ?? '—',
                    ),
                    if (_animal?.breed.isNotEmpty == true)
                      EtRow(label: 'Порода', value: _animal!.breed),
                    if (_animal?.ageCategory != null)
                      EtRow(label: 'Возраст', value: _animal!.ageCategory!),
                    if (lot.totalWeight > 0)
                      EtRow(label: 'Вес туши', value: weightLabel(lot.totalWeight)),
                    const SizedBox(height: 8),
                    Text(
                      'Точный вес — после контрольного взвешивания: при перевесе доплата, при недовесе возврат разницы.',
                      style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                    ),
                  ],
                ),
              ),

              if (farm != null) ...[
                const SizedBox(height: EtShape.gap),
                EtCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(farm.displayName, style: context.texts.titleSmall)),
                          if (farm.certified)
                            const EtStatusChip(text: 'Сертификаты', tone: 'active'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${farm.rating.toStringAsFixed(1)} · ${farm.totalDeals} '
                        '${pluralRu(farm.totalDeals, 'сделка', 'сделки', 'сделок')}'
                        '${farm.reviewsCount > 0 ? ' · ${farm.reviewsCount} ${pluralRu(farm.reviewsCount, 'отзыв', 'отзыва', 'отзывов')}' : ''}',
                        style: context.texts.bodySmall?.copyWith(color: c.inkDim),
                      ),
                      if (storefront.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(storefront.description, style: context.texts.bodySmall),
                      ],
                      if (storefront.cutting.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Разделка', style: context.texts.labelLarge),
                        EtRow(label: 'Стандартная', value: 'в цене'),
                        for (final option in storefront.cutting)
                          EtRow(
                            label: option.name,
                            sub: option.note ?? 'за половину туши',
                            value: '+${formatTenge(option.price)}',
                          ),
                      ],
                      if (storefront.pickup || storefront.delivery.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Доставка', style: context.texts.labelLarge),
                        if (storefront.pickup)
                          EtRow(label: 'Самовывоз из хаба', value: 'бесплатно'),
                        for (final tariff in storefront.delivery)
                          EtRow(label: tariff.city, value: formatTenge(tariff.price)),
                      ],
                    ],
                  ),
                ),
              ],

              _OpenGroups(lotId: widget.lotId),

              if (_reviews.isNotEmpty) ...[
                const SizedBox(height: EtShape.gap),
                EtCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Отзывы покупателей', style: context.texts.titleSmall),
                      const SizedBox(height: 4),
                      for (final review in _reviews.take(5)) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              '★' * review.rating + '☆' * (5 - review.rating),
                              style: const TextStyle(color: Color(0xFFE9A23B)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                review.buyerName,
                                style: context.texts.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (review.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(review.text, style: context.texts.bodySmall),
                          ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: EtShape.gap),
              const EtNotice(
                text:
                    'Бронь закрепляет тушу за вами. Что и когда платить — будет написано '
                    'на экране заказа сразу после бронирования.',
                icon: Icons.verified_user_outlined,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

/// Gatherings on this carcass that still have a free place.
///
/// The organiser shares a link, but a link opens the website - inside the app this card is the
/// way in. Nothing is held while a gathering fills, so the carcass may be ordered by someone
/// else first; that is what the server tells the last person to join.
class _OpenGroups extends StatelessWidget {
  const _OpenGroups({required this.lotId});

  final String lotId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupBuy>>(
      stream: GroupBuysRepo().openForLot(lotId),
      builder: (context, snapshot) {
        final groups = (snapshot.data ?? const <GroupBuy>[])
            .where((g) => g.freePlaces > 0)
            .toList();
        if (groups.isEmpty) return const SizedBox.shrink();
        final c = context.et;
        final uid = context.watch<AuthService>().uid ?? '';

        return Padding(
          padding: const EdgeInsets.only(top: EtShape.gap),
          child: EtCard(
            tinted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Собирают эту тушу', style: context.texts.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Можно занять свободное место и заплатить только свою долю.',
                  style: context.texts.bodySmall?.copyWith(color: c.inkDim),
                ),
                for (final group in groups) ...[
                  const SizedBox(height: 12),
                  EtRow(
                    label:
                        '${formatLabel[group.format] ?? ''} · ${group.creatorName.isEmpty ? 'организатор' : group.creatorName}',
                    sub:
                        'собрано ${group.joined} из ${group.size} · осталось ${group.freePlaces} '
                        '${pluralRu(group.freePlaces, 'место', 'места', 'мест')}',
                    value: formatTenge(group.shareFor(uid)),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => GroupScreen(groupId: group.id))),
                    child: Text(
                      group.memberUids.contains(uid)
                          ? 'Открыть сбор'
                          : 'Посмотреть и присоединиться',
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
