import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'discovery.dart';
import 'printer.dart';

void main() => runApp(const PrinterFinderApp());

class PrinterFinderApp extends StatelessWidget {
  const PrinterFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Printer Finder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0096D6), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF0096D6),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _discovery = PrinterDiscovery();
  List<DiscoveredPrinter> _printers = [];
  bool _scanning = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discovery.printers.listen((list) => setState(() => _printers = list));
    _search(); // automatisch zoeken bij openen
  }

  @override
  void dispose() {
    _discovery.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_scanning) return;
    await _discovery.stop();
    _discovery.clear();
    setState(() {
      _scanning = true;
      _progress = 0;
      _error = null;
    });
    await _discovery.startBonjour();
    try {
      await _discovery.scanSubnet(onProgress: (p) => setState(() => _progress = p));
    } catch (e) {
      setState(() => _error = 'Netwerkscan mislukt: maak verbinding met wifi.');
    }
    if (mounted) setState(() => _scanning = false);
    // Bonjour blijft luisteren, zodat een printer die later aangaat ook verschijnt.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printers zoeken'),
        actions: [
          IconButton(
            tooltip: 'Opnieuw zoeken',
            onPressed: _scanning ? null : _search,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: _scanning
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              )
            : null,
      ),
      body: RefreshIndicator(onRefresh: _search, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_printers.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.print_outlined, size: 72, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _scanning ? 'Netwerk wordt doorzocht…' : 'Geen printers gevonden',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (!_scanning)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Controleer of de printer aan staat en op hetzelfde wifi-netwerk zit als je telefoon. '
                'Bij een OfficeJet 6500A: druk op het draadloos-pictogram op het printerpaneel om de verbinding te controleren.',
                textAlign: TextAlign.center,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _printers.length,
      itemBuilder: (_, i) => _PrinterCard(printer: _printers[i]),
    );
  }
}

class _PrinterCard extends StatelessWidget {
  const _PrinterCard({required this.printer});
  final DiscoveredPrinter printer;

  Future<void> _testPrint(BuildContext context) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      await PrinterDiscovery.printTestPage(printer);
      msg.showSnackBar(const SnackBar(content: Text('Testpagina verstuurd')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Afdrukken mislukt: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = printer;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.print, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.displayName, style: Theme.of(context).textTheme.titleMedium),
                  Text(p.ip, style: TextStyle(color: scheme.outline)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final proto in p.protocols) Chip(label: Text(proto), visualDensity: VisualDensity.compact),
              for (final src in p.sources)
                Chip(
                  avatar: Icon(src == 'Bonjour' ? Icons.wifi_tethering : Icons.radar, size: 16),
                  label: Text(src),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            if (p.location != null) ...[
              const SizedBox(height: 8),
              Text('Locatie: ${p.location}'),
            ],
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: () => launchUrl(p.webInterface, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Webpagina'),
              ),
              if (p.supportsRaw)
                FilledButton.tonalIcon(
                  onPressed: () => _testPrint(context),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Testpagina'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
