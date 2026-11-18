import 'package:flutter_test/flutter_test.dart';
import 'package:printer_finder/discovery.dart';

void main() {
  test('normalizeEntry haalt schema, pad en poort weg', () {
    expect(PrinterDiscovery.normalizeEntry(' 192.168.1.25 '), '192.168.1.25');
    expect(PrinterDiscovery.normalizeEntry('http://192.168.1.25/index.html'), '192.168.1.25');
    expect(PrinterDiscovery.normalizeEntry('ipp://HP6500A.local:631/ipp/print'), 'hp6500a.local');
    expect(PrinterDiscovery.normalizeEntry('Printer.Thuis'), 'printer.thuis');
    expect(PrinterDiscovery.normalizeEntry('   '), '');
  });
}
