/* mz_crypt_apple.c -- Crypto/hash functions for Apple platforms
   part of the minizip-ng project

   Copyright (C) Nathan Moinvaziri
     https://github.com/zlib-ng/minizip-ng

   This program is distributed under the terms of the same license as zlib.
   See the accompanying LICENSE file for the full text of the license.
*/

#include "mz.h"
#include "mz_crypt.h"

#include <CommonCrypto/CommonCrypto.h>
#include <CommonCrypto/CommonHMAC.h>
#include <CommonCrypto/CommonRandom.h>
#include <Security/Security.h>

/***************************************************************************/

int32_t mz_crypt_rand(uint8_t *buf, int32_t size) {
    if (CCRandomGenerateBytes(buf, (size_t)size) != kCCSuccess)
        return MZ_CRYPT_ERROR;
    return MZ_OK;
}

/***************************************************************************/

typedef struct mz_crypt_sha_s {
    CC_SHA1_CTX ctx1;
    CC_SHA256_CTX ctx256;
    CC_SHA512_CTX ctx512;
    uint16_t algorithm;
    int32_t initialized;
} mz_crypt_sha;

/***************************************************************************/

void mz_crypt_sha_reset(void *handle) {
    mz_crypt_sha *sha = (mz_crypt_sha *)handle;
    sha->initialized = 0;
}

int32_t mz_crypt_sha_begin(void *handle) {
    mz_crypt_sha *sha = (mz_crypt_sha *)handle;

    if (!sha)
        return MZ_PARAM_ERROR;

    switch (sha->algorithm) {
    case MZ_HASH_SHA1:
        if (CC_SHA1_Init(&sha->ctx1) != 1)
            return MZ_CRYPT_ERROR;
        break;
    case MZ_HASH_SHA256:
        if (CC_SHA256_Init(&sha->ctx256) != 1)
            return MZ_CRYPT_ERROR;
        break;
    case MZ_HASH_SHA512:
        if (CC_SHA512_Init(&sha->ctx512) != 1)
            return MZ_CRYPT_ERROR;
        break;
    default:
        return MZ_PARAM_ERROR;
    }

    sha->initialized = 1;
    return MZ_OK;
}

int32_t mz_crypt_sha_update(void *handle, const void *buf, int32_t size) {
    mz_crypt_sha *sha = (mz_crypt_sha *)handle;

    if (!sha || !buf || !sha->initialized)
        return MZ_PARAM_ERROR;

    switch (sha->algorithm) {
    case MZ_HASH_SHA1:
        if (CC_SHA1_Update(&sha->ctx1, buf, (CC_LONG)size) != 1)
            return MZ_CRYPT_ERROR;
        break;
    case MZ_HASH_SHA256:
        if (CC_SHA256_Update(&sha->ctx256, buf, (CC_LONG)size) != 1)
            return MZ_CRYPT_ERROR;
        break;
    case MZ_HASH_SHA512:
        if (CC_SHA512_Update(&sha->ctx512, buf, (CC_LONG)size) != 1)
            return MZ_CRYPT_ERROR;
        break;
    default:
        return MZ_PARAM_ERROR;
    }

    return MZ_OK;
}

int32_t mz_crypt_sha_end(void *handle, uint8_t *digest, int32_t digest_size) {
    mz_crypt_sha *sha = (mz_crypt_sha *)handle;

    if (!sha || !digest || !sha->initialized)
        return MZ_PARAM_ERROR;

    switch (sha->algorithm) {
    case MZ_HASH_SHA1:
        if (digest_size < MZ_HASH_SHA1_SIZE)
            return MZ_PARAM_ERROR;
        if (CC_SHA1_Final(digest, &sha->ctx1) != 1)
            return MZ_CRYPT_ERROR;
        break;
    case MZ_HASH_SHA256:
        if (digest_size < MZ_HASH_SHA256_SIZE)
            return MZ_PARAM_ERROR;
        if (CC_SHA256_Final(digest, &sha->ctx256) != 1)
            return MZ_CRYPT_ERROR;
        break;
    case MZ_HASH_SHA512:
        if (digest_size < MZ_HASH_SHA512_SIZE)
            return MZ_PARAM_ERROR;
        if (CC_SHA512_Final(digest, &sha->ctx512) != 1)
            return MZ_CRYPT_ERROR;
        break;
    default:
        return MZ_PARAM_ERROR;
    }

    sha->initialized = 0;
    return MZ_OK;
}

int32_t mz_crypt_sha_set_algorithm(void *handle, uint16_t algorithm) {
    mz_crypt_sha *sha = (mz_crypt_sha *)handle;

    if (!sha)
        return MZ_PARAM_ERROR;

    switch (algorithm) {
    case MZ_HASH_SHA1:
    case MZ_HASH_SHA256:
    case MZ_HASH_SHA512:
        sha->algorithm = algorithm;
        return MZ_OK;
    default:
        return MZ_PARAM_ERROR;
    }
}

