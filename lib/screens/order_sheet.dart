import 'package:et_core/et_core.dart';
import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// What the buyer did with the sheet.
class OrderSheetResult {
  const OrderSheetResult({this.orderId, this.groupId, this.addedToCart = false});

  final String? orderId;
  final String? groupId;
  final bool addedToCart;
}

/// Ordering one carcass - leadership's windows 1.3 and 1.4 in a single sheet.
///
/// A lot is one carcass: it is bought whole or by the half, with the farm's cutting and its
/// delivery. The same sheet also puts the choice in the cart, or gathers 2-5 people around it.
/// Everything here is a PREVIEW - the server prices the order again from the lot and the farm's
/// storefront when it is placed, so nothing this screen computes can set a price. It only has to
/// agree with the server, which is why the arithmetic comes from et_core.
Future<OrderSheetResult?> showOrderSheet(BuildContext context, {required String lotId}) {
  return showModalBottomSheet<OrderSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OrderSheet(lotId: lotId),
  );
}

class _OrderSheet extends StatefulWidget {
  const _OrderSheet({required this.lotId});

  final String lotId;

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  final _catalogue = CatalogueRepo();
  final _api = EtApi();
  final _address = TextEditingController();
  final _phone = TextEditingController();

  /// One key for this sheet: a retry after a lost answer returns the order already made instead
  /// of booking the carcass twice.
  final _idempotencyKey =
      '${DateTime.now().microsecondsSinceEpoch}-${UniqueKey().hashCode}';

  Lot? _lot;
  Partner? _farm;
  bool _loading = true;
  bool _placing = false;
  String? _error;

  String _format = 'half';
  String? _formatHint;
  String? _cuttingId;
  String? _deliveryId;
  DateTime _date = DateTime.now().add(const Duration(days: 4));
  String _slot = 'any';

  /// Gathering 2-5 people instead of ordering alone. The carcass is NOT held while a group
  /// fills - the server says so and so does this screen.
  bool _groupMode = false;
  int _groupSize = 2;

