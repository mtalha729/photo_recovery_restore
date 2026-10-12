import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppPreferenceState {
  const AppPreferenceState({
    this.themeMode = ThemeMode.system,
    this.reduceMotion = false,
  });

  final ThemeMode themeMode;
  final bool reduceMotion;
}

abstract interface class AppPreferencesStore {
  Future<AppPreferenceState> load();
  Future<void> save(AppPreferenceState state);
  Future<List<String>> authorizedFolders();
  Future<String> appVersion();
}

class PlatformAppPreferencesStore implements AppPreferencesStore {
  PlatformAppPreferencesStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.photorecoveryrestore.app/settings';
  final MethodChannel _channel;

  @override
  Future<AppPreferenceState> load() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('load');
      return AppPreferenceState(
        themeMode: switch (raw?['themeMode']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        reduceMotion: raw?['reduceMotion'] == true,
      );
    } on PlatformException {
      return const AppPreferenceState();
    } on MissingPluginException {
      return const AppPreferenceState();
    }
  }

  @override
  Future<void> save(AppPreferenceState state) async {
    try {
      await _channel.invokeMethod<void>('save', {
        'themeMode': state.themeMode.name,
        'reduceMotion': state.reduceMotion,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<List<String>> authorizedFolders() async {
    try {
      return await _channel.invokeListMethod<String>('authorizedFolders') ??
          const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<String> appVersion() async {
    try {
      return await _channel.invokeMethod<String>('appVersion') ?? 'Unavailable';
    } on PlatformException {
      return 'Unavailable';
    } on MissingPluginException {
      return 'Unavailable';
    }
  }
}

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController(this.store);
  final AppPreferencesStore store;

  AppPreferenceState state = const AppPreferenceState();

  Future<void> load() async {
    state = await store.load();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) => _update(
    AppPreferenceState(themeMode: value, reduceMotion: state.reduceMotion),
  );

  Future<void> setReduceMotion(bool value) => _update(
    AppPreferenceState(themeMode: state.themeMode, reduceMotion: value),
  );

  Future<void> _update(AppPreferenceState value) async {
    state = value;
    notifyListeners();
    await store.save(value);
  }
}
