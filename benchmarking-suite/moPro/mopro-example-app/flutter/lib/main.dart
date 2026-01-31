import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:mopro_flutter/mopro_flutter.dart';
import 'package:mopro_flutter/mopro_types.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:system_info2/system_info2.dart';
import 'package:battery_plus/battery_plus.dart';

// Input data structure
class InputData {
  final String name;
  final String description;
  final List<String> values;
  
  InputData({required this.name, required this.description, required this.values});
}

// Input size options (in bits)
enum InputSize {
  bits128(128, 16, 1),   // 128 bits = 16 bytes = 1 field element
  bits256(256, 32, 2),   // 256 bits = 32 bytes = 2 field elements
  bits512(512, 64, 3),   // 512 bits = 64 bytes = 3 field elements
  bits1024(1024, 128, 5); // 1024 bits = 128 bytes = 5 field elements

  final int bits;
  final int bytes;
  final int fieldElements;
  
  const InputSize(this.bits, this.bytes, this.fieldElements);
  
  String get displayName => '$bits bits';
}

// ZK-friendly hash algorithms that require field element inputs
const List<String> zkFriendlyHashes = ['Poseidon', 'MiMC', 'Anemoi', 'RescuePrime'];

// Non-ZK hash algorithms that require byte inputs
const List<String> nonZkHashes = ['SHA256', 'Keccak256', 'Blake2', 'Blake3'];

/// Converts a list of bytes to field elements by packing 31 bytes per field element.
/// BN254 field elements can safely hold 31 bytes (248 bits) without overflow.
List<BigInt> bytesToFieldElements(List<int> bytes) {
  const int bytesPerField = 31;
  List<BigInt> fieldElements = [];
  
  for (int i = 0; i < bytes.length; i += bytesPerField) {
    BigInt fieldValue = BigInt.zero;
    int end = (i + bytesPerField < bytes.length) ? i + bytesPerField : bytes.length;
    
    // Pack bytes into a single field element (big-endian)
    for (int j = i; j < end; j++) {
      fieldValue = (fieldValue << 8) | BigInt.from(bytes[j] & 0xFF);
    }
    
    fieldElements.add(fieldValue);
  }
  
  return fieldElements;
}

/// Converts field elements to hex strings for circuit input
List<String> fieldElementsToHexStrings(List<BigInt> fieldElements) {
  return fieldElements.map((fe) => '0x${fe.toRadixString(16)}').toList();
}

/// Pads or truncates byte array to exact size
List<int> padOrTruncateBytes(List<int> bytes, int targetSize) {
  if (bytes.length >= targetSize) {
    return bytes.sublist(0, targetSize);
  }
  // Pad with zeros
  return [...bytes, ...List.filled(targetSize - bytes.length, 0)];
}


class AppTheme {
  static const Color primary = Color(0xFF5B56E6);
  static const Color secondary = Color(0xFF1E40AF);
  static const Color accent = Color(0xFF00BCD4);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFFFA500);
  static const Color success = Color(0xFF10B981);
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deimos',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: AppTheme.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const MainSelectionPage(),
    );
  }
}

class MainSelectionPage extends StatefulWidget {
  const MainSelectionPage({super.key});

  @override
  State<MainSelectionPage> createState() => _MainSelectionPageState();
}

class _MainSelectionPageState extends State<MainSelectionPage> {
  // Selection state
  String? _selectedFramework;
  String? _selectedAlgorithm;
  String? _selectedInput;
  InputSize _selectedInputSize = InputSize.bits256; // Default to 256 bits
  bool _isLoading = false;
  bool _isLoadingInputs = true;
  
  List<InputData> _availableInputs = [];

  @override
  void initState() {
    super.initState();
    _loadInputs();
  }

  Future<void> _loadInputs() async {
    try {
      final List<InputData> loadedInputs = [];
      
      // Load input files
      for (int i = 1; i <= 3; i++) {
        try {
          final inputData = await _loadInputFromJson('inputs/input_$i.json');
          loadedInputs.add(inputData);
        } catch (e) {
          debugPrint('Error loading input_$i.json: $e');
        }
      }
      
      setState(() {
        _availableInputs = loadedInputs;
        _isLoadingInputs = false;
        if (_availableInputs.isNotEmpty) {
          _selectedInput = _availableInputs.first.name;
        }
      });
    } catch (e) {
      debugPrint('Error loading inputs: $e');
      setState(() {
        _isLoadingInputs = false;
      });
    }
  }

