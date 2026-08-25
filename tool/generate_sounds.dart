// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

void main() {
  Directory('assets/sounds').createSync(recursive: true);

  // 1. Generate new_order.wav (Joyful ascending 4-note bell jingle like Zomato/Swiggy order alert)
  final newOrderWav = generateMelodicJingle(
    frequencies: [523.25, 659.25, 783.99, 1046.50, 1318.51], // C5, E5, G5, C6, E6
    noteStarts: [0.0, 0.12, 0.24, 0.36, 0.48],
    noteDurations: [0.35, 0.35, 0.35, 0.55, 0.8],
    totalDuration: 1.5,
  );
  File('assets/sounds/new_order.wav').writeAsBytesSync(newOrderWav);
  print('Generated assets/sounds/new_order.wav');

  // 2. Generate success_ding.wav (Crisp Apple Pay style double glass ding)
  final successWav = generateMelodicJingle(
    frequencies: [783.99, 1174.66], // G5, D6
    noteStarts: [0.0, 0.14],
    noteDurations: [0.3, 0.6],
    totalDuration: 0.85,
  );
  File('assets/sounds/success_ding.wav').writeAsBytesSync(successWav);
  print('Generated assets/sounds/success_ding.wav');

  // 3. Generate new_alert.wav (Clear dual alert chime)
  final alertWav = generateMelodicJingle(
    frequencies: [880.0, 1046.50, 1318.51], // A5, C6, E6
    noteStarts: [0.0, 0.15, 0.30],
    noteDurations: [0.35, 0.35, 0.6],
    totalDuration: 1.0,
  );
  File('assets/sounds/new_alert.wav').writeAsBytesSync(alertWav);
  print('Generated assets/sounds/new_alert.wav');
}

Uint8List generateMelodicJingle({
  required List<double> frequencies,
  required List<double> noteStarts,
  required List<double> noteDurations,
  required double totalDuration,
  int sampleRate = 44100,
}) {
  final totalSamples = (totalDuration * sampleRate).toInt();
  final buffer = Float64List(totalSamples);

  for (int n = 0; n < frequencies.length; n++) {
    final freq = frequencies[n];
    final startSec = noteStarts[n];
    final durSec = noteDurations[n];
    final startIdx = (startSec * sampleRate).toInt();
    final endIdx = min(totalSamples, startIdx + (durSec * sampleRate).toInt());

    for (int i = startIdx; i < endIdx; i++) {
      final t = (i - startIdx) / sampleRate;
      final progress = t / durSec;

      // Bell envelope (Fast punchy attack, smooth exponential ring decay)
      double envelope = 0.0;
      if (progress < 0.03) {
        envelope = progress / 0.03;
      } else {
        envelope = exp(-4.5 * (progress - 0.03));
      }

      // Additive synthesis for rich metallic/glass bell warmth (Fundamental + 2nd + 3rd + 4.2x inharmonic overtone)
      final sample = (sin(2 * pi * freq * t) * 0.55 +
              sin(2 * pi * (freq * 2) * t) * 0.25 +
              sin(2 * pi * (freq * 3) * t) * 0.12 +
              sin(2 * pi * (freq * 4.2) * t) * 0.08) *
          envelope;

      buffer[i] += sample;
    }
  }

  // Normalize to prevent clipping
  double maxAmp = 0.0;
  for (int i = 0; i < totalSamples; i++) {
    if (buffer[i].abs() > maxAmp) maxAmp = buffer[i].abs();
  }
  if (maxAmp > 0) {
    for (int i = 0; i < totalSamples; i++) {
      buffer[i] = (buffer[i] / maxAmp) * 0.92;
    }
  }

  // Encode 16-bit Mono WAV
  return encodeWav(buffer, sampleRate);
}

Uint8List encodeWav(Float64List samples, int sampleRate) {
  final numSamples = samples.length;
  final numChannels = 1;
  final bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  final blockAlign = numChannels * (bitsPerSample ~/ 8);
  final dataSize = numSamples * (bitsPerSample ~/ 8);
  final fileSize = 36 + dataSize;

  final bytes = ByteData(44 + dataSize);

  // RIFF header
  bytes.setUint8(0, 0x52); // 'R'
  bytes.setUint8(1, 0x49); // 'I'
  bytes.setUint8(2, 0x46); // 'F'
  bytes.setUint8(3, 0x46); // 'F'
  bytes.setUint32(4, fileSize, Endian.little);
  bytes.setUint8(8, 0x57);  // 'W'
  bytes.setUint8(9, 0x41);  // 'A'
  bytes.setUint8(10, 0x56); // 'V'
  bytes.setUint8(11, 0x45); // 'E'

  // fmt subchunk
  bytes.setUint8(12, 0x66); // 'f'
  bytes.setUint8(13, 0x6D); // 'm'
  bytes.setUint8(14, 0x74); // 't'
  bytes.setUint8(15, 0x20); // ' '
  bytes.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
  bytes.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
  bytes.setUint16(22, numChannels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, byteRate, Endian.little);
  bytes.setUint16(32, blockAlign, Endian.little);
  bytes.setUint16(34, bitsPerSample, Endian.little);

  // data subchunk
  bytes.setUint8(36, 0x64); // 'd'
  bytes.setUint8(37, 0x61); // 'a'
  bytes.setUint8(38, 0x74); // 't'
  bytes.setUint8(39, 0x61); // 'a'
  bytes.setUint32(40, dataSize, Endian.little);

  int offset = 44;
  for (int i = 0; i < numSamples; i++) {
    final sampleVal = (samples[i].clamp(-1.0, 1.0) * 32767).toInt();
    bytes.setInt16(offset, sampleVal, Endian.little);
    offset += 2;
  }

  return bytes.buffer.asUint8List();
}
