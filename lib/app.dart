import 'package:flutter/material.dart';

import 'sessions/session_manager.dart';
import 'storage/repository.dart';
import 'theme/mhrd_theme.dart';
import 'ui/home_screen.dart';

/// Доступ до сервісів з будь-якого віджета: `AppScope.of(context).repo`.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.repo, required this.sessions, required super.child});

  final Repository repo;
  final SessionManager sessions;

  static AppScope of(BuildContext context) {
    final s = context.getInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope не знайдено');
    return s!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => repo != oldWidget.repo || sessions != oldWidget.sessions;
}

class MhrdApp extends StatelessWidget {
  const MhrdApp({super.key, required this.repo, required this.sessions});

  final Repository repo;
  final SessionManager sessions;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repo: repo,
      sessions: sessions,
      child: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final platform = MediaQuery.platformBrightnessOf(context);
          final tokens = repo.themeFor(platform);
          return MaterialApp(
            title: 'MHRD',
            debugShowCheckedModeBanner: false,
            theme: tokens.toThemeData(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(tokens.textScale),
                disableAnimations: tokens.motion == MotionLevel.off ||
                    MediaQuery.of(context).disableAnimations,
              ),
              child: child!,
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
