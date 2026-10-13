import 'package:et_core/et_core.dart';
import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'group_screen.dart';
import 'order_detail_screen.dart';

/// The buyer's orders.
///
/// Both kinds: the orders of the current flow, and the ones this person is in as a participant of
/// a joint purchase - they follow the same deal, the organiser decides it.
class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthService>().uid;
    if (uid == null) return const SizedBox.shrink();
    final repo = OrdersRepo();

    return Scaffold(
      appBar: AppBar(title: const Text('Мои заказы')),
      body: StreamBuilder<List<GroupBuy>>(
        stream: GroupBuysRepo().mine(uid),
        builder: (context, groups) {
          final open = (groups.data ?? const <GroupBuy>[]).where((g) => g.isOpen).toList();
          return StreamBuilder<List<FarmOrder>>(
            stream: repo.forBuyer(uid),
            builder: (context, mine) {
              return StreamBuilder<List<FarmOrder>>(
                stream: repo.sharedWith(uid),
                builder: (context, shared) {
                  if (mine.hasError) {
                    return const EtEmpty(
                      title: 'Не удалось загрузить заказы',
                      text: 'Проверьте связь.',
                      icon: Icons.cloud_off,
                    );
                  }
                  if (!mine.hasData) {
                    return ListView(
                      padding: const EdgeInsets.all(EtShape.gutter),
                      children: const [
                        EtSkeleton(height: 130),
                        SizedBox(height: EtShape.gap),
                        EtSkeleton(height: 130),
                      ],
                    );
                  }

                  final orders = [...mine.data!, ...(shared.data ?? const <FarmOrder>[])]
                    ..sort(
                      (a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
                    );
                  // A gathering that is still filling is not an order yet, but it is the thing
                  // this person is waiting on - so it counts against the empty screen.
                  if (orders.isEmpty && open.isEmpty) {
                    return const EtEmpty(
                      title: 'Заказов пока нет',
                      illustrated: true,
                      text:
                          'Выберите тушу — половину или целую — и оформите заказ. '
                          'Каждый шаг хозяйства будет виден здесь.',
                      icon: Icons.shopping_basket_outlined,
                    );
                  }

                  final active = orders.where((o) => !isFinished(o)).toList();
                  final done = orders.where(isFinished).toList();

                  return ListView(
                    padding: const EdgeInsets.all(EtShape.gutter),
                    children: [
                      if (open.isNotEmpty) _OpenGroups(groups: open, uid: uid),
                      if (active.isNotEmpty) ...[
                        const EtEyebrow('В работе'),
                        const SizedBox(height: 10),
                        for (var i = 0; i < active.length; i++)
                          EtReveal(index: i, child: _Card(order: active[i], uid: uid)),
                      ],
                      if (done.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const EtEyebrow('Завершённые и отменённые'),
                        const SizedBox(height: 10),
                        for (var i = 0; i < done.length; i++)
                          EtReveal(index: i, child: _Card(order: done[i], uid: uid)),
                      ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.order, required this.uid});

  final FarmOrder order;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final c = context.et;
    final isMine = order.buyerUid == uid;
    final share = order.group?.members.where((m) => m.uid == uid).map((m) => m.amount).firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: EtShape.gap),
      child: EtCard(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(
          settings: RouteSettings(name: "order/${order.id}"),
          builder: (_) => OrderDetailScreen(orderId: order.id),
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.lotTitle.isEmpty ? 'Заказ' : order.lotTitle,
              style: context.texts.titleMedium,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: EtStatusChip(
                text: statusTextForBuyer(order),
                tone: statusTone(order),
                icon: etStageIcon(order.status),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${orderSummary(format: order.format, estimatedWeightKg: order.estimatedWeightKg, shares: order.shares)}'
              ' · ${formatTenge(share ?? order.total)}',
              style: context.texts.bodySmall?.copyWith(color: c.inkDim),
            ),
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Совместная покупка · ваша доля',
                  style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  order.delivery.isPickup ? Icons.store_outlined : Icons.local_shipping_outlined,
                  size: 16,
                  color: c.inkFaint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.delivery.isPickup
                        ? 'Самовывоз из хаба'
                        : (order.deliveryAddress.isEmpty
                              ? 'Адрес не указан'
                              : order.deliveryAddress),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                  ),
                ),
                Icon(Icons.arrow_forward, size: 18, color: c.green),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Gatherings that are still filling. They are not orders yet - the order appears when the last
/// place is taken - so they sit above the orders, where the person left them.
class _OpenGroups extends StatelessWidget {
  const _OpenGroups({required this.groups, required this.uid});

  final List<GroupBuy> groups;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EtEyebrow('Идёт сбор'),
        const SizedBox(height: 10),
        for (final group in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: EtShape.gap),
            child: EtCard(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => GroupScreen(groupId: group.id))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.lotTitle.isEmpty ? 'Туша' : group.lotTitle,
                    style: context.texts.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  EtProgress(
                    percent: group.size == 0 ? 0 : group.joined / group.size,
                    label: 'Совместная покупка · собрано ${group.joined} из ${group.size}',
                    trailing: formatTenge(group.shareFor(uid)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group.creatorUid == uid
                        ? 'Вы организатор — позовите ещё участников'
                        : 'Вы участник этого сбора',
                    style: context.texts.bodySmall?.copyWith(color: context.et.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
