import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Fetch all seller information and verification documents.
 * Includes personal info, identity docs, business docs, and store details.
 * Used in the UserDetailModal "Documents" tab.
 */
export function useUserDocuments(userId) {
  return useQuery({
    queryKey: ['user-documents', userId],
    enabled: !!userId,
    queryFn: async () => {
      // Fetch ALL profile data (personal info + identity documents)
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single()

      if (profileError) throw profileError

      // Fetch business verification documents (if they exist)
      let businessDocs = null
      const { data: bizData, error: bizError } = await supabase
        .from('seller_business_docs')
        .select('*')
        .eq('profile_id', userId)
        .maybeSingle()

      if (!bizError && bizData) {
        businessDocs = bizData
      }

      // Generate signed URLs for private documents
      const generateSignedUrl = async (path, bucket = 'seller-verification-docs') => {
        if (!path) return null
        try {
          const { data, error } = await supabase.storage
            .from(bucket)
            .createSignedUrl(path, 3600) // 1 hour expiry
          if (error) throw error
          return data?.signedUrl ?? null
        } catch (err) {
          console.error('Failed to generate signed URL:', err)
          return null
        }
      }

      // Generate signed URLs for all documents
      const [
        idDocUrl,
        selfieUrl,
        barangayUrl,
        storeFrontUrl,
        dtiUrl,
        birUrl,
        permitUrl,
      ] = await Promise.all([
        generateSignedUrl(profile?.id_document_url),
        generateSignedUrl(profile?.selfie_url),
        generateSignedUrl(profile?.barangay_proof_url),
        generateSignedUrl(profile?.store_front_url, 'store-assets'), // Public bucket
        generateSignedUrl(businessDocs?.dti_cert_url),
        generateSignedUrl(businessDocs?.bir_cor_url),
        generateSignedUrl(businessDocs?.permit_url),
      ])

      // Generate signed URLs for product photos
      const productPhotoUrls = []
      if (profile?.product_photo_urls) {
        for (const path of profile.product_photo_urls) {
          if (path) {
            const url = await generateSignedUrl(path)
            productPhotoUrls.push(url)
          }
        }
      }

      return {
        // Personal information (from signup)
        personal: {
          fullName: profile?.full_name,
          email: profile?.email,
          phone: profile?.phone,
          birthday: profile?.birthday,
          gender: profile?.gender,
          createdAt: profile?.created_at,
        },
        // Identity documents
        identity: {
          idDocument: {
            url: idDocUrl,
            path: profile?.id_document_url,
            label: 'Government ID',
            type: profile?.id_type,
          },
          selfie: {
            url: selfieUrl,
            path: profile?.selfie_url,
            label: 'Selfie',
          },
          barangay: {
            url: barangayUrl,
            path: profile?.barangay_proof_url,
            label: 'Barangay Proof',
          },
          cufmaiMemberId: profile?.cufmai_member_id,
        },
        // Store information (from signup)
        store: {
          name: profile?.store_name,
          description: profile?.store_description,
          location: profile?.store_location,
          lat: profile?.store_lat,
          lng: profile?.store_lng,
          tags: profile?.store_tags || [],
          storefront: {
            url: storeFrontUrl,
            path: profile?.store_front_url,
            label: 'Store Front',
            bucket: 'store-assets',
          },
          products: productPhotoUrls.map((url, idx) => ({
            url,
            label: `Product ${idx + 1}`,
          })),
        },
        // Business documents (Tier 2)
        business: businessDocs ? {
          dti: {
            url: dtiUrl,
            path: businessDocs.dti_cert_url,
            label: 'DTI Certificate',
          },
          bir: {
            url: birUrl,
            path: businessDocs.bir_cor_url,
            label: 'BIR COR',
          },
          permit: {
            url: permitUrl,
            path: businessDocs.permit_url,
            label: "Mayor's/Barangay Permit",
          },
          status: businessDocs.verification_status,
          submittedAt: businessDocs.submitted_at,
          verifiedAt: businessDocs.verified_at,
        } : null,
        // Application status
        application: {
          status: profile?.seller_status,
          rejectionReason: profile?.rejection_reason,
        },
      }
    },
  })
}