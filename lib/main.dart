import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

/// Minimal QR Scanner + Generator single-file app (main.dart)
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Scanner & Generator',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<String> _scanHistory = [];
  String _lastScanned = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void addScanned(String value) {
    if (value.trim().isEmpty) return;
    setState(() {
      _lastScanned = value;
      _scanHistory.insert(0, value);
      if (_scanHistory.length > 50) _scanHistory.removeLast();
    });
    Fluttertoast.showToast(
      msg: 'Scanned: $value',
      gravity: ToastGravity.BOTTOM,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scannerAvailable = _isScanSupported;

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Scanner & Generator'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.camera_alt), text: 'Scan'),
            Tab(icon: Icon(Icons.qr_code), text: 'Generate'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          if (scannerAvailable)
            ScanScreen(
              onScanned: addScanned,
              lastScanned: _lastScanned,
              history: _scanHistory,
            )
          else
            const ScannerUnavailableScreen(),
          GenerateScreen(),
        ],
      ),
    );
  }
}

bool get _isScanSupported =>
    kIsWeb || Platform.isAndroid || Platform.isIOS;

class ScannerUnavailableScreen extends StatelessWidget {
  const ScannerUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.warning_amber_rounded, size: 64),
            SizedBox(height: 12),
            Text(
              'QR scanning is not supported on this platform.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Use Android, iOS, or the web for the scanning experience.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

Uri? _linkFromValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.hasScheme) {
    if ((parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed;
    }
    return null;
  }

  if (trimmed.contains(' ') || !trimmed.contains('.')) {
    return null;
  }

  final httpsUri = Uri.tryParse('https://$trimmed');
  if (httpsUri != null && httpsUri.host.isNotEmpty) {
    return httpsUri;
  }

  return null;
}
class ScanScreen extends StatefulWidget {
  final Function(String) onScanned;
  final String lastScanned;
  final List<String> history;

  const ScanScreen({
    super.key,
    required this.onScanned,
    required this.lastScanned,
    required this.history,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController cameraController = MobileScannerController();
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue ?? '';
    if (raw.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      widget.onScanned(raw);
    } finally {
      // small delay prevents same code from being added repeatedly
      await Future.delayed(const Duration(milliseconds: 700));
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _scanFromGallery() async {
    if (_isProcessing) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
    );
    if (picked == null) return;

    setState(() => _isProcessing = true);
    try {
      final capture = await cameraController.analyzeImage(picked.path);
      final code = capture?.barcodes.first.rawValue ?? '';
      if (code.isNotEmpty) {
        widget.onScanned(code);
        Fluttertoast.showToast(msg: 'Scanned from gallery');
      } else {
        Fluttertoast.showToast(msg: 'No QR code found in the image');
      }
    } catch (error) {
      Fluttertoast.showToast(msg: 'Unable to analyze the image');
    } finally {
      await Future.delayed(const Duration(milliseconds: 700));
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _launchLink(String value) async {
    final uri = _linkFromValue(value);
    if (uri == null) return;
    final success =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success) {
      Fluttertoast.showToast(msg: 'Could not open the link');
    }
  }

  void _handleHistoryTap(String value) {
    final uri = _linkFromValue(value);
    if (uri != null) {
      _launchLink(value);
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Scanned value'),
        content: SelectableText(value),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Camera preview
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              MobileScanner(
                controller: cameraController,
                onDetect: _handleBarcode,
              ),
              // simple overlay
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: ValueListenableBuilder<MobileScannerState>(
                          valueListenable: cameraController,
                          builder: (context, state, child) {
                            final torchState = state.torchState;
                            return Icon(
                              torchState == TorchState.off
                                  ? Icons.flash_off
                                  : Icons.flash_on,
                            );
                          },
                        ),
                        onPressed: () => cameraController.toggleTorch(),
                        tooltip: 'Toggle torch',
                      ),
                      IconButton(
                        icon: ValueListenableBuilder<MobileScannerState>(
                          valueListenable: cameraController,
                          builder: (context, state, child) {
                            final facing = state.cameraDirection;
                            return Icon(
                              facing == CameraFacing.back
                                  ? Icons.camera_rear
                                  : Icons.camera_front,
                            );
                          },
                        ),
                        onPressed: () => cameraController.switchCamera(),
                        tooltip: 'Switch camera',
                      ),
                      IconButton(
                        icon: const Icon(Icons.pause),
                        onPressed: () => cameraController.stop(),
                        tooltip: 'Stop camera',
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => cameraController.start(),
                        tooltip: 'Start camera',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // result and history
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last scanned:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final lastUri = _linkFromValue(widget.lastScanned);
                    return Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            widget.lastScanned.isEmpty
                                ? '— nothing scanned yet —'
                                : widget.lastScanned,
                            maxLines: 3,
                            style: lastUri != null
                                ? TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  )
                                : null,
                          ),
                        ),
                        if (widget.lastScanned.isNotEmpty) ...[
                          IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: widget.lastScanned),
                              );
                              Fluttertoast.showToast(
                                  msg: 'Copied to clipboard');
                            },
                          ),
                          if (lastUri != null)
                            IconButton(
                              tooltip: 'Open link',
                              icon: const Icon(Icons.open_in_browser),
                              onPressed: () => _launchLink(widget.lastScanned),
                            ),
                        ],
                        IconButton(
                          tooltip: 'Scan from gallery',
                          icon: const Icon(Icons.photo_library),
                          onPressed: _isProcessing ? null : _scanFromGallery,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'History:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: widget.history.isEmpty
                      ? const Center(child: Text('No scans yet'))
                      : ListView.separated(
                          itemCount: widget.history.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final v = widget.history[index];
                            final historyUri = _linkFromValue(v);
                          return ListTile(
                            title: Text(
                              v,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (historyUri != null)
                                  IconButton(
                                    tooltip: 'Open link',
                                    icon: const Icon(Icons.open_in_browser),
                                    onPressed: () => _launchLink(v),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: v));
                                    Fluttertoast.showToast(
                                      msg: 'Copied to clipboard',
                                    );
                                  },
                                ),
                              ],
                            ),
                            onTap: () => _handleHistoryTap(v),
                          );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Generator screen: type text, show QR
