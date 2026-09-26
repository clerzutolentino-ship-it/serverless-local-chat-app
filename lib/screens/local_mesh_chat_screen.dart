import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nearby_connections/nearby_connections.dart';

class LocalMeshChatScreen extends StatefulWidget {
  const LocalMeshChatScreen({super.key});

  @override
  State<LocalMeshChatScreen> createState() =>
      _LocalMeshChatScreenState();
}

class _LocalMeshChatScreenState
    extends State<LocalMeshChatScreen> {
  final TextEditingController _messageController =
      TextEditingController();

  final List<String> _messages = [];

  final Map<String, String> _discoveredDevices = {};

  final Nearby _nearby = Nearby();

  bool _isDiscovering = false;
  bool _isAdvertising = false;

  String? _connectedEndpointId;
  String? _connectedDeviceName;

  @override
  void initState() {
    super.initState();
    _requestNearbyPermissions();
  }

  Future<void> _requestNearbyPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _handleConnectionInitiated(
    String endpointId,
    ConnectionInfo connectionInfo,
  ) async {
    if (!mounted) return;

    final shouldAccept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Connection Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A nearby device wants to connect.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Device:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(connectionInfo.endpointName),
              const SizedBox(height: 16),
              const Text(
                'Authentication Code:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.deepPurple.withOpacity(0.08),
                ),
                child: Text(
                  connectionInfo.authenticationToken,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Compare this code with the other device before accepting.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );

    if (shouldAccept == true) {
      await _acceptConnection(
        endpointId,
        connectionInfo.endpointName,
      );
    } else {
      try {
        await _nearby.rejectConnection(endpointId);
      } catch (e) {
        debugPrint('Reject connection error: $e');
      }
    }
  }

  Future<void> _acceptConnection(
    String endpointId,
    String endpointName,
  ) async {
    try {
      final result = await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: (
          String endpointId,
          Payload payload,
        ) {
          if (payload.type == PayloadType.BYTES &&
              payload.bytes != null) {
            final message = utf8.decode(payload.bytes!);

            if (!mounted) return;

            setState(() {
              _messages.add(message);
            });
          }
        },
        onPayloadTransferUpdate: (
          String endpointId,
          PayloadTransferUpdate update,
        ) {
          debugPrint(
            'Payload ${update.id}: ${update.status}',
          );
        },
      );

      if (result && mounted) {
        setState(() {
          _connectedEndpointId = endpointId;
          _connectedDeviceName = endpointName;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connection accepted with $endpointName',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Accept connection failed: $e',
          ),
        ),
      );
    }
  }

  Future<void> _connectToDevice(
    String endpointId,
    String endpointName,
  ) async {
    try {
      if (_isDiscovering) {
        await _nearby.stopDiscovery();

        if (mounted) {
          setState(() {
            _isDiscovering = false;
          });
        }
      }

      final result = await _nearby.requestConnection(
        'Student',
        endpointId,
        onConnectionInitiated: (
          String id,
          ConnectionInfo connectionInfo,
        ) {
          _handleConnectionInitiated(
            id,
            connectionInfo,
          );
        },
        onConnectionResult: (
          String id,
          Status status,
        ) {
          if (!mounted) return;

          if (status == Status.CONNECTED) {
            setState(() {
              _connectedEndpointId = id;
              _connectedDeviceName = endpointName;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Connected to $endpointName',
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Connection result: $status',
                ),
              ),
            );
          }
        },
        onDisconnected: (String id) {
          if (!mounted) return;

          setState(() {
            _connectedEndpointId = null;
            _connectedDeviceName = null;
          });
        },
      );

      if (!result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not request connection.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connection request failed: $e',
          ),
        ),
      );
    }
  }

  Future<void> _startAdvertising() async {
    try {
      if (_isDiscovering) {
        await _nearby.stopDiscovery();

        setState(() {
          _isDiscovering = false;
        });
      }

      final result = await _nearby.startAdvertising(
        'Student',
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: (
          String endpointId,
          ConnectionInfo connectionInfo,
        ) {
          _handleConnectionInitiated(
            endpointId,
            connectionInfo,
          );
        },
        onConnectionResult: (
          String endpointId,
          Status status,
        ) {
          if (!mounted) return;

          if (status == Status.CONNECTED) {
            setState(() {
              _connectedEndpointId = endpointId;
              _connectedDeviceName = 'Connected Device';
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Device connected successfully.',
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Connection result: $status',
                ),
              ),
            );
          }
        },
        onDisconnected: (String endpointId) {
          if (!mounted) return;

          setState(() {
            _connectedEndpointId = null;
            _connectedDeviceName = null;
          });
        },
        serviceId: 'com.example.serverless_local_chat',
      );

      if (mounted) {
        setState(() {
          _isAdvertising = result;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isAdvertising = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Advertising failed: $e',
          ),
        ),
      );
    }
  }

  Future<void> _stopAdvertising() async {
    await _nearby.stopAdvertising();

    if (mounted) {
      setState(() {
        _isAdvertising = false;
      });
    }
  }

  Future<void> _startDiscovery() async {
    try {
      if (_isAdvertising) {
        await _nearby.stopAdvertising();

        setState(() {
          _isAdvertising = false;
        });
      }

      final result = await _nearby.startDiscovery(
        'Student',
        Strategy.P2P_CLUSTER,
        onEndpointFound: (
          String endpointId,
          String endpointName,
          String serviceId,
        ) {
          if (!mounted) return;

          setState(() {
            _discoveredDevices[endpointId] = endpointName;
          });
        },
        onEndpointLost: (String? endpointId) {
          if (endpointId != null && mounted) {
            setState(() {
              _discoveredDevices.remove(endpointId);
            });
          }
        },
        serviceId: 'com.example.serverless_local_chat',
      );

      if (mounted) {
        setState(() {
          _isDiscovering = result;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDiscovering = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Discovery failed: $e',
          ),
        ),
      );
    }
  }

  Future<void> _stopDiscovery() async {
    await _nearby.stopDiscovery();

    if (mounted) {
      setState(() {
        _isDiscovering = false;
      });
    }
  }

  // IMPORTANT:
  // Uint8List is available because of:
  // import 'dart:typed_data';
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();

    if (message.isEmpty) {
      return;
    }

    if (_connectedEndpointId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect to a device first.',
          ),
        ),
      );
      return;
    }

    try {
      final Uint8List bytes = Uint8List.fromList(
        utf8.encode(message),
      );

      await _nearby.sendBytesPayload(
        _connectedEndpointId!,
        bytes,
      );

      if (!mounted) return;

      setState(() {
        _messages.add(message);
      });

      _messageController.clear();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Message failed to send: $e',
          ),
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    if (_connectedEndpointId == null) {
      return;
    }

    try {
      await _nearby.disconnectFromEndpoint(
        _connectedEndpointId!,
      );

      if (!mounted) return;

      setState(() {
        _connectedEndpointId = null;
        _connectedDeviceName = null;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Disconnect failed: $e',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nearby.stopDiscovery();
    _nearby.stopAdvertising();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Mesh Chat'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nearby Devices',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _connectedEndpointId != null
                          ? 'Connected to $_connectedDeviceName'
                          : _isAdvertising
                              ? 'Your device is visible to nearby users.'
                              : _isDiscovering
                                  ? 'Searching for nearby devices...'
                                  : 'Discovery and advertising are stopped.',
                    ),
                    const SizedBox(height: 12),

                    if (_connectedEndpointId != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(10),
                          color:
                              Colors.green.withOpacity(0.1),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Connected: $_connectedDeviceName',
                                style: const TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _disconnect,
                              icon: const Icon(
                                Icons.link_off,
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_connectedEndpointId != null)
                      const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isAdvertising
                            ? _stopAdvertising
                            : _startAdvertising,
                        icon: Icon(
                          _isAdvertising
                              ? Icons.stop
                              : Icons
                                  .broadcast_on_personal,
                        ),
                        label: Text(
                          _isAdvertising
                              ? 'Stop Advertising'
                              : 'Make My Device Visible',
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isDiscovering
                            ? _stopDiscovery
                            : _startDiscovery,
                        icon: Icon(
                          _isDiscovering
                              ? Icons.stop
                              : Icons.search,
                        ),
                        label: Text(
                          _isDiscovering
                              ? 'Stop Discovery'
                              : 'Find Nearby Devices',
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_discoveredDevices.isEmpty)
                      const Text(
                        'No nearby devices found yet.',
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      )
                    else
                      ..._discoveredDevices.entries.map(
                        (device) {
                          return Card(
                            elevation: 0,
                            child: ListTile(
                              leading: const Icon(
                                Icons.phone_android,
                              ),
                              title: Text(device.value),
                              subtitle: const Text(
                                'Tap to connect',
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                              ),
                              onTap: () {
                                _connectToDevice(
                                  device.key,
                                  device.value,
                                );
                              },
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                        fontSize: 18,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin:
                              const EdgeInsets.only(bottom: 10),
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple,
                            borderRadius:
                                BorderRadius.circular(16),
                          ),
                          child: Text(
                            _messages[index],
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed:
                      _connectedEndpointId != null
                          ? _sendMessage
                          : null,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}