/*********************************************************************
 * Filename:   aes.h
 * Author:     Brad Conte (brad AT bradconte.com)
 * Copyright:
 * Disclaimer: This code is presented "as is" without any guarantees.
 * Details:    Defines the API for the corresponding AES implementation.
 *********************************************************************/

#ifndef SELF_DNS_AES_AES_H
#define SELF_DNS_AES_AES_H

/*************************** HEADER FILES ***************************/

#include <stddef.h>
#include <string>

namespace self_dns {

/****************************** MACROS ******************************/
#define AES_BLOCK_SIZE 16  // AES operates on 16 bytes at a time

// CRYPT CONFIG
#define MAX_LEN (2 * 1024 * 1024)
#define AES_ENCRYPT 0
#define AES_DECRYPT 1
#define AES_KEY_SIZE 128

/**************************** DATA TYPES ****************************/
typedef unsigned char BYTE;  // 8-bit byte
typedef unsigned int WORD;  // 32-bit word, change to "long" for 16-bit machines

/*********************** FUNCTION DECLARATIONS **********************/
///////////////////
// AES
///////////////////
// Key setup must be done before any AES en/de-cryption functions can be used.
void AesKeySetup(const BYTE *key,  // The key, must be 128, 192, or 256 bits
                 WORD *w,          // Output key schedule to be used later
                 int keysize);     // Bit length of the key, 128, 192, or 256

void AesEncrypt(const BYTE *in,   // 16 bytes of plaintext
                BYTE *out,        // 16 bytes of ciphertext
                const WORD *key,  // From the key setup
                int keysize);     // Bit length of the key, 128, 192, or 256

void AesDecrypt(const BYTE *in,   // 16 bytes of ciphertext
                BYTE *out,        // 16 bytes of plaintext
                const WORD *key,  // From the key setup
                int keysize);     // Bit length of the key, 128, 192, or 256

///////////////////
// AES - CBC
///////////////////
int AesEncryptCbc(
    const unsigned char *in,   // Plaintext
    size_t in_len,             // Must be a multiple of AES_BLOCK_SIZE
    unsigned char *out,        // Ciphertext, same length as plaintext
    const unsigned int *key,   // From the key setup
    int keysize,               // Bit length of the key, 128, 192, or 256
    const unsigned char *iv);  // IV, must be AES_BLOCK_SIZE bytes long

int AesDecryptCbc(const unsigned char *in, size_t in_len, unsigned char *out,
                  const unsigned int *key, int keysize,
                  const unsigned char *iv);

// Only output the CBC-MAC of the input.
int AesEncryptCbcMac(const BYTE *in,   // plaintext
                     size_t in_len,    // Must be a multiple of AES_BLOCK_SIZE
                     BYTE *out,        // Output MAC
                     const WORD *key,  // From the key setup
                     int keysize,      // Bit length of key, 128, 192, or 256
                     const BYTE *iv);  // IV, must be AES_BLOCK_SIZE bytes long

///////////////////
// AES - CTR
///////////////////
void IncrementIv(
    BYTE *iv,           // Must be a multiple of AES_BLOCK_SIZE
    int counter_size);  // Bytes of the IV used for counting (low end)

void AesEncryptCtr(const BYTE *in,   // Plaintext
                   size_t in_len,    // Any byte length
                   BYTE *out,        // Ciphertext, same length as plaintext
                   const WORD *key,  // From the key setup
                   int keysize,      // Bit length of the key, 128, 192, or 256
                   const BYTE *iv);  // IV, must be AES_BLOCK_SIZE bytes long

void AesDecryptCtr(const BYTE *in,   // Ciphertext
                   size_t in_len,    // Any byte length
                   BYTE *out,        // Plaintext, same length as ciphertext
                   const WORD *key,  // From the key setup
                   int keysize,      // Bit length of the key, 128, 192, or 256
                   const BYTE *iv);  // IV, must be AES_BLOCK_SIZE bytes long

///////////////////
// AES - CCM
///////////////////
// Returns True if the input parameters do not violate any constraint.
int AesEncryptCcm(
    const BYTE *payload,  // IN  - Plaintext.
    WORD payload_len,     // IN  - Plaintext length.
    const BYTE *assoc,  // IN  - Associated Data included in authentication, but
    // not encryption.
    uint16_t assoc_len,  // IN  - Associated Data length in bytes.
    const BYTE *nonce,   // IN  - The Nonce to be used for encryption.
    uint16_t nonce_len,  // IN  - Nonce length in bytes.
    BYTE *
        out,  // OUT - Ciphertext, a concatination of the plaintext and the MAC.
    WORD
        *out_len,  // OUT - The length of the ciphertext, always plaintext_len +
    // mac_len.
    WORD mac_len,  // IN  - The desired length of the MAC, must be 4, 6, 8, 10,
    // 12, 14, or 16.
    const BYTE *key_str,  // IN  - The AES key for encryption.
    int keysize);  // IN  - The length of the key in bits. Valid values are 128,
// 192, 256.

// Returns True if the input parameters do not violate any constraint.
// Use mac_auth to ensure decryption/validation was preformed correctly.
// If authentication does not succeed, the plaintext is zeroed out. To overwride
// this, call with mac_auth = NULL. The proper proceedure is to decrypt with
// authentication enabled (mac_auth != NULL) and make a second call to that
// ignores authentication explicitly if the first call failes.
int AesDecryptCcm(
    const BYTE
        ciphertext[],  // IN  - Ciphertext, the concatination of encrypted
    // plaintext and MAC.
    WORD ciphertext_len,  // IN  - Ciphertext length in bytes.
    const BYTE
        assoc[],  // IN  - The Associated Data, required for authentication.
    uint16_t assoc_len,  // IN  - Associated Data length in bytes.
    const BYTE nonce[],  // IN  - The Nonce to use for decryption, same one as
    // for encryption.
    uint16_t nonce_len,  // IN  - Nonce length in bytes.
    BYTE
        plaintext[],  // OUT - The plaintext that was decrypted. Will need to be
    // large enough to hold ciphertext_len - mac_len.
    WORD *plaintext_len,  // OUT - Length in bytes of the output plaintext,
    // always ciphertext_len - mac_len .
    WORD mac_len,   // IN  - The length of the MAC that was calculated.
    int *mac_auth,  // OUT - TRUE if authentication succeeded, FALSE if it did
    // not. NULL pointer will ignore the authentication.
    const BYTE key[],  // IN  - The AES key for decryption.
    int keysize);  // IN  - The length of the key in BITS. Valid values are 128,
// 192, 256.

int AesGetOutLen(int len, int mode);

int AesCryptWithKey(const unsigned char *src, unsigned int srclen,
                    unsigned char *dst, unsigned int mode,
                    const unsigned char *AES_KEY, const unsigned char *AES_IV);

}  // namespace self_dns

#endif  // SELF_DNS_AES_AES_H