class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final TextEditingController _controller = TextEditingController(
    text: 'https://example.com',
  );
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();
  final ImagePicker _picker = ImagePicker();
  XFile? _uploadedImage;

  ImageProvider? get _uploadedImageProvider =>
      _uploadedImage == null ? null : FileImage(File(_uploadedImage!.path));

  String get current => _controller.text;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openUploadPage() async {
    final picked = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => const UploadImagePage()),
    );
    if (picked != null) {
      setState(() => _uploadedImage = picked);
      Fluttertoast.showToast(msg: 'Image selected');
    }
  }

  void _clearUploadedImage() {
    setState(() => _uploadedImage = null);
  }

  void _openGeneratedQr() {
    if (current.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrPreviewScreen(
          data: current,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
          embeddedImage: _uploadedImageProvider,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldKey,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('Upload image'),
                onPressed: _openUploadPage,
              ),
            ),
            if (_uploadedImageProvider != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 140,
                  child: Image(
                    image: _uploadedImageProvider!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove uploaded image'),
                onPressed: _clearUploadedImage,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Text / URL to encode',
                border: OutlineInputBorder(),
                hintText: 'Enter website, text, phone number, etc.',
              ),
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18.0),
                          child: Column(
                            children: [
                              Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: current.isEmpty
                                    ? const Center(
                                        child: Text('Enter text to generate QR'),
                                      )
                                    : QrImageView(
                                        data: current,
                                        version: QrVersions.auto,
                                        errorCorrectionLevel:
                                            QrErrorCorrectLevel.H,
                                        size: 220,
                                        embeddedImage: _uploadedImageProvider,
                                      ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                current.isEmpty
                                    ? 'Enter text to generate QR'
                                    : current,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 6,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.copy),
                                    label: const Text('Copy'),
                                    onPressed: current.isEmpty
                                        ? null
                                        : () {
                                            Clipboard.setData(
                                              ClipboardData(text: current),
                                            );
                                            Fluttertoast.showToast(
                                              msg: 'Copied to clipboard',
                                            );
                                          },
                                  ),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.share),
                                    label: const Text('Share'),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: current),
                                      );
                                      Fluttertoast.showToast(
                                        msg:
                                            'Text copied — use share plugin for full sharing',
                                      );
                                    },
                                  ),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.open_in_full),
                                    label: const Text('Open'),
                                    onPressed:
                                        current.isEmpty ? null : _openGeneratedQr,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tip: Use the Scan tab to capture QR codes; use Generate to make new ones.',
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class UploadImagePage extends StatefulWidget {
  const UploadImagePage({super.key});

  @override
  State<UploadImagePage> createState() => _UploadImagePageState();
}

class _UploadImagePageState extends State<UploadImagePage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;

  Future<void> _pickImage() async {
    final selected = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
    );
    if (selected == null) return;
    setState(() => _pickedImage = selected);
  }

  void _useImage() {
    if (_pickedImage == null) {
      Fluttertoast.showToast(msg: 'Pick an image first');
      return;
    }
    Navigator.of(context).pop(_pickedImage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload image')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Choose an image from your gallery to embed into the QR code.',
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick from gallery'),
              onPressed: _pickImage,
            ),
            const SizedBox(height: 16),
            if (_pickedImage != null)
              Expanded(
                child: Column(
                  children: [
                    const Text('Preview:'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_pickedImage!.path),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Text(
                    'No image selected yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ElevatedButton(
              onPressed: _useImage,
              child: const Text('Use this image'),
            ),
          ],
        ),
      ),
    );
  }
}

class QrPreviewScreen extends StatelessWidget {
  const QrPreviewScreen({
    super.key,
    required this.data,
    required this.version,
    required this.errorCorrectionLevel,
    this.embeddedImage,
  });

  final String data;
  final int version;
  final int errorCorrectionLevel;
  final ImageProvider? embeddedImage;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.shortestSide * 0.8;
    return Scaffold(
      appBar: AppBar(title: const Text('QR preview')),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: QrImageView(
              data: data,
              version: version,
              errorCorrectionLevel: errorCorrectionLevel,
              size: size,
              embeddedImage: embeddedImage,
            ),
          ),
        ),
      ),
    );
  }
}
