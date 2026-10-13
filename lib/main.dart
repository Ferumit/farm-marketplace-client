import 'dart:async';
import 'package:et_core/et_core.dart';
import 'package:et_data/et_data.dart';
import 'package:et_ui/et_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/cart_screen.dart';
import 'screens/catalogue_screen.dart';
import 'screens/group_screen.dart';
import 'screens/lot_screen.dart';
import 'screens/my_orders_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/order_detail_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_profile_screen.dart';

import 'screens/registration_screen.dart';
import 'screens/welcome_screen.dart';
import 'models/user_profile.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // A debug build started with --dart-define=ET_EMULATOR=true talks to the local Firebase
    // emulators instead of the live project, so a whole deal can be walked without touching a
    // real farm. Release builds always go to production.
    await EtFirebase.init(DefaultFirebaseOptions.currentPlatform);

    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestProvider(),
    );

    // ─── Crashlytics setup ───────────────────────────────────────
    // Crashlytics alone would swallow the message: the default handler is what prints a layout
    // error to the console, and without it a broken screen just renders blank while debugging.
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      if (kDebugMode) FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

    runApp(const ETApp());
  }, (error, stack) {
    // Catches anything outside Flutter's own error zone (e.g. errors in
    // bare, unawaited Futures) that the handlers above would otherwise miss.
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class ETApp extends StatelessWidget {
  const ETApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => FirestoreService()),
      ],
      // Material, not Cupertino: the new design is the website's - its palette, its type and its
      // parts (package et_ui) - and it brings a dark theme this app never had. The Cupertino
      // widgets the older screens use keep working inside it while they are rebuilt one by one.
      child: MaterialApp(
        title: 'ET',
        debugShowCheckedModeBanner: false,
        theme: EtTheme.light(),
        darkTheme: EtTheme.dark(),
        themeMode: ThemeMode.system,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ru', ''),
          Locale('en', ''),
        ],
        home: const AuthGate(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/market': (context) => const MainNavigation(),
          '/profile': (context) => const SettingsProfileScreen(),
        },
      ),
    );
  }
}

