/**
 * Cryptographic utilities for AI Health Vault backend.
 * Uses Web Crypto API (available in Cloudflare Workers runtime).
 *
 * IMPORTANT: All functions here are pure — no side effects, no PHI handling.
 */

/**
 * Computes SHA-256 hash of the given string and returns lowercase hex.
 * Used to derive anonymous_id from original_transaction_id.
 */
export async function sha256Hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Returns current billing month string in 'YYYY-MM' format (UTC).
 * D1 uses this as partition key for monthly usage reset.
 */
export function currentBillingMonth(): string {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

/**
 * Decodes a JWS (JSON Web Signature) token and returns its payload.
 * Does NOT verify the signature — call verifyAppleJWS for full verification.
 *
 * Apple's StoreKit 2 tokens are compact JWS: header.payload.signature
 */
export function decodeJWSPayload<T>(jws: string): T {
  const parts = jws.split('.');
  if (parts.length !== 3) {
    throw new Error('Invalid JWS format: expected 3 parts separated by dots');
  }
  // Base64url decode the payload (second part)
  const payloadBase64 = parts[1];
  if (!payloadBase64) {
    throw new Error('Invalid JWS: empty payload segment');
  }
  const padded = payloadBase64.replace(/-/g, '+').replace(/_/g, '/');
  const decoded = atob(padded);
  return JSON.parse(decoded) as T;
}

/**
 * Verifies an Apple JWS token signature chain.
 *
 * Apple signs StoreKit 2 tokens using ES256 (ECDSA with P-256 + SHA-256).
 * The x5c header contains the certificate chain:
 *   [0] = leaf cert (signing key)
 *   [1] = intermediate CA
 *   [2] = Apple Root CA G3 (must match our stored root)
 *
 * @param jws       The compact JWS string from Apple
 * @param rootCertPem  Apple Root CA G3 PEM (stored as Cloudflare Secret)
 * @returns Verified payload, or throws if signature is invalid
 */
export async function verifyAppleJWS<T>(jws: string, rootCertPem: string): Promise<T> {
  const parts = jws.split('.');
  if (parts.length !== 3) {
    throw new Error('Invalid JWS: expected 3 parts');
  }

  const [headerB64, payloadB64, signatureB64] = parts as [string, string, string];

  // Decode header to get x5c chain
  const header = JSON.parse(atob(headerB64.replace(/-/g, '+').replace(/_/g, '/'))) as {
    alg: string;
    x5c: string[];
  };

  if (header.alg !== 'ES256') {
    throw new Error(`Unsupported algorithm: ${header.alg}, expected ES256`);
  }

  if (!header.x5c || header.x5c.length < 3) {
    throw new Error('JWS header missing x5c certificate chain (need ≥3 certs)');
  }

  // Import the leaf certificate's public key (x5c[0] is DER-encoded, base64)
  const leafCertDer = base64ToArrayBuffer(header.x5c[0] as string);
  const leafKey = await importECKeyFromCertDER(leafCertDer);

  // Reconstruct the signed data (header.payload as ASCII bytes)
  const signedData = new TextEncoder().encode(`${headerB64}.${payloadB64}`);

  // Decode the DER-encoded signature from base64url
  const signatureBytes = base64UrlToArrayBuffer(signatureB64);

  // Verify signature
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    leafKey,
    signatureBytes,
    signedData
  );

  if (!valid) {
    throw new Error('JWS signature verification failed');
  }

  // Verify root cert matches Apple Root CA G3
  const rootCertDer = pemToArrayBuffer(rootCertPem);
  const providedRootDer = base64ToArrayBuffer(header.x5c[2] as string);
  if (!arrayBuffersEqual(rootCertDer, providedRootDer)) {
    throw new Error('JWS root certificate does not match expected Apple Root CA G3');
  }

  // Return decoded payload
  return JSON.parse(atob(payloadB64.replace(/-/g, '+').replace(/_/g, '/'))) as T;
}

// ─── Private helpers ────────────────────────────────────────────────────────

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function base64UrlToArrayBuffer(base64url: string): ArrayBuffer {
  return base64ToArrayBuffer(base64url.replace(/-/g, '+').replace(/_/g, '/'));
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN CERTIFICATE-----/g, '')
    .replace(/-----END CERTIFICATE-----/g, '')
    .replace(/\s+/g, '');
  return base64ToArrayBuffer(b64);
}

function arrayBuffersEqual(a: ArrayBuffer, b: ArrayBuffer): boolean {
  if (a.byteLength !== b.byteLength) return false;
  const va = new Uint8Array(a);
  const vb = new Uint8Array(b);
  for (let i = 0; i < va.length; i++) {
    if (va[i] !== vb[i]) return false;
  }
  return true;
}

/**
 * Extracts the EC public key from a DER-encoded X.509 certificate.
 * Cloudflare Workers Web Crypto does not have native cert parsing,
 * so we locate the SubjectPublicKeyInfo (SPKI) by searching for the
 * EC P-256 OID sequence within the DER bytes.
 */
async function importECKeyFromCertDER(certDer: ArrayBuffer): Promise<CryptoKey> {
  // P-256 OID in DER: 06 08 2A 86 48 CE 3D 03 01 07
  const p256OidDer = new Uint8Array([0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]);
  const certBytes = new Uint8Array(certDer);

  // Find the SPKI structure by locating the P-256 OID
  let spkiStart = -1;
  outer: for (let i = 0; i < certBytes.length - p256OidDer.length - 20; i++) {
    let match = true;
    for (let j = 0; j < p256OidDer.length; j++) {
      if (certBytes[i + j] !== p256OidDer[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      // Walk back to find the SEQUENCE tag (0x30) that starts the SPKI block
      for (let k = i - 1; k >= Math.max(0, i - 16); k--) {
        if (certBytes[k] === 0x30) {
          spkiStart = k;
          break outer;
        }
      }
    }
  }

  if (spkiStart === -1) {
    throw new Error('Could not locate SPKI in certificate DER');
  }

  // Extract SPKI length from DER TLV at spkiStart
  let spkiLength: number;
  let offset = spkiStart + 1; // skip 0x30 tag
  if ((certBytes[offset] ?? 0) & 0x80) {
    const lenBytes = (certBytes[offset] ?? 0) & 0x7f;
    spkiLength = 0;
    for (let i = 0; i < lenBytes; i++) {
      spkiLength = (spkiLength << 8) | (certBytes[offset + 1 + i] ?? 0);
    }
    offset += 1 + lenBytes;
  } else {
    spkiLength = certBytes[offset] ?? 0;
    offset += 1;
  }

  const spkiDer = certBytes.slice(spkiStart, spkiStart + 2 + (offset - spkiStart - 1) + spkiLength);

  return crypto.subtle.importKey(
    'spki',
    spkiDer.buffer,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify']
  );
}
