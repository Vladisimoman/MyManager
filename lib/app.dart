import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'features/notifications/notifications.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/security/lock_screen.dart';

class MyManagerApp extends StatelessWidget {
  const MyManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyManager',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: buildAppTheme(),
      locale: const Locale('uk'),
      supportedLocales: const [Locale('uk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // PIN (етап 13) закриває будь-який екран, поки додаток замкнено.
      builder: (context, child) =>
          AppWidthLimit(child: LockGate(child: child ?? const SizedBox())),
      home: const StartGate(),
    );
  }
}

/// Найбільша ширина інтерфейсу. На широкому екрані (браузер на комп'ютері)
/// додаток стоїть по центру, як на телефоні (етап 21). На телефоні нічого
/// не змінюється.
const appMaxWidth = 600.0;

class AppWidthLimit extends StatelessWidget {
  const AppWidthLimit({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= appMaxWidth) return child;
    final width = math.min(mq.size.width, appMaxWidth);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Center(
        child: SizedBox(
          width: width,
          // Екрани, що беруть ширину з MediaQuery, бачать саме цю колонку.
          child: MediaQuery(
            data: mq.copyWith(size: Size(width, mq.size.height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
