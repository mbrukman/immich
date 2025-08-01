import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/codegen_loader.g.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/share_intent_upload.provider.dart';
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/providers/theme.provider.dart';
import 'package:immich_mobile/routing/app_navigation_observer.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/background.service.dart';
import 'package:immich_mobile/services/deep_link.service.dart';
import 'package:immich_mobile/services/local_notification.service.dart';
import 'package:immich_mobile/theme/dynamic_theme.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/utils/bootstrap.dart';
import 'package:immich_mobile/utils/cache/widgets_binding.dart';
import 'package:immich_mobile/utils/http_ssl_options.dart';
import 'package:immich_mobile/utils/licenses.dart';
import 'package:immich_mobile/utils/migration.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest.dart';
import 'package:worker_manager/worker_manager.dart';

void main() async {
  ImmichWidgetsBinding();
  final db = await Bootstrap.initIsar();
  await Bootstrap.initDomain(db);
  await initApp();
  // Warm-up isolate pool for worker manager
  await workerManager.init(dynamicSpawning: true);
  await migrateDatabaseIfNeeded(db);
  HttpSSLOptions.apply();

  runApp(
    ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        isarProvider.overrideWithValue(db),
      ],
      child: const MainWidget(),
    ),
  );
}

Future<void> initApp() async {
  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting();

  if (kReleaseMode && Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
      debugPrint("Enabled high refresh mode");
    } catch (e) {
      debugPrint("Error setting high refresh rate: $e");
    }
  }

  await DynamicTheme.fetchSystemPalette();

  final log = Logger("ImmichErrorLogger");

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.severe(
      'FlutterError - Catch all',
      "${details.toString()}\nException: ${details.exception}\nLibrary: ${details.library}\nContext: ${details.context}",
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint("FlutterError - Catch all: $error \n $stack");
    log.severe('PlatformDispatcher - Catch all', error, stack);
    return true;
  };

  initializeTimeZones();

  // Initialize the file downloader

  await FileDownloader().configure(
    // maxConcurrent: 6, maxConcurrentByHost(server):6, maxConcurrentByGroup: 3
    globalConfig: (Config.holdingQueue, (6, 6, 3)),
  );

  await FileDownloader().trackTasksInGroup(
    kDownloadGroupLivePhoto,
    markDownloadedComplete: false,
  );

  await FileDownloader().trackTasks();

  LicenseRegistry.addLicense(
    () async* {
      for (final license in nonPubLicenses.entries) {
        yield LicenseEntryWithLineBreaks(
          [license.key],
          license.value,
        );
      }
    },
  );
}

class ImmichApp extends ConsumerStatefulWidget {
  const ImmichApp({super.key});

  @override
  ImmichAppState createState() => ImmichAppState();
}

class ImmichAppState extends ConsumerState<ImmichApp> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint("[APP STATE] resumed");
        ref.read(appStateProvider.notifier).handleAppResume();
        break;
      case AppLifecycleState.inactive:
        debugPrint("[APP STATE] inactive");
        ref.read(appStateProvider.notifier).handleAppInactivity();
        break;
      case AppLifecycleState.paused:
        debugPrint("[APP STATE] paused");
        ref.read(appStateProvider.notifier).handleAppPause();
        break;
      case AppLifecycleState.detached:
        debugPrint("[APP STATE] detached");
        ref.read(appStateProvider.notifier).handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        debugPrint("[APP STATE] hidden");
        ref.read(appStateProvider.notifier).handleAppHidden();
        break;
    }
  }

  Future<void> initApp() async {
    WidgetsBinding.instance.addObserver(this);

    // Draw the app from edge to edge
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Sets the navigation bar color
    SystemUiOverlayStyle overlayStyle = const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    );
    if (Platform.isAndroid) {
      // Android 8 does not support transparent app bars
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt <= 26) {
        overlayStyle = context.isDarkTheme ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light;
      }
    }
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
    await ref.read(localNotificationService).setup();
  }

  void _configureFileDownloaderNotifications() {
    FileDownloader().configureNotificationForGroup(
      kDownloadGroupImage,
      running: TaskNotification(
        'downloading_media'.tr(),
        '${'file_name'.tr()}: {filename}',
      ),
      complete: TaskNotification(
        'download_finished'.tr(),
        '${'file_name'.tr()}: {filename}',
      ),
      progressBar: true,
    );

    FileDownloader().configureNotificationForGroup(
      kDownloadGroupVideo,
      running: TaskNotification(
        'downloading_media'.tr(),
        '${'file_name'.tr()}: {filename}',
      ),
      complete: TaskNotification(
        'download_finished'.tr(),
        '${'file_name'.tr()}: {filename}',
      ),
      progressBar: true,
    );

    FileDownloader().configureNotificationForGroup(
      kManualUploadGroup,
      running: TaskNotification(
        'uploading_media'.tr(),
        '${'file_name'.tr()}: {displayName}',
      ),
      complete: TaskNotification(
        'upload_finished'.tr(),
        '${'file_name'.tr()}: {displayName}',
      ),
      progressBar: true,
    );
  }

  Future<DeepLink> _deepLinkBuilder(PlatformDeepLink deepLink) async {
    final deepLinkHandler = ref.read(deepLinkServiceProvider);
    final currentRouteName = ref.read(currentRouteNameProvider.notifier).state;

    final isColdStart = currentRouteName == null || currentRouteName == SplashScreenRoute.name;

    if (deepLink.uri.scheme == "immich") {
      final proposedRoute = await deepLinkHandler.handleScheme(
        deepLink,
        isColdStart,
      );

      return proposedRoute;
    }

    if (deepLink.uri.host == "my.immich.app") {
      final proposedRoute = await deepLinkHandler.handleMyImmichApp(
        deepLink,
        isColdStart,
      );

      return proposedRoute;
    }

    return DeepLink.path(deepLink.path);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Intl.defaultLocale = context.locale.toLanguageTag();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _configureFileDownloaderNotifications();
    });
  }

  @override
  initState() {
    super.initState();
    initApp().then((_) => debugPrint("App Init Completed"));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // needs to be delayed so that EasyLocalization is working
      ref.read(backgroundServiceProvider).resumeServiceIfEnabled();
    });

    ref.read(shareIntentUploadProvider.notifier).init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final immichTheme = ref.watch(immichThemeProvider);

    return ProviderScope(
      overrides: [
        localeProvider.overrideWithValue(context.locale),
      ],
      child: MaterialApp.router(
        title: 'Immich',
        debugShowCheckedModeBanner: true,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        themeMode: ref.watch(immichThemeModeProvider),
        darkTheme: getThemeData(
          colorScheme: immichTheme.dark,
          locale: context.locale,
        ),
        theme: getThemeData(
          colorScheme: immichTheme.light,
          locale: context.locale,
        ),
        routerConfig: router.config(
          deepLinkBuilder: _deepLinkBuilder,
          navigatorObservers: () => [AppNavigationObserver(ref: ref), HeroController()],
        ),
      ),
    );
  }
}

class MainWidget extends StatelessWidget {
  const MainWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: locales.values.toList(),
      path: translationsPath,
      useFallbackTranslations: true,
      fallbackLocale: locales.values.first,
      assetLoader: const CodegenLoader(),
      child: const ImmichApp(),
    );
  }
}
