import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:nsd/nsd.dart' as nsd;

import 'printer.dart';

/// Zoekt printers op twee manieren tegelijk:
///  1. Bonjour/mDNS: printers kondigen zichzelf aan (_ipp, _ipps, _pdl-datastream, _printer).
///  2. Netwerkscan: elk adres in het /24-subnet wordt geprobeerd op poort 9100 en 631.
///     Dat vangt ook printers die mDNS uit hebben staan.
class PrinterDiscovery {
  static const _serviceTypes = <String, String>{
    '_ipp._tcp': 'IPP',
    '_ipps._tcp': 'IPPS',
    '_pdl-datastream._tcp': 'RAW (9100)',
    '_printer._tcp': 'LPD',
  };

  static const _scanPorts = <int, String>{
    9100: 'RAW (9100)',
    631: 'IPP',
  };

  final _printers = <String, DiscoveredPrinter>{};
  final _controller = StreamController<List<DiscoveredPrinter>>.broadcast();
  final _discoveries = <nsd.Discovery>[];
  bool _cancelScan = false;

  Stream<List<DiscoveredPrinter>> get printers => _controller.stream;

  void _emit() {
    final list = _printers.values.toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    _controller.add(list);
  }

  DiscoveredPrinter _get(String ip) =>
      _printers.putIfAbsent(ip, () => DiscoveredPrinter(ip: ip));

  // ---------- 1. Bonjour / mDNS ----------

  Future<void> startBonjour() async {
    for (final entry in _serviceTypes.entries) {
      try {
        final d = await nsd.startDiscovery(entry.key, ipLookupType: nsd.IpLookupType.v4);
        d.addServiceListener((service, status) {
          if (status == nsd.ServiceStatus.found) _onService(service, entry.value);
        });
        _discoveries.add(d);
      } catch (_) {
        // Servicetype niet ondersteund op dit apparaat: overslaan.
      }
    }
  }

  void _onService(nsd.Service s, String protocol) {
    final addrs = s.addresses ?? const <InternetAddress>[];
    if (addrs.isEmpty) return;
    final ip = addrs
        .firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => addrs.first)
        .address;

    final p = _get(ip)
      ..name ??= s.name
      ..host ??= s.host
      ..protocols.add(protocol)
      ..sources.add('Bonjour');

