import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';

/// Первый экран: степь, обещание и одна кнопка.
///
/// Раньше он жил вне дизайн-системы — на CupertinoPageScaffold, со своей палитрой и своими
/// шрифтами. В отладочной сборке это было видно буквально: текст без Material рисуется жёлтым
/// подчёркиванием, и весь экран выглядел сломанным. Теперь он на общей теме: те же цвета и та же
/// типографика, что на сайте и на остальных экранах.
///
/// Фотография остаётся, но уходит под градиент: заголовок должен читаться, а не соревноваться с
/// травой. Текст лежит на сплошном фоне внизу — там, где он и читается.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.et;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // Степь занимает верхние две трети и растворяется в фоне экрана.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: ShaderMask(
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: const [0, 0.55, 1],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: Image.asset(
                'assets/images/steppe_horses_background.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => ColoredBox(color: c.greenTint),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: EtShape.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const _Brand(),
                  const Spacer(),
                  Text(
                    'Мясо со степи\nдо твоего стола.',
                    style: context.texts.displaySmall?.copyWith(height: 1.05),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Говядина и конина напрямую от проверенных хозяйств Казахстана. '
                    'Целая туша или половина — одному или вместе с друзьями.',
                    style: context.texts.bodyMedium?.copyWith(color: c.inkDim, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  const _Promises(),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text('Начать'),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Вход по номеру телефона',
                      style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final c = context.et;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: c.green, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            'ET',
            style: context.texts.labelLarge?.copyWith(color: c.onGreen, letterSpacing: 0.5),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ET', style: context.texts.titleMedium?.copyWith(color: c.green)),
            Text(
              'мясо со степи',
              style: context.texts.labelSmall?.copyWith(color: c.inkFaint, letterSpacing: 1.2),
            ),
          ],
        ),
      ],
    );
  }
}

/// Три обещания платформы — то же, что обещает первый экран сайта.
class _Promises extends StatelessWidget {
  const _Promises();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.verified_outlined, 'Проверенные хозяйства', 'СЭС и ветконтроль у каждого'),
      (Icons.photo_camera_outlined, 'Видно каждый шаг', 'Хозяйство снимает животное и мясо'),
      (Icons.groups_2_outlined, 'Можно вместе', 'Туша делится на 2–5 человек'),
    ];

    final c = context.et;
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(item.$1, size: 20, color: c.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$2,
                        style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        item.$3,
                        style: context.texts.bodySmall?.copyWith(color: c.inkFaint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
