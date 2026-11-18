import 'package:shared_preferences/shared_preferences.dart';

/// Bewaart handmatig toegevoegde printers (IP of hostnaam) op het toestel.
class ManualPrinterStore {
  static const _key = 'manual_printers';

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<void> add(String entry) async {
    final list = await load();
    if (!list.contains(entry)) {
      list.add(entry);
      await (await SharedPreferences.getInstance()).setStringList(_key, list);
    }
  }

  Future<void> remove(String entry) async {
    final list = await load()..remove(entry);
    await (await SharedPreferences.getInstance()).setStringList(_key, list);
  }
}