  @override
  void initState() {
    super.initState();
    _phone.text = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    _load();
  }

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lot = await _catalogue.lot(widget.lotId);
      final farm = lot == null ? null : await _catalogue.partner(lot.partnerId);
      if (!mounted) return;
      final offers = lot == null ? null : formatsOf(lot);
      setState(() {
        _lot = lot;
        _farm = farm;
        _format = offers != null && offers['half']!.available ? 'half' : 'whole';
        final options = deliveryOptions(farm?.storefront ?? const Storefront());
        _deliveryId = options.isEmpty ? null : options.first.id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить тушу. Проверьте связь.';
      });
    }
  }

  bool get _needsAddress => _deliveryId != 'pickup';

  /// Ни одного формата к продаже. Так бывает не только когда тушу разобрали целиком: от лота
  /// старой модели, где долей было восемь, после пяти заказов остаётся три — меньше половины,
  /// а четвертями мы не торгуем. Снаружи оба случая выглядят одинаково: обе плитки приглушены
  /// и выбрать нечего. Значит, и кнопки заказа должны быть выключены, иначе бронь уйдёт на
  /// сервер и вернётся ошибкой.
  bool get _nothingFree {
    final lot = _lot;
    if (lot == null) return false;
    return !formatsOf(lot).values.any((o) => o.available);
  }

  String _soldOutReason(Lot lot) {
    if (!lot.isOpen) return 'Эта туша сейчас не продаётся.';
    if (lot.freeShares == 0) return 'Эту тушу уже разобрали целиком.';
    return 'От этой туши осталось меньше половины — такую часть хозяйство не продаёт. '
        'Посмотрите другие туши этого хозяйства.';
  }

  /// Puts the choice aside instead of ordering it now. Nothing is booked: the cart is a list of
  /// intentions, and every price in it is re-checked when it is opened.
  Future<void> _addToCart() async {
    final lot = _lot;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (lot == null || uid == null) return;
    final storefront = _farm?.storefront ?? const Storefront();
    final q = quote(lot, storefront, format: _format, cuttingId: _cuttingId, deliveryId: _deliveryId);

    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      await CartRepo().add(
        uid,
        CartItem(
          id: CartItem.idFor(lot.id, _format),
          lotId: lot.id,
          lotTitle: lot.name,
          imageUrl: lot.imageUrl,
          partnerId: lot.partnerId,
          partnerName: _farm?.displayName ?? '',
          format: _format,
          cuttingId: _cuttingId,
          cuttingName: q.cuttingOption?.name,
          deliveryId: _deliveryId,
          deliveryCity: q.deliveryTariff?.city,
          deliveryMode: _deliveryId == 'pickup'
              ? 'pickup'
              : (_deliveryId == null ? 'agree' : 'city'),
          weightKg: q.weight,
          amount: q.total,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(const OrderSheetResult(addedToCart: true));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _placing = false;
        _error = 'Не удалось добавить в корзину. Проверьте связь.';
      });
    }
  }

  Future<void> _place() async {
    final phone = _phone.text.trim();
    final address = _address.text.trim();
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
    try {
      if (_groupMode) {
        final groupId = await _api.createGroupBuy(
          lotId: widget.lotId,
          format: _format,
          size: _groupSize,
          cuttingId: _cuttingId,
          deliveryId: _deliveryId,
          deliveryAddress: _needsAddress ? address : '',
          deliveryDate: _date.toIso8601String().substring(0, 10),
          deliverySlot: _slot,
          contactPhone: phone,
        );
        if (!mounted) return;
        Navigator.of(context).pop(OrderSheetResult(groupId: groupId));
        return;
      }
      final orderId = await _api.createOrder(
        lotId: widget.lotId,
        format: _format,
        cuttingId: _cuttingId,
        deliveryId: _deliveryId,
        deliveryAddress: _needsAddress ? address : '',
        deliveryDate: _date.toIso8601String().substring(0, 10),
        deliverySlot: _slot,
        contactPhone: phone,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(OrderSheetResult(orderId: orderId));
    } on EtApiException catch (e) {
      // The server refuses in Russian - "Свободной половины не осталось." - and that sentence is
      // better than anything this screen could invent.
      if (!mounted) return;
      setState(() {
        _placing = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _placing = false;
        _error = 'Не получилось оформить заказ. Попробуйте ещё раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.et;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _lot == null
                ? EtEmpty(
                    title: 'Туша не найдена',
                    text: _error ?? 'Возможно, её уже сняли с продажи.',
                    icon: Icons.search_off,
                  )
                : _form(controller),
      ),
    );
  }

  Widget _form(ScrollController controller) {
    final lot = _lot!;
    final storefront = _farm?.storefront ?? const Storefront();
    final offers = formatsOf(lot);
    final options = deliveryOptions(storefront);
    // Город уже выбран выше — тарифом хозяйства. Просить вписать его ещё раз в строку адреса
    // значит просить одно и то же дважды, и второй раз - с опечатками.
    final chosenCity = _deliveryId == null || _deliveryId == 'pickup'
        ? null
        : options.where((o) => o.id == _deliveryId).map((o) => o.label).firstOrNull;
    final q = quote(lot, storefront, format: _format, cuttingId: _cuttingId, deliveryId: _deliveryId);
    final c = context.et;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(EtShape.gutter, 12, EtShape.gutter, 28),
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 18),
        const EtEyebrow('Оформление заказа'),
        const SizedBox(height: 6),
        Text(lot.name, style: context.texts.headlineSmall),
        Text(
          '${_farm?.displayName ?? ''} · ${availabilityLabel(lot)}',
          style: context.texts.bodySmall?.copyWith(color: c.inkDim),
        ),
        const SizedBox(height: 20),

        if (_groupMode) ...[
          EtCard(
            tinted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.group_outlined, size: 18, color: c.green),
                    const SizedBox(width: 8),
                    Text('Совместная покупка', style: context.texts.titleSmall),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Вы организатор: выбираете тушу, разделку и доставку, а стоимость делится поровну. '
                  'Заказ уйдёт хозяйству, когда соберутся все участники.',
                  style: context.texts.bodySmall?.copyWith(color: c.inkDim),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _groupSize,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Сколько человек делят тушу'),
                  items: [
                    for (final n in [2, 3, 4, 5])
                      DropdownMenuItem(
                        value: n,
                        child: Text('$n ${pluralRu(n, 'человек', 'человека', 'человек')}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _groupSize = value ?? 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        // Формат — не пункт анкеты, а сам выбор: половина или целая. Две плитки рядом дают
        // сравнить вес и цену одним взглядом; двумя радиокнопками в столбик цены приходилось
        // сличать по очереди.
        _section('Формат'),
        _formats(lot, offers),
        // Когда не продаётся ни один формат, говорим это сразу и сами. Ждать, пока человек
        // потыкает в обе приглушённые плитки и догадается, — ровно то, из-за чего экран
        // назвали неживым.
        if (_nothingFree) ...[
          const SizedBox(height: 10),
          EtNotice(text: _soldOutReason(lot), icon: Icons.info_outline, tone: 'danger'),
        ] else if (_formatHint != null) ...[
          const SizedBox(height: 10),
          EtNotice(text: _formatHint!, icon: Icons.info_outline),
        ],

        const SizedBox(height: 18),
        _section('Разделка'),
        _choice(
          title: 'Стандартная',
          subtitle: 'включена в цену',
          trailing: '',
          selected: _cuttingId == null,
          onTap: () => setState(() => _cuttingId = null),
        ),
        for (final option in storefront.cutting)
          _choice(
            title: option.name,
            subtitle: option.note ?? 'за половину туши',
            trailing: '+${formatTenge(option.price)}',
            selected: _cuttingId == option.id,
            onTap: () => setState(() => _cuttingId = option.id),
          ),

        const SizedBox(height: 18),
        _section('Доставка'),
        if (options.isEmpty)
          Text(
            'Хозяйство ещё не указало тарифы — способ и стоимость вы согласуете с ним после заказа.',
            style: context.texts.bodySmall?.copyWith(color: c.inkDim),
          ),
        for (final option in options)
          _choice(
            title: option.label,
            subtitle: option.id == 'pickup' ? 'адрес хаба сообщит фермер' : 'доставка хозяйства',
            trailing: option.price == 0 ? 'бесплатно' : formatTenge(option.price),
            selected: _deliveryId == option.id,
            onTap: () => setState(() => _deliveryId = option.id),
          ),

        const SizedBox(height: 18),
        if (_needsAddress) ...[
          TextField(
            controller: _address,
            maxLines: 2,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: chosenCity == null ? 'Адрес доставки' : 'Улица, дом, квартира',
              hintText: chosenCity == null ? 'Город, улица, дом, квартира' : 'Абая 49, кв. 12',
              helperText: chosenCity == null ? null : 'Город — $chosenCity, вы выбрали его выше',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
        ],
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
                // Without isExpanded the menu keeps its items' natural width, and "Вечер,
                // 16:00–20:00" runs off the right edge of a phone.
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Время'),
                items: [
                  for (final entry in slotLabel.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() => _slot = value ?? 'any'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Забой и разделка занимают несколько дней — фермер подтвердит дату или предложит другую.',
          style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Контактный телефон'),
        ),

        const SizedBox(height: 20),
        EtCard(
          child: Column(
            children: [
              EtRow(
                label: formatLabel[_format]!,
                sub: [
                  weightLabel(q.weight),
                  if (lot.pricePerKg > 0) '${formatTenge(lot.pricePerKg)}/кг',
                ].where((s) => s.isNotEmpty).join(' × '),
                value: formatTenge(q.meat),
              ),
              EtRow(
                label: 'Разделка',
                sub: q.cuttingOption?.name ?? 'стандартная',
                value: q.cutting == 0 ? 'в цене' : formatTenge(q.cutting),
              ),
              EtRow(
                label: 'Доставка',
                sub: _deliveryId == 'pickup'
                    ? 'самовывоз из хаба'
                    : (q.deliveryTariff?.city ?? 'по договорённости'),
                value: options.isEmpty ? '—' : (q.delivery == 0 ? 'бесплатно' : formatTenge(q.delivery)),
              ),
              const Divider(height: 20),
              EtRow(label: 'Итого', value: formatTenge(q.total), strong: true),
              if (_groupMode)
                // Even shares, the odd tenge on the organiser - the same split the server makes.
                EtRow(
                  label: 'Ваша доля',
                  sub: 'из $_groupSize ${pluralRu(_groupSize, 'участника', 'участников', 'участников')}',
                  value: formatTenge(q.total - (q.total ~/ _groupSize) * (_groupSize - 1)),
                  strong: true,
                  valueColor: c.green,
                ),
            ],
          ),
        ),
        if (lot.pricePerKg > 0) ...[
          const SizedBox(height: 10),
          Text(
            'Итог за мясо уточнится после контрольного взвешивания: при перевесе — доплата, при недовесе — возврат разницы.',
            style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          EtNotice(text: _error!, icon: Icons.error_outline, tone: 'danger'),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _placing || _nothingFree ? null : _place,
          child: _placing
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_groupMode ? 'Создать совместную покупку' : 'Забронировать заказ'),
        ),
        if (!_groupMode) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _placing || _nothingFree ? null : _addToCart,
            icon: const Icon(Icons.shopping_basket_outlined, size: 18),
            label: const Text('В корзину'),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _placing || _nothingFree
              ? null
              : () => setState(() => _groupMode = !_groupMode),
          icon: Icon(_groupMode ? Icons.close : Icons.group_add_outlined, size: 18),
          label: Text(_groupMode ? 'Обычный заказ' : 'Собрать совместную покупку'),
        ),
        const SizedBox(height: 10),
        EtNotice(
          text: _groupMode
              ? 'Пока идёт сбор, туша не бронируется: если её купят раньше, сбор не состоится '
                  'и никто ничего не теряет.'
              : 'Бронь закрепляет тушу за вами. Что и когда платить — будет написано на '
                  'экране заказа сразу после бронирования.',
          icon: Icons.verified_user_outlined,
        ),
      ],
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

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: EtEyebrow(title),
      );

  /// Две плитки формата в ряд. Если продаётся только один формат, он занимает всю ширину —
  /// пустая половина рядом читалась бы как «что-то не загрузилось».
  Widget _formats(Lot lot, Map<String, FormatOffer> offers) {
    final sellable = ['half', 'whole'].where((f) => offers[f]!.sellable).toList();
    // Плиток нет вовсе — но и объяснять здесь нечего: раз ни один формат не продаётся,
    // `_nothingFree` уже true и причину напишет уведомление ниже. Два сообщения подряд об
    // одном и том же читаются как два разных отказа.
    if (sellable.isEmpty) return const SizedBox.shrink();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sellable.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _formatTile(lot, sellable[i], offers[sellable[i]]!)),
          ],
        ],
      ),
    );
  }

  Widget _formatTile(Lot lot, String format, FormatOffer offer) {
    final c = context.et;
    final selected = _format == format && offer.available;
    final weight = weightLabel(offer.weight);

    return Opacity(
      // Занятую половину не убираем со страницы: человеку важно видеть, что туша делится на две
      // и одна уже ушла. Но она приглушена — выбрать её нельзя.
      opacity: offer.available ? 1 : 0.5,
      child: InkWell(
        borderRadius: EtShape.cardRadius,
        // Недоступный формат тоже отвечает на нажатие — словами. Молчащая плитка читается как
        // сломанная кнопка: человек жмёт, ничего не происходит, и он уходит с мыслью, что
        // приложение не работает. Приглушённости и мелкой подписи для этого мало.
        onTap: offer.available
            ? () => setState(() {
                _format = format;
                _formatHint = null;
              })
            : () => _whyUnavailable(format),
        // Рамка выбранной плитки не вспыхивает, а наливается: нажатие должно ощущаться ответом,
        // а не перерисовкой.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // Выбранная плитка не только обводится, но и заливается. Половина выбрана заранее,
            // и по одной рамке это читалось как «ничего не произошло»: человек жал на неё,
            // ждал отклика и решал, что плитка мёртвая.
            color: selected ? c.greenTint : c.surfaceRaised,
            borderRadius: EtShape.cardRadius,
            border: Border.all(color: selected ? c.green : c.line, width: selected ? 1.8 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  EtHero(
                    label: format == 'half' ? 'Половина' : 'Целая',
                    meatType: lot.meatType ?? 'cattle',
                    height: 48,
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: c.green, shape: BoxShape.circle),
                        child: Icon(Icons.check, size: 14, color: c.onGreen),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.available
                          ? [
                              if (weight.isNotEmpty) weight,
                              if (lot.pricePerKg > 0) '${formatTenge(lot.pricePerKg)}/кг',
                            ].join(' · ')
                          : 'уже забронирована',
                      style: context.texts.bodySmall
                          ?.copyWith(color: offer.available ? c.inkFaint : c.rust),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatTenge(offer.meat),
                      style: context.texts.titleLarge?.copyWith(fontSize: 21),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Почему этот формат нельзя выбрать. Туша делится надвое: как только одну половину взяли,
  /// целую уже не купить — и это не поломка, а то, ради чего половины и придуманы.
  ///
  /// Подсказка живёт ВНУТРИ листа, а не в снекбаре: снекбар показывается у нижнего края экрана,
  /// а лист занимает почти весь экран и накрывает его собой. Человек нажал бы и снова ничего не
  /// увидел — ровно та жалоба, с которой всё началось.
  void _whyUnavailable(String format) {
    // Когда недоступны оба формата, причину уже объясняет постоянное уведомление над кнопками.
    // Второй текст рядом с ним только спорил бы с первым.
    if (_nothingFree) return;
    setState(() {
      _formatHint = format == 'whole'
          ? 'Целую тушу уже не взять — одну половину забронировали. Свободна вторая.'
          : 'Эту половину уже забронировали.';
    });
  }

  Widget _choice({
    required String title,
    required String subtitle,
    required String trailing,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
    String disabledNote = '',
  }) {
    final c = context.et;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: EtShape.smallRadius,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected && enabled ? c.greenTint : c.surfaceRaised,
            borderRadius: EtShape.smallRadius,
            border: Border.all(color: selected && enabled ? c.green : c.line, width: selected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: enabled ? (selected ? c.green : c.inkFaint) : c.inkFaint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: enabled ? c.ink : c.inkFaint,
                      ),
                    ),
                    Text(
                      enabled ? subtitle : disabledNote,
                      style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                    ),
                  ],
                ),
              ),
              if (trailing.isNotEmpty)
                Text(
                  trailing,
                  style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
