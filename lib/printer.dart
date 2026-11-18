/// Een gevonden netwerkprinter. Meerdere bronnen (mDNS-services, poortscan)
/// worden op IP-adres samengevoegd tot één printer.
class DiscoveredPrinter {
  DiscoveredPrinter({required this.ip, this.name, this.host});

  final String ip;
  String? name;
  String? host;
  String? model; // uit TXT-record "ty" of "product"
  String? adminUrl; // uit TXT-record "adminurl"
  String? location; // uit TXT-record "note"
  final Set<String> protocols = {}; // IPP, IPPS, RAW 9100, LPD, ...
  final Set<String> sources = {}; // "Bonjour" en/of "Netwerkscan"

  String get displayName => model ?? name ?? 'Printer op $ip';

  bool get supportsRaw => protocols.contains('RAW (9100)');

  bool get isHp {
    final s = '${model ?? ''} ${name ?? ''}'.toLowerCase();
    return s.contains('hp') || s.contains('officejet') || s.contains('deskjet') || s.contains('laserjet');
  }

  Uri get webInterface =>
      adminUrl != null ? Uri.parse(adminUrl!) : Uri.parse('http://$ip/');
}