/// Routes the user to Login or MainNavigation based on auth state.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Имя, которым приложение само называло человека, когда профиль создавался молча. Оно
  /// попадало и в заказ хозяйству, и в список совместной покупки: «Пользователь» вместо имени.
  static const _placeholder = 'Пользователь';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.isLoggedIn || auth.uid == null) {
      return const WelcomeScreen();
    }

    FirebaseCrashlytics.instance.setUserIdentifier(auth.uid!);

    return StreamBuilder<UserProfile?>(
      stream: context.read<FirestoreService>().userProfileStream(auth.uid!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: context.et.bg,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snapshot.data;
        final name = (profile?.displayName ?? '').trim();

        // Профиля нет или в нём стоит имя-заглушка — сначала знакомство. Раньше приложение
        // создавало профиль само и вело человека прямо в каталог, а хозяйство потом получало
        // заказ от «Пользователя».
        if (profile == null || name.isEmpty || name == _placeholder) {
          return const RegistrationScreen();
        }

        return const MainNavigation();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  /// Switches the bottom tab from anywhere in the widget tree.
  /// Uses the nearest [_MainNavigationState] ancestor.
  static void switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_MainNavigationState>();
    state?._goTo(index);
  }

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with _PushRouting {
  int _index = 0;

  /// Lets any screen send the person to another tab - after an order is placed, to «Заказы».
  void _goTo(int index) => setState(() => _index = index);

  @override
  void initState() {
    super.initState();
    listenForPushes();
    listenForLinks();
  }

  @override
  void dispose() {
    stopListeningForPushes();
    stopListeningForLinks();
    super.dispose();
  }

  /// Ссылка с сайта. Открывается ровно то, что в ней названо; неизвестный адрес ведёт в
  /// каталог, а не в пустой экран.
  @override
  void openLink(LinkTarget target) {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    switch (target.kind) {
      case 'group':
        navigator.push(MaterialPageRoute(builder: (_) => GroupScreen(groupId: target.id!)));
      case 'lot':
        navigator.push(MaterialPageRoute(builder: (_) => LotScreen(lotId: target.id!)));
      case 'order':
        if (target.id != null) {
          // Возврат с оплаты приходит на тот заказ, с которого человек на неё и ушёл, — то есть
          // чаще всего он уже открыт. Положить поверх копию значило бы показать два одинаковых
          // заказа, между которыми «назад» ходит по кругу. Если экран уже в стопке — поднимаем
          // его, а не заводим второй.
          final name = 'order/${target.id}';
          var open = false;
          navigator.popUntil((route) {
            if (route.settings.name == name) open = true;
            return true; // ничего не снимаем, только смотрим
          });
          if (open) {
            navigator.popUntil((route) => route.settings.name == name);
          } else {
            navigator.push(MaterialPageRoute(
              settings: RouteSettings(name: name),
              builder: (_) => OrderDetailScreen(orderId: target.id!),
            ));
          }
        } else {
          _goTo(2);
        }
      case 'lots':
      default:
        _goTo(0);
    }
  }

  /// A push names what it is about. The screen is opened fresh from Firestore - the message
  /// itself is only a knock, and may be late, repeated or half-delivered.
  @override
  void openPush(PushTarget target) {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (target.isOrder) {
      navigator.push(MaterialPageRoute(
        settings: RouteSettings(name: "order/${target.orderId}"),
        builder: (_) => OrderDetailScreen(orderId: target.orderId!),
      ));
    } else if (target.isGroup) {
      navigator.push(MaterialPageRoute(builder: (_) => GroupScreen(groupId: target.groupId!)));
    } else {
      navigator.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          CatalogueScreen(),
          CartScreen(),
          MyOrdersScreen(),
          SettingsProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.et.surfaceRaised,
          border: Border(top: BorderSide(color: context.et.line)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              indicatorColor: context.et.greenTint,
              labelTextStyle: WidgetStatePropertyAll(
                context.texts.labelSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              height: 68,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.storefront_outlined, color: context.et.inkFaint),
                  selectedIcon: Icon(Icons.storefront, color: context.et.green),
                  label: 'Каталог',
                ),
                NavigationDestination(
                  icon: _CartIcon(uid: context.read<AuthService>().uid),
                  selectedIcon: _CartIcon(uid: context.read<AuthService>().uid, active: true),
                  label: 'Корзина',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined, color: context.et.inkFaint),
                  selectedIcon: Icon(Icons.receipt_long, color: context.et.green),
                  label: 'Заказы',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline, color: context.et.inkFaint),
                  selectedIcon: Icon(Icons.person, color: context.et.green),
                  label: 'Профиль',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}




/// The cart icon with the number of carcasses waiting in it.
///
/// A count that lags reads as a bug, so it comes from the same live stream the cart screen
/// itself uses rather than from a value someone remembered to refresh.
class _CartIcon extends StatelessWidget {
  const _CartIcon({this.uid, this.active = false});

  final String? uid;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colour = active ? context.et.green : context.et.inkFaint;
    final icon = Icon(active ? Icons.shopping_basket : Icons.shopping_basket_outlined, color: colour);
    if (uid == null) return icon;

    return StreamBuilder<int>(
      stream: CartRepo().count(uid!),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) return icon;
        return Badge(
          label: Text('$count'),
          backgroundColor: context.et.green,
          child: icon,
        );
      },
    );
  }
}

/// Push, once the app is on screen: a tap opens what it is about, and a message that arrives
/// while the person is already looking gets a line at the bottom rather than nothing at all
/// (Android shows no notification of its own while the app is in front).
mixin _PushRouting<T extends StatefulWidget> on State<T> {
  final Push _push = Push();
  final DeepLinks _links = DeepLinks();
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _inApp;
  StreamSubscription<LinkTarget>? _linked;

  void openPush(PushTarget target);
  void openLink(LinkTarget target);

  /// Ссылка, которой приложение запустили, и ссылки, пришедшие в уже открытое, ведут в одно
  /// место: человек не знает, было ли приложение в памяти, и не должен узнавать это по тому,
  /// куда он попал.
  void listenForLinks() {
    _linked = _links.stream.listen(openLink);
    _links.initial().then((target) {
      if (target != null && !target.isEmpty && mounted) openLink(target);
    });
  }

  void stopListeningForLinks() => _linked?.cancel();

  void listenForPushes() {
    _opened = _push.opened.listen((message) => openPush(PushTarget.of(message)));
    _inApp = _push.whileOpen.listen(_announce);
    // Started by tapping a notification: the message that did it arrives once.
    _push.launchMessage().then((message) {
      if (message != null && mounted) openPush(PushTarget.of(message));
    });
  }

  void stopListeningForPushes() {
    _opened?.cancel();
    _inApp?.cancel();
  }

  void _announce(RemoteMessage message) {
    if (!mounted) return;
    final target = PushTarget.of(message);
    final title = target.title ?? '';
    final body = target.body ?? '';
    if (title.isEmpty && body.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text([title, body].where((s) => s.isNotEmpty).join(' — ')),
        action: SnackBarAction(label: 'Открыть', onPressed: () => openPush(target)),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