void *mz_crypt_sha_create(void) {
    mz_crypt_sha *sha = (mz_crypt_sha *)calloc(1, sizeof(mz_crypt_sha));
    if (sha)
        sha->algorithm = MZ_HASH_SHA256;
    return sha;
}

void mz_crypt_sha_delete(void **handle) {
    mz_crypt_sha *sha = NULL;
    if (!handle)
        return;
    sha = (mz_crypt_sha *)*handle;
    if (sha) {
        memset(sha, 0, sizeof(mz_crypt_sha));
        free(sha);
    }
    *handle = NULL;
}

/***************************************************************************/

typedef struct mz_crypt_aes_s {
    CCCryptorRef cryptor;
    int32_t mode;
    int32_t initialized;
} mz_crypt_aes;

/***************************************************************************/

void mz_crypt_aes_reset(void *handle) {
    mz_crypt_aes *aes = (mz_crypt_aes *)handle;
    if (aes->cryptor) {
        CCCryptorRelease(aes->cryptor);
        aes->cryptor = NULL;
    }
    aes->initialized = 0;
}

int32_t mz_crypt_aes_encrypt(void *handle, const void *aad, int32_t aad_size, uint8_t *buf, int32_t size) {
    mz_crypt_aes *aes = (mz_crypt_aes *)handle;
    size_t data_moved = 0;
    CCCryptorStatus status;

    MZ_UNUSED(aad);
    MZ_UNUSED(aad_size);

    if (!aes || !buf || !aes->initialized)
        return MZ_PARAM_ERROR;

    status = CCCryptorUpdate(aes->cryptor, buf, (size_t)size, buf, (size_t)size, &data_moved);
    if (status != kCCSuccess)
        return MZ_CRYPT_ERROR;

    return (int32_t)data_moved;
}

int32_t mz_crypt_aes_encrypt_final(void *handle, uint8_t *buf, int32_t size, uint8_t *tag, int32_t tag_size) {
    mz_crypt_aes *aes = (mz_crypt_aes *)handle;
    size_t data_moved = 0;
    CCCryptorStatus status;

    MZ_UNUSED(tag);
    MZ_UNUSED(tag_size);

    if (!aes || !buf || !aes->initialized)
        return MZ_PARAM_ERROR;

    status = CCCryptorFinal(aes->cryptor, buf, (size_t)size, &data_moved);
    if (status != kCCSuccess)
        return MZ_CRYPT_ERROR;

    return (int32_t)data_moved;
}

int32_t mz_crypt_aes_decrypt(void *handle, const void *aad, int32_t aad_size, uint8_t *buf, int32_t size) {
    mz_crypt_aes *aes = (mz_crypt_aes *)handle;
    size_t data_moved = 0;
    CCCryptorStatus status;

    MZ_UNUSED(aad);
    MZ_UNUSED(aad_size);

    if (!aes || !buf || !aes->initialized)
        return MZ_PARAM_ERROR;

    status = CCCryptorUpdate(aes->cryptor, buf, (size_t)size, buf, (size_t)size, &data_moved);
    if (status != kCCSuccess)
        return MZ_CRYPT_ERROR;

    return (int32_t)data_moved;
}

int32_t mz_crypt_aes_decrypt_final(void *handle, uint8_t *buf, int32_t size, const uint8_t *tag, int32_t tag_size) {
    mz_crypt_aes *aes = (mz_crypt_aes *)handle;
    size_t data_moved = 0;
    CCCryptorStatus status;

    MZ_UNUSED(tag);
    MZ_UNUSED(tag_size);

    if (!aes || !buf || !aes->initialized)
        return MZ_PARAM_ERROR;

    status = CCCryptorFinal(aes->cryptor, buf, (size_t)size, &data_moved);
    if (status != kCCSuccess)
        return MZ_CRYPT_ERROR;

    return (int32_t)data_moved;
}

static int32_t mz_crypt_aes_set_key(void *handle, const void *key, int32_t key_length, const void *iv,
                                    int32_t iv_length, CCOperation op) {
    mz_crypt_aes *aes = (mz_crypt_aes *)handle;
    CCCryptorStatus status;

    MZ_UNUSED(iv);
    MZ_UNUSED(iv_length);

    if (!aes || !key || key_length == 0)
        return MZ_PARAM_ERROR;

    if (aes->cryptor) {
        CCCryptorRelease(aes->cryptor);
        aes->cryptor = NULL;
    }

    /* Use ECB mode - the wzaes stream implements CTR counter manually */
    status = CCCryptorCreateWithMode(op, kCCModeECB, kCCAlgorithmAES, ccNoPadding,
                                     NULL, key, (size_t)key_length, NULL, 0, 0, 0, &aes->cryptor);
    if (status != kCCSuccess)
        return MZ_CRYPT_ERROR;

    aes->initialized = 1;
    return MZ_OK;
}

