import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'notifications_screen.dart';

/// «Профиль» покупателя: кто он на платформе и всё, что он может о себе решить.
///
/// Включая удаление аккаунта — Google Play требует, чтобы это делалось из приложения, а не
/// письмом в поддержку. Сервер решает, можно ли: незакрытая сделка держит аккаунт, и об этом
/// человек узнаёт словами, а не кодом ошибки.
class SettingsProfileScreen extends StatelessWidget {
  const SettingsProfileScreen({super.key});

  // Опубликованные документы — те же, на которые ссылается подвал сайта и карточка в Play.
  static const _termsUrl = 'https://example.kz/legal/terms-et-client';
  static const _privacyUrl = 'https://example.kz/legal/privacy-et-client';
  static const _deletionUrl = 'https://example.kz/legal/delete-account-et';
  static const _supportEmail = 'deploy@example.kz';
  static const _supportPhone = '+7 777 756-43-29';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final uid = auth.uid;
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: StreamBuilder<UserProfile?>(
        stream: context.read<FirestoreService>().userProfileStream(uid),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(EtShape.gutter),
            children: [
              _header(context, profile, auth.phone),
              const SizedBox(height: EtShape.gap),
              _links(context, uid),
              const SizedBox(height: EtShape.gap),
              _legal(context),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Выйти из аккаунта'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _delete(context, uid),
                style: TextButton.styleFrom(foregroundColor: context.et.danger),
                child: const Text('Удалить аккаунт'),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, UserProfile? profile, String? phone) {
    final c = context.et;
    final name = (profile?.displayName ?? '').trim();
    return EtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name.isEmpty ? 'Покупатель' : name, style: context.texts.headlineSmall),
          const SizedBox(height: 6),
          Text(
            [phone ?? '', profile?.city ?? ''].where((s) => s.isNotEmpty).join(' · '),
            style: context.texts.bodySmall?.copyWith(color: c.inkDim),
          ),
          const SizedBox(height: 10),
          Text(
            'Номер — это вход в аккаунт. Чтобы сменить его, напишите в поддержку.',
            style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _links(BuildContext context, String uid) {
    return EtCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _row(
            context,
            icon: Icons.notifications_none,
            title: 'Уведомления',
            sub: 'Шаги по заказам и решения платформы',
            trailing: StreamBuilder<int>(
              stream: NotificationsRepo().unreadCount(uid),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                if (count == 0) return const SizedBox.shrink();
                return EtStatusChip(text: '$count', tone: 'waiting');
              },
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          _row(
            context,
            icon: Icons.support_agent_outlined,
            title: 'Поддержка',
            sub: _supportEmail,
            onTap: () => _support(context),
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _legal(BuildContext context) {
    return EtCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _row(
            context,
            icon: Icons.description_outlined,
            title: 'Условия использования',
            sub: 'Как устроены заказы, оплата и возвраты',
            onTap: () => _open(_termsUrl),
          ),
          _row(
            context,
            icon: Icons.shield_outlined,
            title: 'Политика конфиденциальности',
            sub: 'Какие данные собираются и зачем',
            onTap: () => _open(_privacyUrl),
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
    Widget? trailing,
    bool last = false,
  }) {
    final c = context.et;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(sub, style: context.texts.bodySmall?.copyWith(color: c.inkFaint)),
                ],
              ),
            ),
            if (trailing != null) ...[trailing, const SizedBox(width: 8)],
            Icon(Icons.chevron_right, color: c.inkFaint),
          ],
        ),
      ),
    );
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _support(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EtShape.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Поддержка', style: context.texts.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Ответ в течение 1–2 рабочих дней.',
                style: context.texts.bodySmall?.copyWith(color: context.et.inkDim),
              ),
              const SizedBox(height: 14),
              EtRow(label: 'Почта', value: _supportEmail),
              EtRow(label: 'Телефон', value: _supportPhone),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => _open('mailto:$_supportEmail'),
                child: const Text('Написать письмо'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final auth = context.read<AuthService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Заказы останутся на месте — войти можно тем же номером.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Назад')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok == true) await auth.signOut();
  }

  void _delete(BuildContext context, String uid) {
    final auth = context.read<AuthService>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EtDeleteAccountScreen(
          note: 'Пока идёт заказ или сбор совместной покупки, аккаунт удалить нельзя: '
              'у сделки две стороны. То же самое можно сделать на сайте: $_deletionUrl',
          goes: const [
            'Профиль, имя и город',
            'Корзина и сохранённые телефоны для уведомлений',
            'Все уведомления',
            'Сам вход по этому номеру',
          ],
          stays: const [
            'Закрытые заказы — это запись о деньгах, и она принадлежит обеим сторонам. '
                'Ваш телефон и адрес из них стираются.',
            'Отзывы, которые вы оставили: из них сложился рейтинг хозяйства. Имя заменяется '
                'на «Покупатель».',
          ],
          onDelete: () async {
            try {
              await EtApi().deleteMyAccount(role: 'buyer');
              await auth.signOut();
              return null;
            } on EtApiException catch (e) {
              return e.message;
            } catch (_) {
              return 'Не удалось удалить аккаунт. Проверьте связь и попробуйте ещё раз.';
            }
          },
        ),
      ),
    );
  }
}
