import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'discovery.dart';
import 'printer.dart';
import 'storage.dart';

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
  final _store = ManualPrinterStore();
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
    _restoreManual(); // loopt parallel met de netwerkscan
    try {
      await _discovery.scanSubnet(onProgress: (p) => setState(() => _progress = p));
    } catch (e) {
      setState(() => _error = 'Netwerkscan mislukt: maak verbinding met wifi.');
    }
    if (mounted) setState(() => _scanning = false);
    // Bonjour blijft luisteren, zodat een printer die later aangaat ook verschijnt.
  }

  Future<void> _restoreManual() async {
    final entries = await _store.load();
    await Future.wait(entries.map((e) => _discovery.addManual(e, silent: true).catchError((_) {
          return DiscoveredPrinter(ip: e);
        })));
  }

  Future<void> _removeManual(DiscoveredPrinter p) async {
    await _store.remove(p.manualEntry!);
    _discovery.removeManual(p);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${p.displayName} verwijderd')));
    }
  }

  Future<void> _showAddDialog() async {
    final added = await showDialog<DiscoveredPrinter>(
      context: context,
      builder: (_) => _AddPrinterDialog(discovery: _discovery),
    );
    if (added == null || !mounted) return;
    await _store.add(added.manualEntry!);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${added.displayName} toegevoegd')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Printer toevoegen'),
      ),
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
                'Bij een OfficeJet 6500A: druk op het draadloos-pictogram op het printerpaneel om de verbinding te controleren.\n\n'
                'Weet je het IP-adres of de hostnaam? Tik dan op "Printer toevoegen".',
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: _printers.length,
      itemBuilder: (_, i) => _PrinterCard(
        printer: _printers[i],
        onRemove: _printers[i].isManual ? () => _removeManual(_printers[i]) : null,
      ),
    );
  }
}

class _PrinterCard extends StatelessWidget {
  const _PrinterCard({required this.printer, this.onRemove});
  final DiscoveredPrinter printer;
  final VoidCallback? onRemove;

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
                  Text(p.subtitle, style: TextStyle(color: scheme.outline)),
                ]),
              ),
              if (!p.online)
                Chip(
                  avatar: Icon(Icons.cloud_off, size: 16, color: scheme.error),
                  label: const Text('Offline'),
                  visualDensity: VisualDensity.compact,
                ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Verwijderen',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final proto in p.protocols) Chip(label: Text(proto), visualDensity: VisualDensity.compact),
              for (final src in p.sources)
                Chip(
                  avatar: Icon(
                      switch (src) {
                        'Bonjour' => Icons.wifi_tethering,
                        'Handmatig' => Icons.edit,
                        _ => Icons.radar,
                      },
                      size: 16),
                  label: Text(src),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            if (p.location != null) ...[
              const SizedBox(height: 8),
              Text('Locatie: ${p.location}'),
            ],
            const SizedBox(height: 8),
            if (p.online) Row(mainAxisAlignment: MainAxisAlignment.end, children: [
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

class _AddPrinterDialog extends StatefulWidget {
  const _AddPrinterDialog({required this.discovery});
  final PrinterDiscovery discovery;

  @override
  State<_AddPrinterDialog> createState() => _AddPrinterDialogState();
}

class _AddPrinterDialogState extends State<_AddPrinterDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await widget.discovery.addManual(_controller.text);
      if (mounted) Navigator.of(context).pop(p);
    } on ManualAddException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Toevoegen mislukt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Printer toevoegen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'IP-adres of hostnaam',
              hintText: '192.168.1.25 of HP6500A.local',
              errorText: _error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Het IP-adres staat op het netwerkrapport van de printer '
            '(OfficeJet 6500A: draadloos-pictogram \u2192 Afdrukken netwerkconfiguratie).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Toevoegen'),
        ),
      ],
    );
  }
}
