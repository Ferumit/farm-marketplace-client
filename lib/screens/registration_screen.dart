import 'package:et_ui/et_ui.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Знакомство после входа: как к вам обращаться и куда возить мясо.
///
/// Переписано на общую дизайн-систему. Спрашивается ровно два поля — всё остальное платформа
/// знает и так: номер подтверждён при входе, адрес доставки указывается при заказе, а ИИН у
/// покупателя не спрашивается вовсе.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    if (auth.uid == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<FirestoreService>().createUserProfile(
            UserProfile(
              uid: auth.uid!,
              phone: auth.phone ?? '',
              role: 'client',
              displayName: _name.text.trim(),
              city: _city.text.trim().isEmpty ? null : _city.text.trim(),
              status: 'active',
              createdAt: DateTime.now(),
            ),
          );
      // Дальше AuthGate сам переключит на каталог.
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
      if (mounted) setState(() => _error = 'Не удалось сохранить. Проверьте связь.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.et;
    final phone = context.watch<AuthService>().phone ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Знакомство')),
      body: ListView(
        padding: const EdgeInsets.all(EtShape.gutter),
        children: [
          Text('Как к вам обращаться?', style: context.texts.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Имя увидит хозяйство, у которого вы закажете мясо, — чтобы знать, кого встречать.',
            style: context.texts.bodyMedium?.copyWith(color: c.inkDim),
          ),
          const SizedBox(height: 20),
          EtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    hintText: 'Асхат',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _city,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Город',
                    helperText: 'Покажем туши, которые довезут к вам',
                    counterText: '',
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  EtRow(label: 'Телефон', value: phone),
                ],
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: EtShape.gap),
            EtNotice(text: _error!, icon: Icons.error_outline, tone: 'danger'),
          ],
          const SizedBox(height: EtShape.gap),
          FilledButton(
            onPressed: _busy || _name.text.trim().length < 2 ? null : _save,
            child: Text(_busy ? 'Минуту…' : 'Готово'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
