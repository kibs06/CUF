import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  /// rationale). Returns the local file path, or null if the user
  /// cancelled.
  Future<String?> pickDocumentImage({required ImageSource source}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    return picked?.path;
  }

  /// Uploads (or overwrites) one verification document.
  ///
  /// [docKey] names the document (e.g. `id_document`, `selfie`,
  /// `dti_cert`) and becomes the file name, so the storage path is fully
  /// deterministic per user per document: `{userId}/{docKey}.jpg`.
  ///
  /// Returns the STORAGE PATH (not a public URL — the bucket is private).
  /// Callers persist this path in `profiles` / `seller_business_docs` and
  /// view the file later via [signedUrl].
  Future<String> uploadDocument({
    required String userId,
    required String docKey,
    required String filePath,
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
  Future<String> signedUrl(String storagePath, {int expiresInSeconds = 3600}) {
    return Supabase.instance.client.storage
        .from(bucket)
        .createSignedUrl(storagePath, expiresInSeconds);
  }
}
