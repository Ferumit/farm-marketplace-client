import 'dart:async';

import 'package:et_core/et_core.dart';
import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'order_detail_screen.dart';

/// «Корзина» - the carcasses picked and not yet ordered.
///
/// Every line is re-checked against the lot as it is now, because a cart can sit for days: a half
/// someone else booked, a farm that went off sale, a changed cutting - all of it shows here
/// rather than at the moment of ordering. Ordering makes ONE ORDER PER CARCASS: an order is one
/// carcass from one farm, and each farm prepares and delivers its own.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cart = CartRepo();
  final _catalogue = CatalogueRepo();
  final _api = EtApi();
  final _address = TextEditingController();
  final _phone = TextEditingController();

  StreamSubscription<List<CartItem>>? _sub;
  int _seq = 0;

  List<CartLine> _lines = const [];
  bool _loading = true;
  bool _placing = false;
  String? _error;
  String _progress = '';
  DateTime _date = DateTime.now().add(const Duration(days: 4));
  String _slot = 'any';

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid == null) {
      _loading = false;
      return;
    }
    _phone.text = context.read<AuthService>().phone ?? '';
    // The cart is watched, not read once: the tab stays alive behind the catalogue, so a carcass
    // added from a lot has to appear here without the person thinking to refresh.
    _sub = _cart.watch(uid).listen(
      _resolve,
      onError: (_) => _fail(),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? get _uid => context.read<AuthService>().uid;

  /// Prices what is in the cart against the lots as they are now. Slow enough to overlap with
  /// the next event, so a late answer to an old cart is dropped rather than shown.
  Future<void> _resolve(List<CartItem> items) async {
    final uid = _uid;
    if (uid == null) return;
    final seq = ++_seq;
    try {
      final lines = await loadCartLines(
        uid: uid,
        cart: _cart,
        catalogue: _catalogue,
        items: items,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _lines = lines;
        _loading = false;
      });
    } catch (_) {
      if (seq == _seq) _fail();
    }
  }

  void _fail() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = 'Не удалось загрузить корзину. Проверьте связь.';
    });
  }

  /// A re-check of the same cart: pulled down by hand, and after ordering - a line that failed
  /// leaves the cart unchanged, so nothing would arrive through the stream to re-price it.
  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    await _resolve(await _cart.read(uid));
  }

  List<CartLine> get _ready => _lines.where((l) => l.ready).toList();
  bool get _needsAddress => _ready.any((l) => l.item.deliveryMode != 'pickup');

  /// Places the cart, one carcass at a time. A half that goes while we are ordering must fail
  /// only its own line - and only what became an order leaves the cart.
  Future<void> _placeAll() async {
    final uid = _uid;
    if (uid == null) return;
    final address = _needsAddress ? _address.text.trim() : '';
    final phone = _phone.text.trim();
    if (_needsAddress && address.length < 5) {
      setState(() => _error = 'Укажите адрес доставки.');
      return;
    }
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Укажите телефон для связи.');
      return;
    }

    setState(() {
      _placing = true;
      _error = null;
    });

    final key = DateTime.now().microsecondsSinceEpoch.toString();
    final placed = <String>[];
    final orderIds = <String>[];
    final failed = <String>[];
    final ready = _ready;

    for (var i = 0; i < ready.length; i++) {
      final line = ready[i];
      setState(() => _progress = 'Оформляем ${i + 1} из ${ready.length}…');
      try {
        final orderId = await _api.createOrder(
          lotId: line.item.lotId,
          format: line.item.format,
          cuttingId: line.item.cuttingId,
          deliveryId: line.item.deliveryId,
          deliveryAddress: address,
          deliveryDate: _date.toIso8601String().substring(0, 10),
          deliverySlot: _slot,
          contactPhone: phone,
          idempotencyKey: '$key-${line.item.id}',
        );
        placed.add(line.item.id);
        orderIds.add(orderId);
      } on EtApiException catch (e) {
        failed.add('${line.item.lotTitle} — ${e.message}');
      } catch (_) {
        failed.add('${line.item.lotTitle} — не удалось оформить.');
      }
    }

    if (placed.isNotEmpty) await _cart.clear(uid, ids: placed).catchError((_) {});
    if (!mounted) return;
    setState(() {
      _placing = false;
      _progress = '';
      _error = failed.isEmpty ? null : 'Осталось в корзине: ${failed.join('; ')}';
    });
    await _load();

    if (!mounted || placed.isEmpty) return;
    // Один заказ — открываем его: там написано, надо ли по нему платить. Несколько — ведём в
    // «Заказы», потому что и платить по ним, возможно, придётся по отдельности.
    if (orderIds.length == 1) {
      openOrder(context, orderIds.first);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Оформлено ${placed.length} ${pluralRu(placed.length, 'заказ', 'заказа', 'заказов')}. '
          'Откройте «Заказы» — там видно, что дальше по каждому.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Корзина')),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(EtShape.gutter),
              child: EtSkeleton(height: 160),
            )
          : _lines.isEmpty
              ? const EtEmpty(
                  title: 'Корзина пуста',
                  text: 'Выберите тушу — половину или целую — и добавьте её сюда. '
                      'Оформить можно всё разом.',
                  icon: Icons.shopping_basket_outlined,
                  illustrated: true,
                )
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final c = context.et;
    final ready = _ready;
    final total = ready.fold<int>(0, (sum, line) => sum + line.amount);
    final farms = ready.map((l) => l.item.partnerId).toSet().length;

    return ListView(
      padding: const EdgeInsets.all(EtShape.gutter),
      children: [
        for (var i = 0; i < _lines.length; i++)
          EtReveal(index: i, child: _line(_lines[i])),
        const SizedBox(height: EtShape.gap),
        EtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Итого', style: context.texts.titleSmall),
              EtRow(
                label: 'Готово к заказу',
                value: '${ready.length} ${pluralRu(ready.length, 'туша', 'туши', 'туш')}',
              ),
              if (farms > 1) EtRow(label: 'Хозяйств', value: '$farms'),
              EtRow(label: 'Сумма', value: formatTenge(total), strong: true),
              if (farms > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Туши из разных хозяйств станут отдельными заказами — каждое готовит и везёт своё.',
                    style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                  ),
                ),
            ],
          ),
        ),
        if (ready.isNotEmpty) ...[
          const SizedBox(height: EtShape.gap),
          EtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Доставка и связь', style: context.texts.titleSmall),
                const SizedBox(height: 10),
                if (_needsAddress) ...[
                  TextField(
                    controller: _address,
                    maxLines: 2,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Адрес доставки',
                      hintText: 'Город, улица, дом, квартира',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else
                  const EtNotice(
                    text: 'Все туши в корзине — самовывоз из хаба. Точный адрес фермер сообщит, '
                        'когда подтвердит заказ.',
                    icon: Icons.store_outlined,
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.event, size: 18),
                        label: Text(
                          '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _slot,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Время'),
                        items: [
                          for (final entry in slotLabel.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (value) => setState(() => _slot = value ?? 'any'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Контактный телефон'),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: EtShape.gap),
          EtNotice(text: _error!, icon: Icons.error_outline, tone: 'danger'),
        ],
        const SizedBox(height: EtShape.gap),
        FilledButton(
          onPressed: ready.isEmpty || _placing ? null : _placeAll,
          child: Text(
            _placing
                ? _progress
                : 'Забронировать ${ready.length} ${pluralRu(ready.length, 'заказ', 'заказа', 'заказов')}',
          ),
        ),
        const SizedBox(height: 10),
        const EtNotice(
          text: 'Бронь закрепляет тушу за вами. Что и когда платить — будет написано '
              'на экране заказа сразу после бронирования.',
          icon: Icons.verified_user_outlined,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _line(CartLine line) {
    final c = context.et;
    final item = line.item;
    final details = [
      formatLabel[item.format] ?? '',
      if (line.quote?.weight != null) weightLabel(line.quote!.weight),
      item.cuttingName == null ? 'стандартная разделка' : 'разделка «${item.cuttingName}»',
      item.deliveryMode == 'pickup'
          ? 'самовывоз'
          : (item.deliveryCity == null ? 'доставка по договорённости' : 'доставка: ${item.deliveryCity}'),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: EtShape.gap),
      child: EtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(item.lotTitle.isEmpty ? 'Туша' : item.lotTitle,
                      style: context.texts.titleSmall),
                ),
                Text(
                  line.ready ? formatTenge(line.amount) : '—',
                  style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(item.partnerName, style: context.texts.bodySmall?.copyWith(color: c.inkDim)),
            const SizedBox(height: 6),
            Text(details, style: context.texts.bodySmall?.copyWith(color: c.inkFaint)),
            if (!line.ready)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: c.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line.problem!,
                        style: context.texts.bodySmall?.copyWith(color: c.danger),
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final uid = _uid;
                  if (uid == null) return;
                  await _cart.remove(uid, item.id);
                },
                child: const Text('Убрать'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().add(const Duration(days: 2)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      locale: const Locale('ru'),
    );
    if (picked != null) setState(() => _date = picked);
  }
}

/// Opens an order from the snackbar after the cart was placed.
void openOrder(BuildContext context, String orderId) {
  Navigator.of(context).push(
    MaterialPageRoute(
      settings: RouteSettings(name: "order/$orderId"),
      builder: (_) => OrderDetailScreen(orderId: orderId),
    ),
  );
}
