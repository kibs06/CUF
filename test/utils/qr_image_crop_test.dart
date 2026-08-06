import 'package:app/utils/qr_image_crop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrImageAutoCrop.cornersToRect', () {
    test('builds a bounding box from 4 corner points', () {
      const corners = [
        Offset(10, 20),
        Offset(110, 25),
        Offset(15, 120),
        Offset(105, 130),
      ];
      final rect = QrImageAutoCrop.cornersToRect(corners);
      expect(rect, isNotNull);
      expect(rect!.left, 10);
      expect(rect.top, 20);
      expect(rect.right, 110);
      expect(rect.bottom, 130);
    });

    test('returns null when fewer than 4 corners are given', () {
      expect(QrImageAutoCrop.cornersToRect(const [Offset.zero]), isNull);
      expect(
        QrImageAutoCrop.cornersToRect(const [
          Offset.zero,
          Offset(1, 1),
          Offset(2, 2),
        ]),
        isNull,
      );
    });

    test('returns null for a degenerate (zero-area) box', () {
      // All points on the same vertical line → zero width.
      expect(
        QrImageAutoCrop.cornersToRect(const [
          Offset(5, 0),
          Offset(5, 10),
          Offset(5, 20),
          Offset(5, 30),
        ]),
        isNull,
      );
    });
  });

  group('QrImageAutoCrop.fitScale', () {
    test('returns 1.0 when already within the max dimension', () {
      expect(QrImageAutoCrop.fitScale(500, 400, 1024), 1.0);
      expect(QrImageAutoCrop.fitScale(1024, 1024, 1024), 1.0);
    });

    test('downscales uniformly when larger than the max dimension', () {
      final scale = QrImageAutoCrop.fitScale(2048, 1024, 1024);
      expect(scale, closeTo(0.5, 1e-9));
      // Never upscales the smaller dimension beyond the cap.
      final scale2 = QrImageAutoCrop.fitScale(3000, 1500, 1024);
      expect(scale2, closeTo(1024 / 3000, 1e-9));
    });
  });
}