    final txt = _decodeTxt(s.txt);
    p.model ??= _cleanModel(txt['ty'] ?? txt['product']);
    p.adminUrl ??= txt['adminurl'];
    final note = txt['note'];
    if (note != null && note.isNotEmpty) p.location ??= note;
    _emit();
  }

  Map<String, String> _decodeTxt(Map<String, dynamic>? raw) {
    final out = <String, String>{};
    raw?.forEach((k, v) {
      if (v == null) return;
      try {
        out[k.toLowerCase()] = utf8.decode(v as List<int>, allowMalformed: true);
      } catch (_) {}
    });
    return out;
  }

  /// "(HP Officejet 6500 E710a-f)" -> "HP Officejet 6500 E710a-f"
  String? _cleanModel(String? m) {
    if (m == null) return null;
    final t = m.trim().replaceAll(RegExp(r'^\(|\)$'), '');
    return t.isEmpty ? null : t;
  }

  // ---------- 2. Netwerkscan ----------

  /// Scant het lokale /24-subnet. [onProgress] krijgt een waarde 0..1.
  Future<void> scanSubnet({void Function(double)? onProgress}) async {
    _cancelScan = false;
    final myIp = await NetworkInfo().getWifiIP();
    if (myIp == null || !myIp.contains('.')) {
      throw const SocketException('Geen wifi-verbinding gevonden');
    }
    final prefix = myIp.substring(0, myIp.lastIndexOf('.'));
    final hosts = [for (var i = 1; i < 255; i++) '$prefix.$i']..remove(myIp);

    const batch = 40;
    for (var i = 0; i < hosts.length && !_cancelScan; i += batch) {
      final chunk = hosts.skip(i).take(batch);
      await Future.wait(chunk.map(_probeHost));
      onProgress?.call((i + batch).clamp(0, hosts.length) / hosts.length);
    }
    onProgress?.call(1);
  }

  Future<void> _probeHost(String ip) async {
    for (final entry in _scanPorts.entries) {
      if (await _portOpen(ip, entry.key)) {
        final p = _get(ip)
          ..protocols.add(entry.value)
          ..sources.add('Netwerkscan');
        if (p.model == null) p.model = await _fetchModelFromWeb(ip);
        _emit();
      }
    }
  }

  Future<bool> _portOpen(String ip, int port, {int ms = 450}) async {
    try {
      final s = await Socket.connect(ip, port, timeout: Duration(milliseconds: ms));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Probeert de modelnaam uit de <title> van de printerwebpagina te halen
  /// (bij HP-printers staat daar bv. "HP Officejet 6500 E710a-f").
  Future<String?> _fetchModelFromWeb(String ip) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse('http://$ip/'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(const Utf8Decoder(allowMalformed: true)).take(20).join();
      final m = RegExp(r'<title>([^<]{2,80})</title>', caseSensitive: false).firstMatch(body);
      return m?.group(1)?.trim();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ---------- 3. Handmatig toevoegen (IP of hostnaam) ----------

  static const _manualPorts = <int, String>{
    9100: 'RAW (9100)',
    631: 'IPP',
    515: 'LPD',
    80: 'HTTP',
  };

  /// Voegt een printer toe op basis van een IP-adres of hostnaam, bv.
  /// "192.168.1.25", "HP6500A.local", "printer.thuis" of "http://192.168.1.25/".
  /// Gooit een [ManualAddException] met een Nederlandse foutmelding als het mislukt.
  Future<DiscoveredPrinter> addManual(String input, {bool silent = false}) async {
    final entry = normalizeEntry(input);
    if (entry.isEmpty) throw ManualAddException('Vul een IP-adres of hostnaam in.');

    final ip = await _resolve(entry);
    if (ip == null) {
      if (silent) return _offlineManual(entry);
      throw ManualAddException('Kan "$entry" niet vinden op het netwerk. Controleer de naam, of gebruik het IP-adres.');
    }

    final open = <String>[];
    await Future.wait(_manualPorts.entries.map((e) async {
      if (await _portOpen(ip, e.key, ms: 1500)) open.add(e.value);
    }));
    if (open.isEmpty) {
      if (silent) return _offlineManual(entry, ip: ip);
      throw ManualAddException('Apparaat $ip reageert niet. Staat de printer aan en zit hij op hetzelfde netwerk?');
    }

    final p = _get(ip)
      ..manualEntry = entry
      ..online = true
      ..sources.add('Handmatig');
    p.protocols.addAll(open.where((x) => x != 'HTTP'));
    if (!_isIp(entry)) p.host ??= entry;
    if (p.model == null && open.contains('HTTP')) p.model = await _fetchModelFromWeb(ip);
    _emit();
    return p;
  }

  DiscoveredPrinter _offlineManual(String entry, {String? ip}) {
    final key = ip ?? entry;
    final p = _get(key)
      ..manualEntry = entry
      ..online = false
      ..sources.add('Handmatig');
    _emit();
    return p;
  }

  void removeManual(DiscoveredPrinter p) {
    _printers.remove(p.ip);
    _emit();
  }

  static String normalizeEntry(String input) {
    var s = input.trim();
    s = s.replaceFirst(RegExp(r'^[a-z]+://', caseSensitive: false), ''); // http://, ipp://
    s = s.split('/').first; // pad weghalen
    s = s.replaceFirst(RegExp(r':\d+$'), ''); // poort weghalen
    return s.toLowerCase();
  }

  static bool _isIp(String s) => InternetAddress.tryParse(s) != null;

  Future<String?> _resolve(String entry) async {
    if (_isIp(entry)) return entry;

    // Al via Bonjour gevonden met deze naam? (bv. "HP6500A.local")
    final bare = entry.replaceAll(RegExp(r'\.$'), '');
    for (final p in _printers.values) {
      final h = p.host?.toLowerCase().replaceAll(RegExp(r'\.$'), '');
      if (h != null && (h == bare || h.split('.').first == bare.split('.').first) && _isIp(p.ip)) {
        return p.ip;
      }
    }

    // Gewone DNS-lookup (werkt ook voor .local op de meeste recente telefoons).
    final candidates = [entry, if (!entry.contains('.')) '$entry.local'];
    for (final c in candidates) {
      try {
        final r = await InternetAddress.lookup(c, type: InternetAddressType.IPv4)
            .timeout(const Duration(seconds: 4));
        if (r.isNotEmpty) return r.first.address;
      } catch (_) {}
    }
    return null;
  }

  // ---------- Testpagina ----------

  /// Stuurt een eenvoudige tekst-testpagina naar poort 9100 (RAW/JetDirect).
  /// HP-printers zoals de OfficeJet 6500A verwerken platte tekst met PCL-reset.
  static Future<void> printTestPage(DiscoveredPrinter p) async {
    final s = await Socket.connect(p.ip, 9100, timeout: const Duration(seconds: 4));
    final now = DateTime.now();
    final text = '\x1BE' // PCL reset
        'Printer Finder - testpagina\r\n'
        '============================\r\n\r\n'
        'Printer : ${p.displayName}\r\n'
        'IP-adres: ${p.ip}\r\n'
        'Tijd    : $now\r\n\r\n'
        'Als je dit leest, werkt afdrukken via het netwerk.\r\n'
        '\x0C' // form feed: pagina uitwerpen
        '\x1BE';
    s.add(latin1.encode(text));
    await s.flush();
    await s.close();
  }

  // ---------- Opruimen ----------

  Future<void> stop() async {
    _cancelScan = true;
    for (final d in _discoveries) {
      try {
        await nsd.stopDiscovery(d);
      } catch (_) {}
    }
    _discoveries.clear();
  }

  void clear() {
    _printers.clear();
    _emit();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

class ManualAddException implements Exception {
  ManualAddException(this.message);
  final String message;
  @override
  String toString() => message;
}
