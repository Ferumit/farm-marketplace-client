import 'dart:io';

import 'package:et_core/et_core.dart';
import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

/// The buyer's view of one order - leadership's window 1.5.
///
/// The road as the farm walks it: the animal it filmed, the ready meat, the control weighing and
/// the documents, each appearing as it happens. At the end the deal is confirmed - or disputed,
/// which holds the farm's last payout until the platform decides. Nothing here writes an order:
/// every move is updateOrderStatus.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _orders = OrdersRepo();
  final _catalogue = CatalogueRepo();
  final _api = EtApi();

  bool _busy = false;
  bool _paying = false;
  String? _error;
  bool _autoCompleteTried = false;
  Review? _review;
  bool _reviewChecked = false;
  int _stars = 0;
  final _reviewText = TextEditingController();

  @override
  void dispose() {
    _reviewText.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on EtApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не получилось. Проверьте связь и попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Three hours after the handover the deal closes itself. The scheduled sweep does it every
  /// quarter of an hour; opening the order closes an overdue one straight away, so the buyer is
  /// never shown a deal that should already be done.
  void _closeIfOverdue(FarmOrder order, String uid) {
    if (_autoCompleteTried || order.buyerUid != uid || !isOverdue(order)) return;
    _autoCompleteTried = true;
    _api.autoCompleteOrder(order.id).catchError((_) => '');
  }

  Future<void> _loadReview(FarmOrder order) async {
    if (_reviewChecked || stageOf(order.status) != 'completed') return;
    _reviewChecked = true;
    final review = await _catalogue.reviewOfOrder(order.id).catchError((_) => null);
    if (mounted && review != null) setState(() => _review = review);
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthService>().uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Заказ')),
      body: StreamBuilder<FarmOrder?>(
        stream: _orders.watch(widget.orderId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EtEmpty(
              title: 'Заказ недоступен',
              text: 'Он виден только своим сторонам.',
              icon: Icons.lock_outline,
            );
          }
          final order = snapshot.data;
          if (order == null || uid == null) {
            return const Padding(
              padding: EdgeInsets.all(EtShape.gutter),
              child: EtSkeleton(height: 240),
            );
          }
          _closeIfOverdue(order, uid);
          _loadReview(order);
          final isBuyer = order.buyerUid == uid;

          return ListView(
            padding: const EdgeInsets.all(EtShape.gutter),
            children: [
              _header(order),
              const SizedBox(height: EtShape.gap),
              EtCard(child: _timeline(order)),
              const SizedBox(height: EtShape.gap),
              _actions(order, isBuyer, uid),
              if (_error != null) ...[
                const SizedBox(height: EtShape.gap),
                EtNotice(text: _error!, icon: Icons.error_outline, tone: 'danger'),
              ],
              if (stageOf(order.status) == 'completed' && isBuyer) ...[
                const SizedBox(height: EtShape.gap),
                _reviewCard(order),
              ],
              if (order.isJoint) ...[
                const SizedBox(height: EtShape.gap),
                _group(order, uid),
              ],
              const SizedBox(height: EtShape.gap),
              _money(order, uid),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _header(FarmOrder order) {
    final c = context.et;
    return EtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(order.lotTitle.isEmpty ? 'Заказ' : order.lotTitle, style: context.texts.headlineSmall),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: EtStatusChip(
              text: statusTextForBuyer(order),
              tone: statusTone(order),
              icon: etStageIcon(order.status),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            orderSummary(
              format: order.format,
              estimatedWeightKg: order.estimatedWeightKg,
              shares: order.shares,
            ),
            style: context.texts.bodyMedium?.copyWith(color: c.inkDim),
          ),
          Text(formatTenge(order.total), style: context.texts.headlineSmall),
        ],
      ),
    );
  }

  Widget _timeline(FarmOrder order) {
    final c = context.et;
    final entries = <EtTimelineEntry>[
      EtTimelineEntry(
        title: 'Заказ оформлен',
        when: _when(order.createdAt),
        done: true,
        body: Text(
          [
            if (order.cutting != null) 'разделка «${order.cutting!.name}»',
            order.delivery.isPickup
                ? 'самовывоз'
                : 'доставка: ${order.delivery.city ?? 'по договорённости'}',
          ].join(' · '),
          style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
        ),
      ),
      EtTimelineEntry(
        title: 'Хозяйство приняло заказ',
        when: _when(order.acceptedAt),
        done: reached(order, 'accepted'),
        icon: etStageIcon('accepted'),
      ),
      EtTimelineEntry(
        title: 'Животное выбрано',
        when: _when(order.steps['identify']?.at),
        done: reached(order, 'animal_selected'),
        icon: etStageIcon('animal_selected'),
        body: _mediaOf(order.steps['identify']),
      ),
      EtTimelineEntry(
        title: 'Мясо готово',
        when: _when(order.steps['meat']?.at),
        done: reached(order, 'meat_ready'),
        icon: etStageIcon('meat_ready'),
        body: _meatBody(order),
      ),
      EtTimelineEntry(
        title: order.delivery.isPickup ? 'Готов к выдаче' : 'Заказ в пути',
        when: _when(order.steps['shipped']?.at),
        done: reached(order, 'shipped'),
        icon: etStageIcon('shipped'),
      ),
      EtTimelineEntry(
        title: 'Передан вам',
        when: _when(order.steps['handover']?.at),
        done: reached(order, 'delivered'),
        icon: etStageIcon('delivered'),
      ),
      EtTimelineEntry(
        title: 'Сделка завершена',
        when: _when(order.completedAt),
        done: reached(order, 'completed'),
        icon: etStageIcon('completed'),
        body: stageOf(order.status) == 'completed'
            ? Text(
                completedBy[order.completedBy] ?? '',
                style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
              )
            : null,
      ),
    ];

    // The first step not yet taken is the one being worked on - unless the deal is cancelled,
    // where nothing is in progress any more.
    final cancelled = stageOf(order.status) == 'cancelled';
    var currentMarked = false;
    final marked = entries.map((e) {
      if (!e.done && !currentMarked && !cancelled) {
        currentMarked = true;
        return EtTimelineEntry(
          title: e.title,
          when: e.when,
          body: e.body,
          icon: e.icon,
          current: true,
        );
      }
      return e;
    }).toList();

    return EtTimeline(entries: marked);
  }

  Widget? _mediaOf(OrderStep? step) {
    if (step == null || step.files.isEmpty) return null;
    return EtMediaStrip(
      items: step.files
          .map((f) => EtMediaItem(url: f.url, isVideo: f.isVideo, name: f.name))
          .toList(),
    );
  }

  Widget? _meatBody(FarmOrder order) {
    final step = order.steps['meat'];
    if (step == null) return null;
    final w = order.weighing;
    final c = context.et;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (step.files.isNotEmpty) _mediaOf(step)!,
        if (w != null) ...[
          const SizedBox(height: 8),
          Text(
            'Контрольное взвешивание: ${kgText(w.weightKg)} кг'
            '${order.estimatedWeightKg != null ? ' (ожидалось ~${kgText(order.estimatedWeightKg)} кг)' : ''}.',
            style: context.texts.bodySmall,
          ),
          if (w.meat != null)
            Text(
              w.difference > 0
                  ? 'Итог заказа ${formatTenge(w.total)}, доплата ${formatTenge(w.difference)}.'
                  : w.difference < 0
                      ? 'Итог заказа ${formatTenge(w.total)}, возврат вам ${formatTenge(-w.difference)}.'
                      : 'Итог заказа ${formatTenge(w.total)}, без перерасчёта.',
              style: context.texts.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
        ],
        if (step.certificates.isNotEmpty || step.documents.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Документы: ${[
              ...step.certificates.map((c) => c.label),
              ...step.documents.map((d) => d.name.isEmpty ? 'документ' : d.name),
            ].join(', ')}',
            style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
          ),
        ],
      ],
    );
  }

  Widget _actions(FarmOrder order, bool isBuyer, String uid) {
    final c = context.et;
    final stage = stageOf(order.status);

    if (!isBuyer) {
      return const EtCard(
        child: Text(
          'Вы участник совместной покупки. Шаги хозяйства видны здесь, '
          'а получение подтверждает организатор заказа.',
        ),
      );
    }
    if (stage == 'cancelled') {
      return EtCard(
        child: Text(
          order.cancelledBy == 'partner'
              ? 'Хозяйство отменило заказ. Туша вернулась в продажу.'
              : 'Вы отменили заказ. Туша вернулась в продажу.',
        ),
      );
    }
    if (stage == 'disputed') {
      return const EtNotice(
        text: 'Претензия отправлена. Администратор платформы свяжется с вами по номеру из заказа, '
            'а последняя выплата хозяйству удержана до решения.',
        icon: Icons.gavel_outlined,
        tone: 'danger',
      );
    }
    if (stage == 'completed') {
      return EtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сделка завершена — ${completedBy[order.completedBy] ?? ''}.'),
            if (order.disputeOutcome != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Решение по спору: ${disputeOutcomeForBuyer[order.disputeOutcome] ?? order.disputeOutcome}.',
                  style: context.texts.bodySmall?.copyWith(color: c.inkDim),
                ),
              ),
          ],
        ),
      );
    }

    final canFinish = canConfirm(order);
    return EtCard(
      tinted: canFinish,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canFinish) ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _confirm(order),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Сделка завершена'),
            ),
            const SizedBox(height: 6),
            Text(
              'Нажмите, когда мясо у вас и всё в порядке.',
              style: context.texts.bodySmall?.copyWith(color: c.inkDim),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _dispute(order),
              icon: Icon(Icons.report_outlined, size: 18, color: c.danger),
              label: Text('Оспорить качество', style: TextStyle(color: c.danger)),
            ),
            const SizedBox(height: 6),
            Text(
              'Запах, температура, не те куски — спор остановит последнюю выплату хозяйству '
              'до решения платформы.',
              style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
            ),
            if (stage == 'delivered' && order.autoCompleteAt != null) ...[
              const SizedBox(height: 12),
              EtNotice(
                text: 'Если ничего не нажать, сделка завершится сама '
                    '${_when(order.autoCompleteAt)} — через 3 часа после передачи.',
                icon: Icons.schedule,
              ),
            ],
          ] else
            Text(
              'Хозяйство готовит заказ — здесь появятся фото и видео каждого шага.',
              style: context.texts.bodyMedium,
            ),
          if (canCancel(order)) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : () => _cancel(order),
              child: const Text('Отменить заказ'),
            ),
            Text(
              'Отменить можно, пока хозяйство не приступило к забою.',
              style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(FarmOrder order) async {
    final ok = await _ask(
      'Подтвердить получение?',
      'Мясо у вас и всё в порядке? После этого сделка закроется.',
      'Да, всё в порядке',
    );
    if (ok) await _run(() => _api.completeOrder(order.id));
  }

  Future<void> _cancel(FarmOrder order) async {
    final ok = await _ask(
      'Отменить заказ?',
      'Хозяйство ещё не приступило к забою — туша вернётся в продажу.',
      'Отменить заказ',
    );
    if (ok) await _run(() => _api.cancelOrder(order.id));
  }

  Future<bool> _ask(String title, String text, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Назад')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    return result ?? false;
  }

  /// A claim with a photo of what is wrong. The evidence goes into the buyer's own folder, which
  /// is the only place the server accepts it from.
  Future<void> _dispute(FarmOrder order) async {
    final uid = context.read<AuthService>().uid;
    if (uid == null) return;
    final text = TextEditingController();
    File? picked;

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            EtShape.gutter,
            EtShape.gutter,
            EtShape.gutter,
            MediaQuery.of(context).viewInsets.bottom + EtShape.gutter,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Оспорить качество', style: context.texts.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Опишите проблему: запах, температура, несоответствие кусков. Претензия уходит '
                'администратору платформы, а последняя выплата хозяйству останавливается.',
                style: context.texts.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: text,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Что не так', counterText: ''),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final file = await ImagePicker()
                      .pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1920);
                  if (file != null) setSheet(() => picked = File(file.path));
                },
                icon: Icon(picked == null ? Icons.photo_camera_outlined : Icons.check, size: 18),
                label: Text(picked == null ? 'Снять фото' : 'Фото приложено'),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.pop(context, text.text.trim().length >= 5),
                child: const Text('Отправить в арбитраж платформы'),
              ),
            ],
          ),
        ),
      ),
    );

    if (sent != true) return;
    await _run(() async {
      String? mediaUrl;
      if (picked != null) {
        mediaUrl = await Uploads().disputeFile(uid: uid, orderId: order.id, file: picked!);
      }
      await _api.disputeOrder(order.id, description: text.text.trim(), mediaUrl: mediaUrl);
    });
  }

  Widget _reviewCard(FarmOrder order) {
    final c = context.et;
    final review = _review;
    if (review != null) {
      final state = switch (review.status) {
        'published' => 'Опубликован на странице хозяйства.',
        'rejected' => 'Не опубликован. ${review.moderationNote ?? ''}',
        _ => 'Отправлен на проверку — появится после модерации.',
      };
      return EtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ваш отзыв', style: context.texts.titleSmall),
            const SizedBox(height: 6),
            Text(
              '${'★' * review.rating}${'☆' * (5 - review.rating)} — $state',
              style: context.texts.bodySmall,
            ),
            if (review.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(review.text, style: context.texts.bodySmall?.copyWith(color: c.inkDim)),
              ),
          ],
        ),
      );
    }

    return EtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Отзыв о хозяйстве', style: context.texts.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Как прошла сделка? Оценку увидят другие покупатели — после проверки модератором.',
            style: context.texts.bodySmall?.copyWith(color: c.inkDim),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon(
                    i <= _stars ? Icons.star : Icons.star_border,
                    color: i <= _stars ? const Color(0xFFE9A23B) : c.inkFaint,
                    size: 30,
                  ),
                ),
            ],
          ),
          TextField(
            controller: _reviewText,
            maxLines: 3,
            maxLength: 1500,
            decoration: const InputDecoration(
              labelText: 'Что стоит знать другим',
              hintText: 'Мясо, упаковка, связь с фермером, доставка',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _stars == 0 || _busy
                ? null
                : () => _run(() async {
                      await _api.submitReview(
                        orderId: order.id,
                        rating: _stars,
                        text: _reviewText.text.trim(),
                      );
                      _reviewChecked = false;
                      await _loadReview(order);
                    }),
            child: const Text('Отправить отзыв'),
          ),
        ],
      ),
    );
  }

  Widget _group(FarmOrder order, String uid) {
    final group = order.group!;
    final isOrganiser = order.buyerUid == uid;
    return EtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_outlined, size: 18, color: context.et.green),
              const SizedBox(width: 8),
              Text('Совместная покупка', style: context.texts.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${group.size} ${pluralRu(group.size, 'участник', 'участника', 'участников')} делят эту тушу. '
            '${isOrganiser ? 'Вы организатор: оплачиваете всю сумму и подтверждаете получение. '
                'Ниже — сколько вам должен каждый.' : 'Организатор оплачивает всю сумму и '
                'подтверждает получение. Свою долю переведите ему.'}',
            style: context.texts.bodySmall?.copyWith(color: context.et.inkDim),
          ),
          const SizedBox(height: 6),
          for (final member in group.members)
            EtRow(
              label: member.uid == uid ? '${member.name} (вы)' : member.name,
              value: formatTenge(member.amount),
            ),
        ],
      ),
    );
  }

  Widget _money(FarmOrder order, String uid) {
    final w = order.weighing;
    return EtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Деньги', style: context.texts.titleSmall),
          const SizedBox(height: 4),
          EtRow(
            label: 'Сумма заказа',
            sub: orderSummary(
              format: order.format,
              estimatedWeightKg: order.estimatedWeightKg,
              shares: order.shares,
            ),
            value: formatTenge(order.amount),
          ),
          if (w != null && w.meat != null)
            EtRow(
              label: 'После взвешивания',
              sub: w.difference > 0
                  ? 'доплата ${formatTenge(w.difference)}'
                  : w.difference < 0
                      ? 'возврат ${formatTenge(-w.difference)}'
                      : 'без перерасчёта',
              value: formatTenge(w.total),
              strong: true,
            ),
          const SizedBox(height: 10),
          _payment(order, uid),
        ],
      ),
    );
  }

  /// Платёжная ось заказа словами покупателя.
  ///
  /// `not_required` — заказ пилота: деньги через платформу по нему не идут, и говорить об оплате
  /// тут нечего. Это записано на самом заказе в момент создания, поэтому экран не гадает по
  /// настройкам, а читает решение, принятое тогда.
  Widget _payment(FarmOrder order, String uid) {
    final status = order.payment.status;
    if (status == 'not_required') {
      return const EtNotice(
        text: 'Расчёт — и доплату или возврат после взвешивания — вы согласуете с хозяйством '
            'напрямую.',
        icon: Icons.info_outline,
      );
    }

    final (String title, String note, String tone) = switch (status) {
      'awaiting' => ('Ждёт оплаты', 'Хозяйство начнёт работу после оплаты.', 'waiting'),
      // «Оплачено», а не «деньги у платформы»: при холде сумма заблокирована на карте и спишется,
      // когда хозяйство примет заказ. На экране про деньги обещать больше, чем есть, нельзя.
      'authorized' => (
          'Оплачено',
          'Сумма заблокирована на карте и спишется, когда хозяйство примет заказ.',
          'active'
        ),
      'captured_partial' || 'captured_full' => ('Оплачено', 'Деньги у платформы.', 'active'),
      'cancelled' => ('Оплата отменена', 'Блокировка снята, деньги остались на карте.', 'off'),
      'failed' => ('Оплата не прошла', 'Деньги не списаны. Можно попробовать ещё раз.', 'danger'),
      'expired' => ('Счёт истёк', 'Ссылка на оплату больше не действует.', 'danger'),
      'refund_pending' => ('Оформляется возврат', 'Деньги вернутся на ту же карту.', 'waiting'),
      'refunded' => ('Возвращено', 'Деньги вернулись на карту, которой была оплата.', 'neutral'),
      _ => ('Оплата', '', 'neutral'),
    };

    // Складчину оплачивает организатор — одной суммой за всех, доли он потом собирает сам.
    // Участнику кнопку не показываем: сервер ему всё равно откажет, а кнопка, которая всегда
    // падает, хуже, чем её отсутствие.
    final awaitsMoney = ['awaiting', 'failed', 'expired'].contains(status);
    final isOrganiser = order.buyerUid == uid;
    final canPay = awaitsMoney && stageOf(order.status) == 'created' && isOrganiser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: EtStatusChip(text: title, tone: tone, icon: Icons.credit_card),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(note, style: context.texts.bodySmall?.copyWith(color: context.et.inkDim)),
        ],
        if (canPay) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _paying ? null : () => _pay(order),
            icon: const Icon(Icons.credit_card, size: 18),
            label: Text(_paying ? 'Открываем оплату…' : 'Оплатить ${formatTenge(orderTotal(order))}'),
          ),
        ],
        if (!isOrganiser && order.group != null && awaitsMoney) ...[
          const SizedBox(height: 8),
          Text(
            'Оплачивает организатор — одной суммой за всех. Свою долю переведите ему.',
            style: context.texts.bodySmall?.copyWith(color: context.et.inkDim),
          ),
        ],
        // Фискальный чек. Выбивает его касса ХОЗЯЙСТВА, под его БИН: продавец мяса — оно, а не
        // платформа. Печатать нам нечего, зато по ссылке открывается тот же документ, что ушёл
        // в налоговую, — это сильнее бумажки.
        if (order.fiscal?.issued == true) ...[
          const SizedBox(height: 12),
          _receiptLink('чек', order.fiscal!),
        ],
        if (order.fiscalReturn?.issued == true) ...[
          const SizedBox(height: 8),
          _receiptLink('чек возврата', order.fiscalReturn!),
        ],
      ],
    );
  }

  /// Строка с чеком. Пока контур re:Kassa тестовый, чек так и называется — «Тестовый чек»:
  /// по ссылке откроется документ, которого налоговая не видела, и выдавать его за фискальный
  /// нельзя. Признак приходит с сервера, вместе с самим чеком.
  Widget _receiptLink(String what, OrderFiscal fiscal) {
    final c = context.et;
    final url = fiscal.url;
    final number = fiscal.ticketNumber == null ? 'Открыть' : '№ ${fiscal.ticketNumber}';
    return InkWell(
      borderRadius: EtShape.smallRadius,
      onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 18, color: fiscal.test ? c.inkFaint : c.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fiscal.test ? 'Тестовый' : 'Фискальный'} $what',
                    style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    fiscal.test ? '$number · пробный, в налоговую не ушёл' : number,
                    style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                  ),
                ],
              ),
            ),
            if (url != null) Icon(Icons.open_in_new, size: 16, color: c.inkFaint),
          ],
        ),
      ),
    );
  }

  /// Сумма, которую платит покупатель: после контрольного взвешивания — пересчитанная.
  int orderTotal(FarmOrder order) => order.weighing?.total ?? order.amount;

  /// Уводит на страницу оплаты Freedom Pay.
  ///
  /// Во ВНЕШНЕМ браузере, а не в WebView: 3-D Secure и банковские приложения внутри WebView
  /// ломаются, и человек остаётся с белым экраном вместо подтверждения.
  ///
  /// После оплаты Freedom возвращает на /order?id=…&paid=1 — этот адрес забирает App Link, и
  /// человек оказывается на этом же экране. Если браузер ссылку не отдаст, ничего не теряется:
  /// экран читает заказ потоком, и статус оплаты меняется сам, как только придёт их вебхук.
  Future<void> _pay(FarmOrder order) async {
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final url = await _api.startPayment(order.id);
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw EtApiException('unavailable', 'Не удалось открыть страницу оплаты.');
    } on EtApiException catch (e) {
      // Отказы сервера приходят по-русски и своими словами — «Заказ уже оплачен», «По этому
      // заказу расчёт идёт напрямую с хозяйством». Их и показываем, не переписывая.
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось начать оплату. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _when(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}, ${two(local.hour)}:${two(local.minute)}';
  }
}