int32_t mz_crypt_aes_set_encrypt_key(void *handle, const void *key, int32_t key_length, const void *iv,
                                     int32_t iv_length) {
    return mz_crypt_aes_set_key(handle, key, key_length, iv, iv_length, kCCEncrypt);
}

int32_t mz_crypt_aes_set_decrypt_key(void *handle, const void *key, int32_t key_length, const void *iv,
                                     int32_t iv_length) {
    return mz_crypt_aes_set_key(handle, key, key_length, iv, iv_length, kCCDecrypt);
}

void mz_crypt_aes_set_mode(void *handle, int32_t mode) {
    mz_crypt_aes *aes = (mz_crypt_aes *)handle;
    if (aes)
        aes->mode = mode;
}

void *mz_crypt_aes_create(void) {
    mz_crypt_aes *aes = (mz_crypt_aes *)calloc(1, sizeof(mz_crypt_aes));
    return aes;
}

void mz_crypt_aes_delete(void **handle) {
    mz_crypt_aes *aes = NULL;
    if (!handle)
        return;
    aes = (mz_crypt_aes *)*handle;
    if (aes) {
        mz_crypt_aes_reset(aes);
        free(aes);
    }
    *handle = NULL;
}

/***************************************************************************/

typedef struct mz_crypt_hmac_s {
    CCHmacContext ctx;
    uint16_t algorithm;
    int32_t initialized;
} mz_crypt_hmac;

/***************************************************************************/

void mz_crypt_hmac_reset(void *handle) {
    mz_crypt_hmac *hmac = (mz_crypt_hmac *)handle;
    hmac->initialized = 0;
}

int32_t mz_crypt_hmac_init(void *handle, const void *key, int32_t key_length) {
    mz_crypt_hmac *hmac = (mz_crypt_hmac *)handle;
    CCHmacAlgorithm algorithm;

    if (!hmac || !key)
        return MZ_PARAM_ERROR;

    switch (hmac->algorithm) {
    case MZ_HASH_SHA1:
        algorithm = kCCHmacAlgSHA1;
        break;
    case MZ_HASH_SHA256:
        algorithm = kCCHmacAlgSHA256;
        break;
    default:
        return MZ_PARAM_ERROR;
    }

    CCHmacInit(&hmac->ctx, algorithm, key, (size_t)key_length);
    hmac->initialized = 1;
    return MZ_OK;
}

int32_t mz_crypt_hmac_update(void *handle, const void *buf, int32_t size) {
    mz_crypt_hmac *hmac = (mz_crypt_hmac *)handle;

    if (!hmac || !buf || !hmac->initialized)
        return MZ_PARAM_ERROR;

    CCHmacUpdate(&hmac->ctx, buf, (size_t)size);
    return MZ_OK;
}

int32_t mz_crypt_hmac_end(void *handle, uint8_t *digest, int32_t digest_size) {
    mz_crypt_hmac *hmac = (mz_crypt_hmac *)handle;

    if (!hmac || !digest || !hmac->initialized)
        return MZ_PARAM_ERROR;

    switch (hmac->algorithm) {
    case MZ_HASH_SHA1:
        if (digest_size < MZ_HASH_SHA1_SIZE)
            return MZ_PARAM_ERROR;
        CCHmacFinal(&hmac->ctx, digest);
        break;
    case MZ_HASH_SHA256:
        if (digest_size < MZ_HASH_SHA256_SIZE)
            return MZ_PARAM_ERROR;
        CCHmacFinal(&hmac->ctx, digest);
        break;
    default:
        return MZ_PARAM_ERROR;
    }

    hmac->initialized = 0;
    return MZ_OK;
}

int32_t mz_crypt_hmac_copy(void *src_handle, void *target_handle) {
    mz_crypt_hmac *src = (mz_crypt_hmac *)src_handle;
    mz_crypt_hmac *target = (mz_crypt_hmac *)target_handle;

    if (!src || !target)
        return MZ_PARAM_ERROR;

    memcpy(&target->ctx, &src->ctx, sizeof(CCHmacContext));
    target->algorithm = src->algorithm;
    target->initialized = src->initialized;
    return MZ_OK;
}

void mz_crypt_hmac_set_algorithm(void *handle, uint16_t algorithm) {
    mz_crypt_hmac *hmac = (mz_crypt_hmac *)handle;
    if (hmac)
        hmac->algorithm = algorithm;
}

void *mz_crypt_hmac_create(void) {
    mz_crypt_hmac *hmac = (mz_crypt_hmac *)calloc(1, sizeof(mz_crypt_hmac));
    if (hmac)
        hmac->algorithm = MZ_HASH_SHA1;
    return hmac;
}

void mz_crypt_hmac_delete(void **handle) {
    mz_crypt_hmac *hmac = NULL;
    if (!handle)
        return;
    hmac = (mz_crypt_hmac *)*handle;
    if (hmac) {
        memset(hmac, 0, sizeof(mz_crypt_hmac));
        free(hmac);
    }
    *handle = NULL;
}