  Future<InputData> _loadInputFromJson(String assetPath) async {
    try {
      final String jsonString = await rootBundle.loadString(assetPath);
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      
      // Extract data from JSON
      final String name = jsonData['name'] as String;
      final String description = jsonData['description'] as String;
      final List<dynamic> inArray = jsonData['in'] as List<dynamic>;
      
      // Convert the "in" array to List<String>
      final List<String> values = inArray.map((e) => e.toString()).toList();
      
      return InputData(
        name: name,
        description: description,
        values: values,
      );
    } catch (e) {
      throw Exception('Failed to load input from $assetPath: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInputs) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Loading inputs...',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildFrameworkSelection(),
              const SizedBox(height: 24),
              _buildAlgorithmSelection(),
              const SizedBox(height: 24),
              if (_selectedFramework == 'noir' && _selectedAlgorithm != null) ...[
                _buildInputSizeSelection(),
                const SizedBox(height: 24),
              ],
              _buildCustomInput(),
              const SizedBox(height: 32),
              _buildRunButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'D',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                    Text(
                      'Deimos',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'ZK Proof Benchmarking',
              style: TextStyle(
                fontSize: 16,
                        color: Colors.white70,
                      ),
                ),
              ],
            ),
              ),
            ],
              ),
            ],
          ),
    );
  }

  Widget _buildFrameworkSelection() {
    final frameworks = [
      {'name': 'Circom', 'value': 'circom', 'icon': Icons.speed},
      {'name': 'Halo2', 'value': 'halo2', 'icon': Icons.layers},
      {'name': 'Noir', 'value': 'noir', 'icon': Icons.nightlight_round},
      {'name': 'RISC Zero', 'value': 'risc0', 'icon': Icons.developer_board},
    ];

    return _buildCard(
      title: 'Step 1: Select Framework',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a ZK proof framework',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _selectedFramework != null 
                  ? AppTheme.primary.withOpacity(0.05)
                  : AppTheme.surface,
              border: Border.all(
                color: _selectedFramework != null 
                    ? AppTheme.primary 
                    : AppTheme.border, 
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedFramework,
                hint: Row(
                  children: const [
                    Icon(Icons.code, size: 20, color: AppTheme.textSecondary),
                    SizedBox(width: 12),
                    Text(
                      'Select a framework',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                items: frameworks.map((framework) {
                  return DropdownMenuItem<String>(
                    value: framework['value'] as String,
                    child: Row(
                      children: [
                        Icon(
                          framework['icon'] as IconData,
                          size: 20,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          framework['name'] as String,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.text,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedFramework = newValue;
                    _selectedAlgorithm = null; // Reset algorithm when framework changes
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildAlgorithmSelection() {
    final isEnabled = _selectedFramework != null;
    final algorithms = isEnabled ? _getAlgorithmsForFramework(_selectedFramework!) : <String>[];
    
    return _buildCard(
      title: 'Step 2: Select Circuit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEnabled 
                ? 'Choose a circuit for benchmarking'
                : 'Select a framework first to enable circuit selection',
            style: TextStyle(
              fontSize: 14,
              color: isEnabled ? AppTheme.textSecondary : AppTheme.textSecondary.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          Opacity(
            opacity: isEnabled ? 1.0 : 0.5,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: _selectedAlgorithm != null 
                    ? AppTheme.accent.withOpacity(0.05)
                    : AppTheme.surface,
                border: Border.all(
                  color: _selectedAlgorithm != null 
                      ? AppTheme.accent 
                      : AppTheme.border, 
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedAlgorithm,
                  hint: Row(
                    children: [
                      Icon(
                        Icons.memory, 
                        size: 20, 
                        color: isEnabled ? AppTheme.textSecondary : AppTheme.textSecondary.withOpacity(0.4),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Select a circuit',
                        style: TextStyle(
                          fontSize: 16,
                          color: isEnabled ? AppTheme.textSecondary : AppTheme.textSecondary.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                  isExpanded: true,
                  icon: Icon(
                    Icons.arrow_drop_down, 
                    color: isEnabled ? AppTheme.primary : AppTheme.primary.withOpacity(0.3),
                  ),
                  items: isEnabled ? algorithms.map((algorithm) {
                    return DropdownMenuItem<String>(
                      value: algorithm,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            algorithm,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.text,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList() : null,
                  onChanged: isEnabled ? (String? newValue) {
                    setState(() {
                      _selectedAlgorithm = newValue;
                    });
                  } : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSizeSelection() {
    final isZkFriendly = _selectedAlgorithm != null && _isZkFriendlyHash(_selectedAlgorithm!);
    
    return _buildCard(
      title: 'Step 3: Select Input Size',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isZkFriendly 
                ? 'Choose input size (will be converted to field elements)'
                : 'Choose input size (bytes)',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.05),
              border: Border.all(
                color: AppTheme.success,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<InputSize>(
                value: _selectedInputSize,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                items: InputSize.values.map((size) {
                  return DropdownMenuItem<InputSize>(
                    value: size,
                    child: Row(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 18,
                          color: AppTheme.success,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          size.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.text,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          isZkFriendly 
                              ? '${size.fieldElements} field${size.fieldElements > 1 ? 's' : ''}'
                              : '${size.bytes} bytes',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (InputSize? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedInputSize = newValue;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZkFriendly
                        ? 'ZK-friendly hash: Input bytes will be packed into ${_selectedInputSize.fieldElements} field element(s) (31 bytes per field)'
                        : 'Non-ZK hash: Input will be ${_selectedInputSize.bytes} raw bytes',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomInput() {
    if (_availableInputs.isEmpty) {
      return _buildCard(
        title: 'Select Input',
        child: const Text(
          'No inputs available. Please check input files.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }

    // Adjust step number based on whether input size selection is shown
    final stepNumber = (_selectedFramework == 'noir' && _selectedAlgorithm != null) ? 4 : 3;

    return _buildCard(
      title: 'Step $stepNumber: Select Input',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a predefined input for benchmarking',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedInput,
                hint: Row(
                  children: const [
                    Icon(Icons.input, size: 20, color: AppTheme.textSecondary),
                    SizedBox(width: 12),
                    Text(
                      'Select an input',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                items: _availableInputs.map((InputData input) {
                  return DropdownMenuItem<String>(
                    value: input.name,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.data_object,
                          size: 18,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          input.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.text,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedInput = newValue;
                  });
                },
              ),
            ),
          ),
          if (_selectedInput != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Input Data',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getSelectedInputPreview(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }


  String _getSelectedInputPreview() {
    if (_selectedInput == null) return '';
    final input = _availableInputs.firstWhere((input) => input.name == _selectedInput);
    return _formatInputPreview(input.values);
  }

  String _formatInputPreview(List<String> values, {int maxItems = 1000}) {
    return '[${values.join(', ')}]';
  }

  Widget _buildRunButton() {
    final canRun = _selectedFramework != null && _selectedAlgorithm != null && _selectedInput != null;
    
    return Column(
      children: [
        if (canRun) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Text(
                      'Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSummaryRow('Framework', _getFrameworkDisplayName(_selectedFramework!)),
                const SizedBox(height: 10),
                _buildSummaryRow('Circuit', _selectedAlgorithm!),
                if (_selectedFramework == 'noir') ...[
                  const SizedBox(height: 10),
                  _buildSummaryRow('Input Size', _selectedInputSize.displayName),
                ],
                const SizedBox(height: 10),
                _buildSummaryRow('Input', _selectedInput!),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: canRun ? _runBenchmark : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canRun ? AppTheme.primary : AppTheme.border,
              foregroundColor: canRun ? Colors.white : AppTheme.textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: canRun ? 4 : 0,
            ),
            child: _isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Generating Proof...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        canRun ? Icons.play_arrow : Icons.info_outline,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        canRun 
                            ? 'Run Benchmark'
                            : 'Select Framework, Circuit & Input',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      children: [
        Container(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Text(
          ': ',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
              ),
            ],
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  String _getFrameworkDisplayName(String framework) {
    switch (framework) {
      case 'circom':
        return 'Circom';
      case 'halo2':
        return 'Halo2';
      case 'noir':
        return 'Noir';
      case 'risc0':
        return 'RISC Zero';
      default:
        return framework;
    }
  }

  List<String> _getAlgorithmsForFramework(String framework) {
    switch (framework) {
      case 'circom':
        return ['SHA256', 'Keccak256', 'Blake2s256', 'MiMC256', 'Pedersen', 'Poseidon'];
      case 'halo2':
        return ['Fibonacci'];
      case 'noir':
        // Base algorithms - size will be selected separately
        return ['SHA256', 'Keccak256', 'Poseidon', 'MiMC', 'Blake2', 'Blake3', 'RescuePrime', 'Anemoi'];
      case 'risc0':
        return ['Factor'];
      default:
        return [];
    }
  }

  /// Gets the full circuit name including size suffix for Noir circuits
  String _getNoirCircuitName(String algorithm, InputSize size) {
    final baseName = algorithm.toLowerCase();
    switch (baseName) {
      case 'sha256':
        return 'sha256_${size.bits}';
      case 'keccak256':
        return 'keccak256_${size.bits}';
      case 'poseidon':
        return 'poseidon_${size.bits}';
      case 'mimc':
        return 'mimc_${size.bits}';
      case 'blake2':
        return 'blake2_${size.bits}';
      case 'blake3':
        return 'blake3_${size.bits}';
      case 'rescueprime':
        return 'rescue_prime_${size.bits}';
      case 'anemoi':
        return 'anemoi_${size.bits}';
      default:
        return baseName;
    }
  }

  /// Checks if an algorithm is ZK-friendly (requires field element inputs)
  bool _isZkFriendlyHash(String algorithm) {
    return zkFriendlyHashes.contains(algorithm);
  }

  void _runBenchmark() async {
    if (_selectedFramework == null || _selectedAlgorithm == null || _selectedInput == null) return;

    // Immediately show loading state
    setState(() {
      _isLoading = true;
    });

    // Force UI to update by yielding to the event loop
    await Future.delayed(Duration.zero);

    if (!mounted) return;

    // Navigate immediately without waiting
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ProofResultPage(
          framework: _selectedFramework!,
          algorithm: _selectedAlgorithm!,
          selectedInputName: _selectedInput!,
          selectedInputData: _availableInputs.firstWhere((input) => input.name == _selectedInput!),
          inputSize: _selectedInputSize,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }
}

// Smooth Loading Widget with Pulsing Effect
class SmoothLoadingIndicator extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color color;

  const SmoothLoadingIndicator({
    Key? key,
    this.size = 60,
    this.strokeWidth = 5,
    this.color = AppTheme.primary,
  }) : super(key: key);

  @override
  State<SmoothLoadingIndicator> createState() => _SmoothLoadingIndicatorState();
}

class _SmoothLoadingIndicatorState extends State<SmoothLoadingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: RotationTransition(
            turns: _rotationController,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(
                strokeWidth: widget.strokeWidth,
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                backgroundColor: widget.color.withOpacity(0.1),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Stage 2: Proof Result Page
class ProofResultPage extends StatefulWidget {
  final String framework;
  final String algorithm;
  final String selectedInputName;
  final InputData selectedInputData;
  final InputSize inputSize;

  const ProofResultPage({
    super.key,
    required this.framework,
    required this.algorithm,
    required this.selectedInputName,
    required this.selectedInputData,
    this.inputSize = InputSize.bits256, // Default for non-Noir frameworks
  });

  @override
  State<ProofResultPage> createState() => _ProofResultPageState();
}

class _ProofResultPageState extends State<ProofResultPage> {
  bool _isGenerating = false;
  bool _isVerifying = false;
  bool? _isValid;
  String? _proofData;
  String? _error;
  
  // Store actual proof objects for verification
  CircomProofResult? _circomProofResult;
  Halo2ProofResult? _halo2ProofResult;
  Uint8List? _noirProofResult;
  
  // RISC-V results
  Risc0ProofOutput? _risc0ProofResult;
  Risc0VerifyOutput? _risc0VerifyResult;
  
  // Store Noir verification keys - now organized by circuit name
  final Map<String, Uint8List> _noirVerificationKeys = {};
  
  // Legacy verification key references (for backward compatibility)
  Uint8List? _noirMimcVerificationKey;
  Uint8List? _noirKeccakVerificationKey;
  Uint8List? _noirPoseidonVerificationKey;
  Uint8List? _noirPedersenVerificationKey;
  Uint8List? _noirSha256VerificationKey;
  Uint8List? _noirBlake2VerificationKey;
  Uint8List? _noirBlake3VerificationKey;
  Uint8List? _noirRescuePrimeVerificationKey;
  Uint8List? _noirAnemoiVerificationKey;
  
  // Benchmarking timing
  Duration? _proofGenerationTime;
  Duration? _proofVerificationTime;
  
  // Memory tracking during proof generation
  int _freeMemoryBeforeProof = 0;
  int _minFreeMemoryDuringProof = 0;
  int _freeMemoryAfterProof = 0;
  int _peakMemoryUsage = 0;
  
  // Battery tracking
  int _batteryBeforeProof = 0;
  int _batteryAfterProof = 0;
  
  // Timer to keep UI responsive
  Timer? _uiUpdateTimer;
  
  // Progress tracking
  String _currentStage = 'Initializing...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    // Start a timer to periodically trigger UI updates for smooth animation
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (mounted && _isGenerating) {
        setState(() {
          // Force rebuild to keep animation smooth
        });
      }
    });
    
    // Start proof generation after UI is fully built and rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Minimal delay to ensure smooth animation starts
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _generateProof();
        }
      });
    });
  }
  
  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.framework.toUpperCase()} - ${widget.algorithm}'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInputDisplay(),
                    const SizedBox(height: 24),
                    _buildProofSection(),
                    const SizedBox(height: 24),
                    _buildVerificationSection(),
                    const SizedBox(height: 24),
                    _buildBenchmarkingSection(),
                    const SizedBox(height: 24),
                    _buildResultsSection(),
                  ],
                ),
              ),
            ),
            // Show a full-screen loading overlay when first entering the page
            if (_isGenerating && _proofData == null)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Generating Proof',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This might take a while',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 8,
                            backgroundColor: AppTheme.border,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputDisplay() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Framework: ${widget.framework.toUpperCase()}',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Algorithm: ${widget.algorithm}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          if (widget.framework.toLowerCase() == 'noir') ...[
            const SizedBox(height: 8),
            Text(
              'Input Size: ${widget.inputSize.displayName} (${widget.inputSize.bytes} bytes)',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              zkFriendlyHashes.contains(widget.algorithm)
                  ? 'Type: ZK-friendly (${widget.inputSize.fieldElements} field element${widget.inputSize.fieldElements > 1 ? 's' : ''})'
                  : 'Type: Non-ZK (raw bytes)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Input: ${widget.selectedInputName}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              '[${widget.selectedInputData.values.take(widget.inputSize.bytes).join(', ')}${widget.selectedInputData.values.length > widget.inputSize.bytes ? ', ...' : ''}]',
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofSection() {
    // Don't show this section while generating (overlay handles it)
    if (_isGenerating && _proofData == null) {
      return const SizedBox.shrink();
    }
    
    return _buildCard(
      title: 'Proof Generation',
      child: Column(
        children: [
          if (_proofData != null)
            const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                SizedBox(width: 12),
                Text('Proof generated successfully'),
              ],
            )
          else if (_error != null)
            Row(
            children: [
                const Icon(Icons.error, color: AppTheme.danger, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Error: $_error')),
              ],
            )
          else
            const Text('Ready to generate proof'),
        ],
      ),
    );
  }
  
  Widget _buildVerificationSection() {
    return _buildCard(
      title: 'Proof Verification',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_proofData == null)
            const Text('Generate proof first')
          else if (_isVerifying)
            Row(
              children: const [
                SmoothLoadingIndicator(
                  size: 24,
                  strokeWidth: 2.5,
                  color: AppTheme.primary,
                ),
                SizedBox(width: 12),
                Text(
                  'Verifying proof...',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else if (_isValid != null)
            Row(
              children: [
                Icon(
                  _isValid! ? Icons.check_circle : Icons.cancel,
                  color: _isValid! ? AppTheme.success : AppTheme.danger,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(_isValid! ? 'Proof verified successfully' : 'Proof verification failed'),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _verifyProof,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Verify Proof',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_proofData == null) return const SizedBox.shrink();

    return _buildCard(
      title: 'Proof Data',
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
              color: AppTheme.background,
                    borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _proofData!,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: AppTheme.text,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildProofDetails(),
        ],
      ),
    );
  }
  
  Widget _buildBenchmarkingSection() {
    return _buildCard(
      title: 'Benchmarking Results',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_proofGenerationTime != null)
            _buildTimingRow(
              'Proof Generation',
              _proofGenerationTime!,
              Icons.timer,
              Colors.blue,
            ),
          if (_proofVerificationTime != null)
            _buildTimingRow(
              'Proof Verification',
              _proofVerificationTime!,
              Icons.verified,
              Colors.green,
            ),
          if (_proofGenerationTime != null && _proofVerificationTime != null)
            _buildTimingRow(
              'Total Time',
              Duration(
                milliseconds: _proofGenerationTime!.inMilliseconds + 
                           _proofVerificationTime!.inMilliseconds
              ),
              Icons.speed,
              Colors.orange,
            ),
        ],
      ),
    );
  }
  
  Widget _buildTimingRow(String label, Duration duration, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
            children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              _formatDuration(duration),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatDuration(Duration duration) {
    if (duration.inSeconds > 0) {
      return '${duration.inSeconds}.${(duration.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
    } else {
      return '${duration.inMilliseconds}ms';
    }
  }
  
  Widget _buildProofDetails() {
    switch (widget.framework.toLowerCase()) {
      case 'circom':
        return _buildCircomProofDetails();
      case 'halo2':
        return _buildHalo2ProofDetails();
      case 'noir':
        return _buildNoirProofDetails();
      case 'risc0':
        return _buildRisc0ProofDetails();
      default:
      return const SizedBox.shrink();
    }
  }

  Widget _buildCircomProofDetails() {
    if (_circomProofResult == null) return const SizedBox.shrink();
    
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          'Proof Details:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Text('Protocol: ${_circomProofResult!.proof.protocol}'),
        Text('Curve: ${_circomProofResult!.proof.curve}'),
        Text('Public Signals: ${_circomProofResult!.inputs.toString()}'),
        const SizedBox(height: 8),
              Text(
          'Proof Points:',
          style: TextStyle(
            fontSize: 14,
                  fontWeight: FontWeight.bold,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(height: 4),
        Text('π_a: [${_circomProofResult!.proof.a.x}, ${_circomProofResult!.proof.a.y}, ${_circomProofResult!.proof.a.z}]'),
        Text('π_b.x: [${_circomProofResult!.proof.b.x.join(', ')}]'),
        Text('π_b.y: [${_circomProofResult!.proof.b.y.join(', ')}]'),
        Text('π_b.z: [${_circomProofResult!.proof.b.z.join(', ')}]'),
        Text('π_c: [${_circomProofResult!.proof.c.x}, ${_circomProofResult!.proof.c.y}, ${_circomProofResult!.proof.c.z}]'),
      ],
    );
  }

  Widget _buildHalo2ProofDetails() {
    if (_halo2ProofResult == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Text(
          'Proof Details:',
            style: TextStyle(
              fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Text('Proof Size: ${_halo2ProofResult!.proof.length} bytes'),
        Text('Inputs: ${_halo2ProofResult!.inputs.toString()}'),
      ],
    );
  }

  Widget _buildNoirProofDetails() {
    if (_noirProofResult == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proof Details:',
            style: TextStyle(
            fontSize: 16,
              fontWeight: FontWeight.bold,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Text('Proof Size: ${_noirProofResult!.length} bytes'),
        Text('Algorithm: ${widget.algorithm}'),
      ],
    );
  }

  Widget _buildRisc0ProofDetails() {
    if (_risc0ProofResult == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proof Details:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Text('Receipt size: ${(_risc0ProofResult!.receipt.length / 1024).toStringAsFixed(1)} KB'),
        if (_risc0VerifyResult != null) ...[
            const SizedBox(height: 16),
            Text('Verification: ${_risc0VerifyResult!.isValid ? "PASSED" : "FAILED"}'),
            const SizedBox(height: 4),
            Text('Output value: ${_risc0VerifyResult!.outputValue}'),
          ],
      ],
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
                style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.text,
                ),
              ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
  
  void _generateProof() async {
    // Set generating state
    if (mounted) {
      setState(() {
        _isGenerating = true;
        _error = null;
        _currentStage = 'Generating Proof...';
        _progress = 0.1;
      });
    }

    // Give UI a moment to render the loading overlay
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    try {
      // Update stage: Loading assets
      if (mounted) {
        setState(() {
          _currentStage = 'Generating Proof...';
          _progress = 0.2;
        });
      }
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      
      // Update stage: Preparing inputs
      if (mounted) {
        setState(() {
          _currentStage = 'Generating Proof...';
          _progress = 0.3;
        });
      }
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      
      // Update stage: Generating proof
      if (mounted) {
        setState(() {
          _currentStage = 'Generating Proof...';
          _progress = 0.4;
        });
      }
      
      // Generate actual proof using MoPro framework 
      _proofData = await _generateRealProof();
      
      // Update stage: Finalizing
      if (mounted) {
        setState(() {
          _currentStage = 'Generating Proof...';
          _progress = 0.9;
        });
      }
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (mounted) {
        // Stop the timer
        _uiUpdateTimer?.cancel();
        setState(() {
          _isGenerating = false;
          _currentStage = 'Complete!';
          _progress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        // Stop the timer
        _uiUpdateTimer?.cancel();
        setState(() {
          _isGenerating = false;
          _error = e.toString();
          _currentStage = 'Error occurred';
        });
      }
    }
  }

  Future<String> _generateRealProof() async {
    final moproFlutterPlugin = MoproFlutter();
    
    switch (widget.framework.toLowerCase()) {
      case 'circom':
        return await _generateCircomProof(moproFlutterPlugin);
      case 'halo2':
        return await _generateHalo2Proof(moproFlutterPlugin);
      case 'noir':
        return await _generateNoirProof(moproFlutterPlugin);
      case 'risc0':
        return await _generateRisc0Proof(moproFlutterPlugin);
      default:
        throw Exception('Unknown framework: ${widget.framework}');
    }
  }

  Future<String> _generateCircomProof(MoproFlutter plugin) async {
    // Get input data based on algorithm (special case for Poseidon)
    final inputData = _getInputDataForAlgorithm();
    final inputs = _inputDataToByteArrayJson(inputData);
    
    // Get the appropriate zkey path based on algorithm
    final zkeyPath = _getZkeyPath();
    
    // Capture memory and battery BEFORE proof generation
    _freeMemoryBeforeProof = SysInfo.getFreePhysicalMemory();
    final battery = Battery();
    _batteryBeforeProof = await battery.batteryLevel;
    
    // Start timing
    final stopwatch = Stopwatch()..start();
    
    // Start memory monitoring in background
    _startMemoryMonitoring();
    
    // Generate proof using actual MoPro
    final proofResult = await plugin.generateCircomProof(
      zkeyPath, 
            inputs, 
      ProofLib.arkworks
    );
    
    stopwatch.stop();
    
    // Capture memory and battery AFTER proof generation
    _freeMemoryAfterProof = SysInfo.getFreePhysicalMemory();
    _batteryAfterProof = await battery.batteryLevel;
    
    if (proofResult == null) {
      throw Exception('Failed to generate Circom proof');
    }
    
    setState(() {
      _circomProofResult = proofResult;
      _proofGenerationTime = stopwatch.elapsed;
    });
    
    return _formatCircomProofOutput(proofResult);
  }

  Future<String> _generateHalo2Proof(MoproFlutter plugin) async {
    // Convert selected input to Halo2 format
    final inputData = _getInputDataForAlgorithm();
    final inputs = {
      "out": [inputData.join(" ")]
    };
    
    // Capture memory and battery BEFORE proof generation
    _freeMemoryBeforeProof = SysInfo.getFreePhysicalMemory();
    final battery = Battery();
    _batteryBeforeProof = await battery.batteryLevel;
    
    // Start timing
    final stopwatch = Stopwatch()..start();
    
    // Start memory monitoring in background
    _startMemoryMonitoring();
    
    // Generate proof using actual MoPro
    final proofResult = await plugin.generateHalo2Proof(
      "assets/plonk_fibonacci_srs.bin",
      "assets/plonk_fibonacci_pk.bin", 
      inputs.cast<String, List<String>>()
    );
    
    // Stop timing and store
    stopwatch.stop();
    
    // Capture memory and battery AFTER proof generation
    _freeMemoryAfterProof = SysInfo.getFreePhysicalMemory();
    _batteryAfterProof = await battery.batteryLevel;
    
    if (proofResult == null) {
      throw Exception('Failed to generate Halo2 proof');
    }
    
    // Store the proof result for verification
    setState(() {
      _halo2ProofResult = proofResult;
      _proofGenerationTime = stopwatch.elapsed;
    });
    
    // Format the actual proof data
    return _formatHalo2ProofOutput(proofResult);
  }

  Future<String> _generateNoirProof(MoproFlutter plugin) async {
    // Get input data and convert to Noir format based on algorithm type
    final inputData = _getInputDataForAlgorithm();
    final List<String> noirInputs = _inputDataToNoirInput(inputData);
    
    // Get the appropriate circuit path and settings (now uses inputSize)
    final (circuitPath, srsPath, onChain, vk) = await _getNoirSettings();
    
    // Capture memory and battery BEFORE proof generation
    _freeMemoryBeforeProof = SysInfo.getFreePhysicalMemory();
    final battery = Battery();
    _batteryBeforeProof = await battery.batteryLevel;
    
    // Start timing
    final stopwatch = Stopwatch()..start();
    
    // Start memory monitoring in background
    _startMemoryMonitoring();
    
    // Generate proof using actual MoPro with selected inputs
    final proof = await plugin.generateNoirProof(
      circuitPath,
      srsPath,
      noirInputs,
      onChain,
      vk,
      false // lowMemoryMode
    );
    
    // Stop timing and store
    stopwatch.stop();
    
    // Capture memory and battery AFTER proof generation
    _freeMemoryAfterProof = SysInfo.getFreePhysicalMemory();
    _batteryAfterProof = await battery.batteryLevel;
    
    // Store the proof result for verification
    setState(() {
      _noirProofResult = proof;
      _proofGenerationTime = stopwatch.elapsed;
    });
    
    // Format the actual proof data
    return _formatNoirProofOutput(proof);
  }

  Future<String> _generateRisc0Proof(MoproFlutter plugin) async {
    // Get input data and convert to numeric value for risc0
    final inputData = _getInputDataForAlgorithm();
    // For risc0, we expect a numeric input - use first value or parse from joined string
    int numericInput = int.tryParse(inputData.first) ?? 17; // Default to 17 if parsing fails
    
    // Capture memory and battery BEFORE proof generation
    _freeMemoryBeforeProof = SysInfo.getFreePhysicalMemory();
    final battery = Battery();
    _batteryBeforeProof = await battery.batteryLevel;
    
    // Start timing
    final stopwatch = Stopwatch()..start();
    
    // Start memory monitoring in background
    _startMemoryMonitoring();
    
    // Generate proof using actual MoPro
    final proofResult = await plugin.generateRisc0Proof(numericInput);
    
    // Stop timing and store
    stopwatch.stop();
    
    // Capture memory and battery AFTER proof generation
    _freeMemoryAfterProof = SysInfo.getFreePhysicalMemory();
    _batteryAfterProof = await battery.batteryLevel;
    
    // Store the proof result for verification
    setState(() {
      _risc0ProofResult = proofResult;
      _proofGenerationTime = stopwatch.elapsed;
    });
    
    // Format the actual proof data
    return _formatRisc0ProofOutput(proofResult);
  }

  String _getZkeyPath() {
    switch (widget.algorithm.toLowerCase()) {
      case 'sha256':
        return "assets/sha256.zkey";
      case 'keccak256':
        return "assets/keccak.zkey";
      case 'blake2s256':
        return "assets/blake2s256.zkey";
      case 'mimc256':
        return "assets/mimc256.zkey";
      case 'pedersen':
        return "assets/pedersen.zkey";
      case 'poseidon':
        return "assets/poseidon.zkey";
      default:
        return "assets/sha256.zkey";
    }
  }

  Future<(String, String, bool, Uint8List)> _getNoirSettings() async {
    final moproFlutterPlugin = MoproFlutter();
    const bool lowMemoryMode = false;
    
    // Get the circuit name with size suffix
    final circuitName = _getNoirCircuitNameForProof();
    
    // Build asset paths using circuit name
    final String assetPath = "assets/$circuitName.json";
    final String srsPath = "assets/$circuitName.srs";
    final String vkPath = "assets/$circuitName.vk";
    
    // ZK-friendly hashes don't need onChain verification
    final bool onChain = !zkFriendlyHashes.contains(widget.algorithm);
    
    // Try to load verification key from cache or assets
    Uint8List? verificationKey = _noirVerificationKeys[circuitName];
    
    if (verificationKey == null) {
      try {
        final vkAsset = await rootBundle.load(vkPath);
        verificationKey = vkAsset.buffer.asUint8List();
        _noirVerificationKeys[circuitName] = verificationKey;
      } catch (e) {
        // Generate verification key if not found in assets
        verificationKey = await moproFlutterPlugin.getNoirVerificationKey(
          assetPath, srsPath, onChain, lowMemoryMode,
        );
        if (verificationKey != null) {
          _noirVerificationKeys[circuitName] = verificationKey;
        }
      }
    }
    
    return (assetPath, srsPath, onChain, verificationKey!);
  }

  /// Gets the circuit name for the current algorithm and input size
  String _getNoirCircuitNameForProof() {
    final baseName = widget.algorithm.toLowerCase();
    final size = widget.inputSize.bits;
    
    switch (baseName) {
      case 'sha256':
        return 'sha256_$size';
      case 'keccak256':
        return 'keccak256_$size';
      case 'poseidon':
        return 'poseidon_$size';
      case 'mimc':
        return 'mimc_$size';
      case 'blake2':
        return 'blake2_$size';
      case 'blake3':
        return 'blake3_$size';
      case 'rescueprime':
        return 'rescue_prime_$size';
      case 'anemoi':
        return 'anemoi_$size';
      default:
        return baseName;
    }
  }

  String _formatCircomProofOutput(CircomProofResult proofResult) {
    final proof = proofResult.proof;
    final inputs = proofResult.inputs;
    
    return '''
${widget.algorithm} Proof: ProofCalldata(
  a: G1Point(
    x: ${proof.a.x},
    y: ${proof.a.y},
    z: ${proof.a.z},
  ),
  b: G2Point(
    x: [${proof.b.x.join(', ')}],
    y: [${proof.b.y.join(', ')}],
    z: [${proof.b.z.join(', ')}],
  ),
  c: G1Point(
    x: ${proof.c.x},
    y: ${proof.c.y},
    z: ${proof.c.z},
  ),
  protocol: ${proof.protocol},
  curve: ${proof.curve}
)

Public Signals: ${inputs.toString()}

Framework: ${widget.framework}
Algorithm: ${widget.algorithm}
Input: [${_getInputDataForAlgorithm().join(', ')}]
Timestamp: ${DateTime.now().millisecondsSinceEpoch}
''';
  }

  String _formatHalo2ProofOutput(Halo2ProofResult proofResult) {
    return '''
${widget.algorithm} Proof: Halo2ProofResult(
  proof: ${proofResult.proof.toString()}
  inputs: ${proofResult.inputs.toString()}
)

Framework: ${widget.framework}
Algorithm: ${widget.algorithm}
Input: [${_getInputDataForAlgorithm().join(', ')}]
Timestamp: ${DateTime.now().millisecondsSinceEpoch}
''';
  }

  String _formatNoirProofOutput(Uint8List proof) {
    return '''
${widget.algorithm} Proof: NoirProof(
  proof: ${proof.toString()}
  size: ${proof.length} bytes
)

Framework: ${widget.framework}
Algorithm: ${widget.algorithm}
Input: [${_getInputDataForAlgorithm().join(', ')}]
Timestamp: ${DateTime.now().millisecondsSinceEpoch}
''';
  }

  String _formatRisc0ProofOutput(Risc0ProofOutput proofResult) {
    return '''
${widget.algorithm} Proof: Risc0ProofOutput(
  receipt: ${proofResult.receipt.toString()}
)

Framework: ${widget.framework}
Algorithm: ${widget.algorithm}
Input: [${_getInputDataForAlgorithm().join(', ')}]
Timestamp: ${DateTime.now().millisecondsSinceEpoch}
''';
  }





  List<String> _getInputDataForAlgorithm() {
    // Get the selected input data from JSON file
    List<String> inputData = widget.selectedInputData.values;
    
    // For Noir framework, use the selected input size
    if (widget.framework.toLowerCase() == 'noir') {
      final targetBytes = widget.inputSize.bytes;
      
      // Convert string values to bytes
      List<int> bytes = inputData.map((s) => int.tryParse(s) ?? 0).toList();
      
      // Pad or truncate to target size
      bytes = padOrTruncateBytes(bytes, targetBytes);
      
      return bytes.map((b) => b.toString()).toList();
    }
    
    // Special case for Poseidon (Circom): use exactly 8 bytes (as per the circuit requirement)
    if (widget.algorithm.toLowerCase() == 'poseidon') {
      // Take first 8 bytes, pad with zeros if needed
      List<String> poseidonInput = inputData.take(8).toList();
      while (poseidonInput.length < 8) {
        poseidonInput.add('0');
      }
      return poseidonInput;
    }
    
    // Blake2 and Blake3 require exactly 32 bytes input
    final algorithmLower = widget.algorithm.toLowerCase();
    if (algorithmLower == 'blake2' || algorithmLower == 'blake3') {
      List<String> blakeInput = List<String>.from(inputData);
      // Take first 32 bytes, pad with zeros if needed
      if (blakeInput.length > 32) {
        blakeInput = blakeInput.take(32).toList();
      } else {
        while (blakeInput.length < 32) {
          blakeInput.add('0');
        }
      }
      return blakeInput;
    }
    
    return inputData;
  }

  String _inputDataToByteArrayJson(List<String> inputData) {
    // Convert input data to JSON format for Circom
    return '{"in": [${inputData.map((b) => '"$b"').join(', ')}]}';
  }

  List<String> _inputDataToNoirInput(List<String> inputData) {
    // Check if this is a ZK-friendly hash that needs field element conversion
    final isZkFriendly = zkFriendlyHashes.contains(widget.algorithm);
    
    if (isZkFriendly) {
      // Convert bytes to field elements for ZK-friendly hashes
      final bytes = inputData.map((s) => int.tryParse(s) ?? 0).toList();
      final fieldElements = bytesToFieldElements(bytes);
      
      // Convert field elements to hex strings
      return fieldElementsToHexStrings(fieldElements);
    } else {
      // For non-ZK hashes, just return the bytes as-is
      // Ensure we have exactly the right number of bytes for the input size
      final targetBytes = widget.inputSize.bytes;
      final paddedData = List<String>.from(inputData);
      
      while (paddedData.length < targetBytes) {
        paddedData.add('0');
      }
      
      return paddedData.take(targetBytes).toList();
    }
  }

  void _verifyProof() async {
    setState(() {
      _isVerifying = true;
    });
    
    // Give the UI a chance to update and show the loading indicator
    await Future.delayed(const Duration(milliseconds: 100));
    
    try {
      // Perform actual verification using MoPro framework
      final isValid = await _performRealVerification();
      
      // Update UI immediately after verification
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _isValid = isValid;
        });
      }
      
      // Send data to backend asynchronously without blocking UI
      if (isValid) {
        _sendDataToBackend().catchError((error) {
          debugPrint('Error sending data to backend: $error');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { 
          _isVerifying = false;
          _isValid = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<bool> _performRealVerification() async {
    final moproFlutterPlugin = MoproFlutter();
    
    bool isValid;
    switch (widget.framework.toLowerCase()) {
      case 'circom':
        isValid = await _verifyCircomProof(moproFlutterPlugin);
        break;
      case 'halo2':
        isValid = await _verifyHalo2Proof(moproFlutterPlugin);
        break;
      case 'noir':
        isValid = await _verifyNoirProof(moproFlutterPlugin);
        break;
      case 'risc0':
        isValid = await _verifyRisc0Proof(moproFlutterPlugin);
        break;
      default:
        throw Exception('Unknown framework: ${widget.framework}');
    }
    
    return isValid;
  }

  Future<bool> _verifyCircomProof(MoproFlutter plugin) async {
    if (_circomProofResult == null) {
      throw Exception('No proof available for verification');
    }
    
    final zkeyPath = _getZkeyPath();
    
    // Start timing
    final stopwatch = Stopwatch()..start();
    
    final result = await plugin.verifyCircomProof(zkeyPath, _circomProofResult!, ProofLib.arkworks);
    
    // Stop timing and store
    stopwatch.stop();
    setState(() {
      _proofVerificationTime = stopwatch.elapsed;
    });
    
    return result;
  }

  Future<bool> _verifyHalo2Proof(MoproFlutter plugin) async {
    if (_halo2ProofResult == null) {
      throw Exception('No proof available for verification');
    }
    
    // Start timing
    final stopwatch = Stopwatch()..start();
    
    final result = await plugin.verifyHalo2Proof(
      "assets/plonk_fibonacci_srs.bin",
      "assets/plonk_fibonacci_vk.bin",
      _halo2ProofResult!.proof,
      _halo2ProofResult!.inputs
    );
    
    // Stop timing and store
    stopwatch.stop();
      setState(() {
      _proofVerificationTime = stopwatch.elapsed;
    });
    
    return result;
  }

  Future<bool> _verifyNoirProof(MoproFlutter plugin) async {
    if (_noirProofResult == null) {
      throw Exception('No proof available for verification');
    }
    
    final (circuitPath, srsPath, onChain, vk) = await _getNoirSettings();
    
    // Start timing
    final stopwatch = Stopwatch()..start();
    
    final result = await plugin.verifyNoirProof(circuitPath, _noirProofResult!, onChain, vk, false);
    
    // Stop timing and store
    stopwatch.stop();
    setState(() {
      _proofVerificationTime = stopwatch.elapsed;
    });
    
    return result;
  }

  Future<bool> _verifyRisc0Proof(MoproFlutter plugin) async {
    if (_risc0ProofResult == null) {
      throw Exception('No proof available for verification');
    }
    
    // Start timing
    final stopwatch = Stopwatch()..start();
    
    final verifyResult = await plugin.verifyRisc0Proof(_risc0ProofResult!.receipt);
    
    // Stop timing and store
    stopwatch.stop();
    setState(() {
      _proofVerificationTime = stopwatch.elapsed;
      _risc0VerifyResult = verifyResult;
    });
    
    return verifyResult.isValid;
  }

  // Collect device information and send to backend
  Future<void> _sendDataToBackend() async {
    try {
      final deviceInfo = await _collectDeviceInfo();
      final benchmarkData = _prepareBenchmarkData(deviceInfo);
      
      print('=== Sending Data to Backend ===');
      print('Data: ${jsonEncode(benchmarkData)}');
      
      // Send to backend API
      final response = await http.post(
        Uri.parse('https://deimos-fork.onrender.com/api/benchmark-result'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(benchmarkData),
      );

      print('=== Backend Response ===');
      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✓ Data successfully sent to backend');
      } else {
        print('✗ Failed to send data: ${response.statusCode}');
      }
    } catch (e) {
      print('✗ Error sending data to backend: $e');
    }
  }
  
  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    Map<String, dynamic> deviceData = {};
    
    try {
      // Collect system information (RAM, CPU)
      final systemInfo = await _collectSystemInfo();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceData = {
          'platform': 'Android',
          'device': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'androidVersion': androidInfo.version.release,
          'androidId': androidInfo.id,
          // Add system info
          ...systemInfo,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceData = {
          'platform': 'iOS',
          'device': iosInfo.model,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'name': iosInfo.name,
          'identifierForVendor': iosInfo.identifierForVendor,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
          'utsname': {
            'machine': iosInfo.utsname.machine,
            'sysname': iosInfo.utsname.sysname,
          },
          // Add system info
          ...systemInfo,
        };
      }
    } catch (e) {
      print('Error collecting device info: $e');
      deviceData = {'platform': 'Unknown', 'error': e.toString()};
    }
    
    return deviceData;
  }
  
  Future<Map<String, dynamic>> _collectSystemInfo() async {
    try {
      // Get memory information
      final totalPhysicalMemory = SysInfo.getTotalPhysicalMemory(); // in bytes
      
      // Calculate memory used during proof generation
      final memoryUsedBeforeProof = totalPhysicalMemory - _freeMemoryBeforeProof;
      final memoryUsedAfterProof = totalPhysicalMemory - _freeMemoryAfterProof;
      
      // Calculate memory consumed by proof generation
      final memoryConsumedByProof = _peakMemoryUsage - memoryUsedBeforeProof;
      
      return {
        'memory': {
          'totalPhysicalMemory': totalPhysicalMemory,
          
          // Memory BEFORE proof generation
          'memoryUsedBeforeProof': memoryUsedBeforeProof,
          
          // Memory DURING proof generation (peak usage)
          'peakMemoryUsage': _peakMemoryUsage,
          
          // Memory consumed specifically by proof generation
          'memoryConsumedByProof': memoryConsumedByProof,

          // Peak memory load during percentage
          'peakMemoryLoadInPercentage': _peakMemoryUsage / totalPhysicalMemory * 100,

          // Memory consumed percentage
          'memoryConsumedInPercentage': memoryConsumedByProof / totalPhysicalMemory * 100,
        },
        'battery': {
          'batteryBeforeProof': _batteryBeforeProof,
          'batteryAfterProof': _batteryAfterProof,
          'batteryConsumed': _batteryBeforeProof - _batteryAfterProof,
        },
      };
    } catch (e) {
      // Silently handle errors and return minimal info
      return {
        'memory': {'error': e.toString()},
      };
    }
  }
  
  // Monitor memory usage during proof generation
  void _startMemoryMonitoring() {
    _peakMemoryUsage = 0;
    _minFreeMemoryDuringProof = 0;
    
    // Sample memory every 100ms during proof generation
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isGenerating) {
        final currentFreeMemory = SysInfo.getFreePhysicalMemory();
        final currentUsedMemory = SysInfo.getTotalPhysicalMemory() - currentFreeMemory;
        
        // Track peak memory usage
        if (currentUsedMemory > _peakMemoryUsage) {
          _peakMemoryUsage = currentUsedMemory;
          _minFreeMemoryDuringProof = currentFreeMemory;
        }
      } else {
        timer.cancel();
      }
    });
  }
  
  Map<String, dynamic> _prepareBenchmarkData(Map<String, dynamic> deviceInfo) {
    return {
      // Circuit and framework info
      'circuit': widget.algorithm,
      'framework': 'MoPro',
      'language': widget.framework,
      
      // Timing data
      'provingTimeMiliSeconds': (_proofGenerationTime?.inMilliseconds ?? 0),
      'verificationTimeMiliSeconds': (_proofVerificationTime?.inMilliseconds ?? 0),
      
      // Device details
      'deviceInfo': deviceInfo,
      
      // Additional metadata
      'proofSize': _getProofSize(),

      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  int _getProofSize() {
    if (_circomProofResult != null) {
      return _proofData?.length ?? 0;
    } else if (_halo2ProofResult != null) {
      return _halo2ProofResult!.proof.length;
    } else if (_noirProofResult != null) {
      return _noirProofResult!.length;
    } else if (_risc0ProofResult != null) {
      return _risc0ProofResult!.receipt.length;
    }
    return 0;
  }

}

