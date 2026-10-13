import 'dart:io';

import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// «Личные данные» покупателя: имя, город и фотография.
///
/// Переписано на общую дизайн-систему. Номер здесь не меняется: им подтверждён вход, и смена
/// номера — это смена аккаунта, а не поля в форме.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _uploads = Uploads();
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.displayName ?? '');
  late final TextEditingController _city =
      TextEditingController(text: widget.profile.city ?? '');

  File? _avatar;
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

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _avatar = File(picked.path));
  }

  Future<void> _save() async {
    final uid = context.read<AuthService>().uid;
    final firestore = context.read<FirestoreService>();
    if (uid == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'displayName': _name.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
      };
      if (_avatar != null) {
        data['avatarUrl'] = await _uploads.media(
          path: 'clients/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
          file: _avatar!,
        );
      }
      await firestore.updateUserProfile(uid, data);
      if (mounted) Navigator.of(context).pop();
    } on UploadRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
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

    return Scaffold(
      appBar: AppBar(title: const Text('Личные данные')),
      body: ListView(
        padding: const EdgeInsets.all(EtShape.gutter),
        children: [
          Center(
            child: Column(
              children: [
                _avatarCircle(),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _pickAvatar,
                  child: Text(_avatar == null ? 'Выбрать фото' : 'Выбрать другое'),
                ),
              ],
            ),
          ),
          const SizedBox(height: EtShape.gap),
          EtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Имя', counterText: ''),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _city,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Город', counterText: ''),
                ),
                const SizedBox(height: 14),
                EtRow(label: 'Телефон', value: widget.profile.phone),
                Text(
                  'Номер — это вход в аккаунт. Чтобы сменить его, напишите в поддержку.',
                  style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                ),
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
            child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _avatarCircle() {
    final c = context.et;
    final url = widget.profile.avatarUrl;
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        color: c.greenTint,
        shape: BoxShape.circle,
        image: _avatar != null
            ? DecorationImage(image: FileImage(_avatar!), fit: BoxFit.cover)
            : (url != null && url.isNotEmpty
                ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
                : null),
      ),
      alignment: Alignment.center,
      child: _avatar == null && (url == null || url.isEmpty)
          ? Icon(Icons.person_outline, size: 44, color: c.green)
          : null,
    );
  }
}
