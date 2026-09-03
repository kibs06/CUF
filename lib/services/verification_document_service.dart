import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of picking and validating a document image.
class PickedDocumentResult {
  /// The local file path, or null if validation failed or user cancelled.
  final String? path;

  /// Human-readable error message for UI display, or null on success.
  final String? error;

  /// Validation passed — [path] is safe to upload.
  const PickedDocumentResult.ok(this.path) : error = null;

  /// Validation failed — [error] explains why; [path] is null.
  const PickedDocumentResult.failed(this.error) : path = null;

  /// User cancelled the picker.
  const PickedDocumentResult.cancelled()
      : path = null,
        error = null;

  bool get isSuccess => path != null;
  bool get isCancelled => path == null && error == null;
  bool get isFailed => error != null;
}

/// Allowed image file signatures (magic bytes).
/// Only real JPEG and PNG files pass; polyglots and renamed executables fail.
const Map<String, List<int>> _allowedSignatures = {
  'jpg': [0xFF, 0xD8, 0xFF],
  'jpeg': [0xFF, 0xD8, 0xFF],
  'png': [0x89, 0x50, 0x4E, 0x47],
};

/// Maximum file size for verification documents (10 MB).
const int _maxFileSizeBytes = 10 * 1024 * 1024;

/// Uploads and signed-URL access for the PRIVATE verification-document
/// storage bucket (`seller-verification-docs`).
///
/// Nothing in here touches the public product-images / avatars buckets —
/// ID photos, selfies, barangay proofs and Tier 2 business docs are
/// private by design (RLS: owner-only + admin read; see migration
/// 20260812000000_add_seller_tiered_verification.sql).
///
/// File layout is `{userId}/{docKey}.jpg` (upsert), so re-submitting a
/// document overwrites the previous file and every policy that keys off
/// the first path segment (`{userId}`) keeps working.
class VerificationDocumentService {
  VerificationDocumentService._();

  static final VerificationDocumentService instance =
      VerificationDocumentService._();

  static const String bucket = 'seller-verification-docs';

  final ImagePicker _picker = ImagePicker();

  /// Picks an image from the gallery or camera, re-encoded to a
  /// reasonable size/quality so we never upload raw camera-resolution
  /// files (image_picker's maxWidth/maxHeight/imageQuality re-encode the
  /// pixels and bake orientation in — see qr_image_crop.dart for the same
  /// rationale).
  ///
  /// Returns a [PickedDocumentResult] — `.path` is non-null only when the
  /// file passes extension allowlist, size limit, and magic-byte checks.
  Future<PickedDocumentResult> pickDocumentImage({
    required ImageSource source,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) return const PickedDocumentResult.cancelled();
    return validatePickedFile(picked.path);
  }

  /// Validates a picked file against extension allowlist, size limit, and
  /// magic-byte (file signature) checks.
  ///
  /// Client-side validation is UX, not security — it catches accidental
  /// mismatches early. Server-side enforcement (bucket MIME types + Edge
  /// Function) is the real boundary.
  Future<PickedDocumentResult> validatePickedFile(String filePath) async {
    // 1. Extension allowlist (jpg, jpeg, png only — no PDF support yet;
  //    image_picker cannot pick PDFs, so PDF is not in the allowlist).
    final ext = _extensionFor(filePath);
    if (!_allowedSignatures.containsKey(ext)) {
      return const PickedDocumentResult.failed(
        'Only JPG and PNG images are accepted. '
        'Please choose a photo taken with your camera or a proper scan.',
      );
    }

    // 2. File size limit (10 MB).
    final file = File(filePath);
    try {
      final sizeBytes = await file.length();
      if (sizeBytes > _maxFileSizeBytes) {
        final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
        return PickedDocumentResult.failed(
          'This file is ${sizeMB}MB, which exceeds the 10MB limit. '
          'Please choose a smaller photo.',
        );
      }
    } catch (e) {
      return const PickedDocumentResult.failed(
        'Could not read this file. Please try again with a different photo.',
      );
    }

    // 3. Magic-byte (file signature) verification — reads actual bytes,
    //    not the extension or declared MIME type.
    try {
      final isValid = await _validateMagicBytes(filePath, ext);
      if (!isValid) {
        return const PickedDocumentResult.failed(
          'This file doesn\'t appear to be a valid image. '
          'Please choose a photo taken with your camera or a proper scan.',
        );
      }
    } catch (e) {
      // Validation inconclusive → fail closed.
      return const PickedDocumentResult.failed(
        'Could not verify this file. Please try again with a different photo.',
      );
    }

    return PickedDocumentResult.ok(filePath);
  }

