# Printer Finder (Flutter, Android + iOS)

Vindt automatisch netwerkprinters op je wifi, zoals de **HP OfficeJet 6500A**.

## Hoe het zoekt
1. **Bonjour/mDNS**: luistert naar `_ipp._tcp`, `_ipps._tcp`, `_pdl-datastream._tcp` en `_printer._tcp`. Model, beheer-URL en locatie komen uit de TXT-records.
2. **Netwerkscan**: probeert elk adres in je /24-subnet op poort 9100 (RAW/JetDirect) en 631 (IPP). Zo vindt hij ook printers waarop Bonjour uit staat. De modelnaam haalt hij dan uit de titel van de webpagina van de printer.

Resultaten van beide methodes worden per IP-adres samengevoegd. Per printer kun je de **webpagina** openen (EWS) of een **testpagina** sturen via poort 9100.

## Installeren
```bash
flutter create printer_finder_app
cd printer_finder_app
# kopieer pubspec.yaml en de map lib/ uit dit project hierover heen
flutter pub get
```

### Android: `android/app/src/main/AndroidManifest.xml`
Zet dit boven `<application>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
```
Zet dit in `<application ...>`, want de webpagina van de printer gebruikt http:
```xml
android:usesCleartextTraffic="true"
```
Gebruik minimaal `minSdkVersion 21` in `android/app/build.gradle`.

### iOS: `ios/Runner/Info.plist`
Voor iOS 14 en hoger zijn deze sleutels **verplicht**, anders vindt Bonjour niets:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Nodig om printers op je netwerk te vinden.</string>
<key>NSBonjourServices</key>
<array>
  <string>_ipp._tcp</string>
  <string>_ipps._tcp</string>
  <string>_pdl-datastream._tcp</string>
  <string>_printer._tcp</string>
</array>
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsLocalNetworking</key><true/></dict>
```

## Starten
```bash
flutter run
```
Test op een echt toestel dat op hetzelfde wifi-netwerk zit als de printer. Emulators zien het lokale netwerk meestal niet.

## Tips voor de OfficeJet 6500A
- Druk op het draadloos-pictogram op het paneel en print het netwerkrapport. Daarop staan het IP-adres en of Bonjour aan staat.
- Staat Bonjour uit, dan vindt de netwerkscan de printer toch via poort 9100.
- Gastnetwerken en "AP-isolatie" op routers blokkeren de detectie.
