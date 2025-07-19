import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Relay Commander',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        textTheme: GoogleFonts.poppinsTextTheme(),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.light,
        cardTheme: CardThemeData(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          shadowColor: Colors.black.withOpacity(0.2),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      debugShowCheckedModeBanner: false,
      home: const BluetoothApp(),
    );
  }
}

class BluetoothApp extends StatefulWidget {
  const BluetoothApp({super.key});

  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> with SingleTickerProviderStateMixin {
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothConnection? connection;
  List<BluetoothDevice> devicesList = [];
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  bool isDiscovering = false;
  String connectionStatus = "Not Connected";
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    requestPermissions();
    initBluetooth();
  }

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    print("Permission Status: $statuses");
  }

  Future<void> initBluetooth() async {
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() => _bluetoothState = state);
      if (state.isEnabled) getPairedDevices();
    });

    FlutterBluetoothSerial.instance.onStateChanged().listen((state) {
      setState(() {
        _bluetoothState = state;
        if (!state.isEnabled) {
          isConnected = false;
          connectionStatus = "Bluetooth Off";
        }
      });
    });
  }

  Future<void> getPairedDevices() async {
    setState(() => isDiscovering = true);
    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      print("Found ${devices.length} paired devices");
      setState(() {
        devicesList = devices;
        isDiscovering = false;
      });
    } catch (e) {
      print("Error getting devices: $e");
      setState(() => isDiscovering = false);
    }
  }

  void connect() async {
    if (selectedDevice == null) {
      showSnackBar("Please select a device first");
      return;
    }

    setState(() => connectionStatus = "Connecting...");

    try {
      BluetoothConnection newConnection = await BluetoothConnection.toAddress(selectedDevice!.address);
      print('Connected to ${selectedDevice!.name}');

      setState(() {
        connection = newConnection;
        isConnected = true;
        connectionStatus = "Connected to ${selectedDevice!.name}";
      });

      connection!.input!.listen((Uint8List data) {
        print('Data received: ${String.fromCharCodes(data)}');
      }).onDone(() {
        print('Disconnected from device');
        setState(() {
          isConnected = false;
          connectionStatus = "Disconnected";
        });
      });
    } catch (e) {
      print('Connection error: $e');
      setState(() => connectionStatus = "Connection failed");
      showSnackBar("Failed to connect: ${e.toString()}");
    }
  }

  void disconnect() {
    connection?.dispose();
    setState(() {
      isConnected = false;
      connectionStatus = "Disconnected";
    });
  }

  Future<void> sendMessage(String message) async {
    if (connection == null || !connection!.isConnected) {
      showSnackBar("Not connected to any device");
      return;
    }

    try {
      connection!.output.add(Uint8List.fromList(message.codeUnits));
      await connection!.output.allSent;
      print('Message sent: $message');
      showSnackBar("Command sent: ${message.toUpperCase()}");
    } catch (e) {
      print('Error sending message: $e');
      showSnackBar("Failed to send command");
    }
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    connection?.dispose();
    super.dispose();
  }

  Widget _buildDeviceDropdown() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DropdownButton<BluetoothDevice>(
          isExpanded: true,
          items: devicesList.map((device) => DropdownMenuItem(
            value: device,
            child: Text(
              device.name ?? 'Unknown Device',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(),
            ),
          )).toList(),
          onChanged: (device) => setState(() => selectedDevice = device),
          value: selectedDevice,
          hint: Text('Select a device', style: GoogleFonts.poppins()),
          underline: const SizedBox(),
          dropdownColor: Theme.of(context).cardColor,
          icon: const Icon(Icons.arrow_drop_down_circle, color: Colors.deepPurple),
        ),
      ),
    );
  }

  Widget _buildRelayButton(String label, String onCommand, String offCommand) {
    return ScaleTransition(
      scale: _animation,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: isConnected ? () => sendMessage(onCommand) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                      elevation: 5,
                    ),
                    child: const Icon(Icons.power_settings_new, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: isConnected ? () => sendMessage(offCommand) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                      elevation: 5,
                    ),
                    child: const Icon(Icons.power_off, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColorDark,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Smart Relay Commander',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: _bluetoothState.isEnabled ? Colors.blue : Colors.grey,
                          ),
                          title: Text('Bluetooth Status', style: GoogleFonts.poppins()),
                          subtitle: Text(
                            _bluetoothState.toString().split('.').last,
                            style: GoogleFonts.poppins(
                              color: _bluetoothState.isEnabled ? Colors.green : Colors.red,
                            ),
                          ),
                          trailing: Switch(
                            value: _bluetoothState.isEnabled,
                            onChanged: (value) {
                              if (value) {
                                FlutterBluetoothSerial.instance.requestEnable();
                              } else {
                                FlutterBluetoothSerial.instance.requestDisable();
                              }
                            },
                            activeColor: Colors.blue,
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          leading: Icon(
                            isConnected ? Icons.link : Icons.link_off,
                            color: isConnected ? Colors.green : Colors.red,
                          ),
                          title: Text('Connection Status', style: GoogleFonts.poppins()),
                          subtitle: Text(
                            connectionStatus,
                            style: GoogleFonts.poppins(
                              color: isConnected ? Colors.green : Colors.red,
                            ),
                          ),
                          trailing: ElevatedButton(
                            onPressed: isConnected ? disconnect : connect,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isConnected ? Colors.red : Colors.blue,
                            ),
                            child: Text(
                              isConnected ? 'DISCONNECT' : 'CONNECT',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Available Devices',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                isDiscovering
                    ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : _buildDeviceDropdown(),
                const SizedBox(height: 30),
                Text(
                  'Relay Controls',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildRelayButton("Relay 1", "A", "a"),
                    _buildRelayButton("Relay 2", "B", "b"),
                    _buildRelayButton("Relay 3", "C", "c"),
                    _buildRelayButton("Relay 4", "D", "d"),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: getPairedDevices,
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.refresh, color: Colors.white),
        tooltip: 'Refresh Devices',
      ),
    );
  }
}