import 'package:et_core/et_core.dart';
import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'order_detail_screen.dart';

/// Совместная покупка: 2-5 people splitting one carcass.
///
/// The organiser sets it up and shares the link; the join that takes the last place is what
/// creates the order for everyone. Nothing is held while it fills - a free hold on a farm's
/// carcass is not ours to give - so the page says plainly what that means.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _groups = GroupBuysRepo();
  final _catalogue = CatalogueRepo();
  final _api = EtApi();

  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _contact;
  Lot? _lot;
  String? _extrasFor;

  /// The lot, and - for the people in the gathering - the address and the organiser's phone.
  /// Keyed on membership, so joining fetches the contact that was closed a moment earlier.
  Future<void> _loadExtras(GroupBuy group, bool isMember) async {
    final key = '${group.id}:$isMember';
    if (_extrasFor == key) return;
    _extrasFor = key;
    final contact =
        isMember ? await _groups.contact(widget.groupId).catchError((_) => null) : null;
    final lot = await _catalogue.lot(group.lotId).catchError((_) => null);
    if (mounted) {
      setState(() {
        _contact = contact;
        _lot = lot;
      });
    }
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
      if (mounted) setState(() => _error = 'Не получилось. Проверьте связь.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthService>().uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Совместная покупка')),
      body: StreamBuilder<GroupBuy?>(
        stream: _groups.watch(widget.groupId),
        builder: (context, snapshot) {
          final group = snapshot.data;
          if (group == null) {
            return snapshot.connectionState == ConnectionState.waiting
                ? const Padding(
                    padding: EdgeInsets.all(EtShape.gutter),
                    child: EtSkeleton(height: 220),
                  )
                : const EtEmpty(
                    title: 'Сбор не найден',
                    text: 'Возможно, ссылка устарела.',
                    icon: Icons.search_off,
                  );
          }
          _loadExtras(group, uid != null && group.memberUids.contains(uid));
          return _body(group, uid);
        },
      ),
    );
  }

  Widget _body(GroupBuy group, String? uid) {
    final c = context.et;
    final isMember = uid != null && group.memberUids.contains(uid);
    final isCreator = uid != null && group.creatorUid == uid;

    return ListView(
      padding: const EdgeInsets.all(EtShape.gutter),
      children: [
        EtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.lotTitle.isEmpty ? 'Туша' : group.lotTitle,
                  style: context.texts.headlineSmall),
              const SizedBox(height: 6),
              Text(
                '${group.partnerName} · ${formatLabel[group.format] ?? ''} · '
                '${formatTenge(group.amount)} на всех',
                style: context.texts.bodySmall?.copyWith(color: c.inkDim),
              ),
              const SizedBox(height: 14),
              EtProgress(
                percent: group.size == 0 ? 0 : group.joined / group.size,
                label: 'Собрано ${group.joined} из ${group.size}',
                trailing: '${((group.joined / group.size) * 100).round()} %',
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < group.size; i++) _seat(group, i, uid),
            ],
          ),
        ),
        const SizedBox(height: EtShape.gap),
        _actions(group, uid, isMember, isCreator),
        if (_error != null) ...[
          const SizedBox(height: EtShape.gap),
          EtNotice(text: _error!, icon: Icons.error_outline, tone: 'danger'),
        ],
        const SizedBox(height: EtShape.gap),
        EtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Что заказываем', style: context.texts.titleSmall),
              EtRow(label: 'Хозяйство', value: group.partnerName),
              EtRow(label: 'Формат', value: formatLabel[group.format] ?? ''),
              EtRow(
                label: 'Доставка',
                value: group.deliveryMode == 'pickup'
                    ? 'самовывоз из хаба'
                    : (group.deliveryCity ?? 'по договорённости'),
              ),
              if (group.deliveryDate != null)
                EtRow(
                  label: 'Дата',
                  value: group.deliveryDate!.split('-').reversed.join('.'),
                ),
              if (_contact?['deliveryAddress'] != null)
                EtRow(label: 'Адрес', value: _contact!['deliveryAddress'].toString()),
              EtRow(label: 'Итого на всех', value: formatTenge(group.amount), strong: true),
              if (_lot != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Туша сейчас: ${availabilityLabel(_lot!).toLowerCase()}. '
                    'Пока идёт сбор, она не забронирована.',
                    style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _seat(GroupBuy group, int index, String? uid) {
    final c = context.et;
    final member = index < group.members.length ? group.members[index] : null;
    final amount = index < group.perMember.length ? group.perMember[index] : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: member == null ? c.fillTrack : c.greenTint,
            ),
            child: member == null
                ? Text('${index + 1}',
                    style: context.texts.labelMedium?.copyWith(color: c.inkFaint))
                : Icon(Icons.check, size: 16, color: c.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member == null
                      ? 'Свободное место'
                      : '${member.name}${member.uid == uid ? ' (вы)' : ''}',
                  style: context.texts.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: member == null ? c.inkFaint : c.ink,
                  ),
                ),
                Text(
                  '${index == 0 ? 'организатор · ' : ''}${formatTenge(member?.amount ?? amount)}',
                  style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(GroupBuy group, String? uid, bool isMember, bool isCreator) {
    final c = context.et;

    if (group.status == 'placed') {
      return EtCard(
        tinted: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Все собрались — заказ ушёл хозяйству.', style: context.texts.bodyMedium),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: group.orderId == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailScreen(orderId: group.orderId!),
                        ),
                      ),
              child: const Text('Открыть заказ'),
            ),
          ],
        ),
      );
    }
    if (group.status == 'failed' || group.status == 'cancelled') {
      return EtNotice(
        text: group.status == 'cancelled'
            ? 'Организатор отменил сбор. Деньги никто не вносил.'
            : 'Сбор не состоялся. ${group.failedReason ?? 'Туша больше не доступна.'} '
                'Деньги никто не вносил.',
        icon: Icons.info_outline,
        tone: 'danger',
      );
    }

    final left = group.freePlaces;
    return EtCard(
      tinted: !isMember,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMember)
            Text(
              'Вы в этой покупке. Осталось найти $left '
              '${pluralRu(left, 'человека', 'человек', 'человек')} — поделитесь ссылкой.',
              style: context.texts.bodyMedium,
            )
          else ...[
            FilledButton(
              onPressed: _busy ? null : () => _join(group),
              child: Text('Участвовать · ${formatTenge(group.shareFor(uid ?? ''))}'),
            ),
            const SizedBox(height: 6),
            Text(
              'Место закрепится за вами. Заказ уйдёт хозяйству, когда соберутся все ${group.size}.',
              style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(
                ClipboardData(text: GroupBuysRepo.linkFor(group.id)),
              );
              messenger.showSnackBar(
                const SnackBar(content: Text('Ссылка скопирована — отправьте её друзьям.')),
              );
            },
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Скопировать ссылку'),
          ),
          if (isMember) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => _leave(group, isCreator),
              child: Text(isCreator ? 'Отменить сбор' : 'Выйти из покупки'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _join(GroupBuy group) async {
    await _run(() async {
      final result = await _api.joinGroupBuy(group.id);
      // The last place places the order for everyone - go straight to it.
      if (result.orderId != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            settings: RouteSettings(name: "order/${result.orderId}"),
            builder: (_) => OrderDetailScreen(orderId: result.orderId!),
          ),
        );
      }
    });
  }

  Future<void> _leave(GroupBuy group, bool isCreator) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCreator ? 'Отменить сбор?' : 'Выйти из покупки?'),
        content: Text(
          isCreator
              ? 'Остальные участники получат уведомление, что сбор отменён.'
              : 'Ваше место освободится, и его сможет занять другой человек.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Назад')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isCreator ? 'Отменить сбор' : 'Выйти'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _api.leaveGroupBuy(group.id));
  }
}