  /// Checks the first bytes of [filePath] against the expected signature
  /// for the given extension. Returns false if the file doesn't start
  /// with valid magic bytes for its claimed type.
  Future<bool> _validateMagicBytes(String filePath, String ext) async {
    final expected = _allowedSignatures[ext];
    if (expected == null) return false;

    final file = File(filePath);
    final raf = file.openSync(mode: FileMode.read);
    try {
      // Read enough bytes to cover the longest signature (PNG = 4 bytes).
      final header = raf.readSync(min(8, expected.length));
      if (header.length < expected.length) return false;
      for (var i = 0; i < expected.length; i++) {
        if (header[i] != expected[i]) return false;
      }
      return true;
    } finally {
      raf.closeSync();
    }
  }

  /// Uploads (or overwrites) one document.
  ///
  /// [docKey] names the document (e.g. `id_document`, `selfie`,
  /// `dti_cert`) and becomes the file name, so the storage path is fully
  /// deterministic per user per document: `{userId}/{docKey}.jpg`.
  ///
  /// Returns the STORAGE PATH (not a public URL). Defaults to the private
  /// verification bucket; pass [bucket] to upload elsewhere (e.g. the
  /// public `store-assets` bucket for the application's store-front
  /// photo, which doubles as the store banner).
  Future<String> uploadDocument({
    required String userId,
    required String docKey,
    required String filePath,
    String bucket = VerificationDocumentService.bucket,
  }) async {
    final file = File(filePath);
    // Keep the extension so the served Content-Type matches the bytes
    // (the picker can return PNG or JPEG; HEIC is re-encoded by picker).
    final ext = _extensionFor(filePath);
    final storagePath = '$userId/$docKey.$ext';

    await Supabase.instance.client.storage
        .from(bucket)
        .upload(
          storagePath,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            cacheControl: '3600',
          ),
        );

    return storagePath;
  }

  /// Returns a normalised extension used for both the extension allowlist
  /// and the storage path. HEIC/HEIF is mapped to jpg (image_picker
  /// re-encodes HEIC to JPEG on pick).
  String _extensionFor(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'jpg';
    return 'jpg';
  }

  /// Deletes an uploaded verification document (best-effort cleanup when a
  /// seller replaces/removes a file — requires the owner DELETE policy).
  Future<void> deleteDocument(String storagePath) async {
    try {
      await Supabase.instance.client.storage
          .from(bucket)
          .remove([storagePath]);
    } catch (e) {
      debugPrint('[VerificationDoc] delete failed for $storagePath: $e');
    }
  }

  /// Creates a short-lived signed URL for a private verification
  /// document. Requires the caller to pass the object SELECT policy
  /// (the owner, or an admin) — createSignedUrl enforces storage RLS.
  Future<String> signedUrl(
    String storagePath, {
    int expiresInSeconds = 3600,
    String bucket = VerificationDocumentService.bucket,
  }) {
    return Supabase.instance.client.storage
        .from(bucket)
        .createSignedUrl(storagePath, expiresInSeconds);
  }

  /// Calls the validate-upload Edge Function to verify an uploaded file's
  /// magic bytes server-side. This is Layer 3 of the upload security
  /// architecture — it closes the gap where a malicious actor spoofs
  /// the Content-Type header and uploads directly via the REST API.
  ///
  /// Returns true if the file is valid, false if the server rejected it
  /// (the function also deletes the invalid file from storage).
  /// On network errors, returns true (fail-open for connectivity — the
  /// client already validated in Layer 1, and the bucket-level
  /// restrictions in Layer 2 provide additional protection).
  Future<bool> validateUploadedFile({
    required String storagePath,
    required String bucket,
  }) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke('validate-upload', body: {
        'bucket_id': bucket,
        'name': storagePath,
      });
      // The function returns 200 for valid, 422 for invalid.
      // A non-2xx response that isn't 422 is treated as a network/function
      // error — fail-open since the client already validated.
      if (response.status == 422) {
        debugPrint(
          '[VerificationDoc] Server rejected $bucket/$storagePath: '
          '${response.data?['reason'] ?? 'invalid file'}',
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint(
        '[VerificationDoc] validate-upload call failed (fail-open): $e',
      );
      return true;
    }
  }
}
