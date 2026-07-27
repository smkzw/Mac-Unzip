/* mz_strm_wzaes.c -- Stream for WinZIP AES encryption
   part of the minizip-ng project

   Copyright (C) Nathan Moinvaziri
      https://github.com/zlib-ng/minizip-ng

   This program is distributed under the terms of the same license as zlib.
   See the accompanying LICENSE file for the full text of the license.
*/

#include "mz.h"
#include "mz_crypt.h"
#include "mz_strm.h"
#include "mz_strm_wzaes.h"

/***************************************************************************/

#define MZ_AES_KEY_LENGTH(S)   (8 * (S & 3) + 8)
#define MZ_AES_KEY_LENGTH_MAX  (32)
#define MZ_AES_SALT_LENGTH(S)  (4 * (S & 3) + 4)
#define MZ_AES_SALT_LENGTH_MAX (16)
#define MZ_AES_PW_LENGTH_MAX   (128)
#define MZ_AES_AUTHCODE_SIZE   (10)

/***************************************************************************/

static mz_stream_vtbl mz_stream_wzaes_vtbl = {
    mz_stream_wzaes_open,
    mz_stream_wzaes_is_open,
    mz_stream_wzaes_read,
    mz_stream_wzaes_write,
    mz_stream_wzaes_tell,
    mz_stream_wzaes_seek,
    mz_stream_wzaes_close,
    mz_stream_wzaes_error,
    mz_stream_wzaes_create,
    mz_stream_wzaes_delete,
    mz_stream_wzaes_get_prop_int64,
    mz_stream_wzaes_set_prop_int64
};

/***************************************************************************/

typedef struct mz_stream_wzaes_s {
    mz_stream stream;
    int64_t total_in;
    int64_t max_total_in;
    int64_t total_out;
    int32_t mode;
    uint8_t strength;
    const char *password;
    void *aes;
    void *hmac;
    uint8_t initialized;
    uint8_t header_verified;
    /* CTR mode state */
    uint8_t nonce[MZ_AES_BLOCK_SIZE];   /* counter block */
    uint8_t keystream[MZ_AES_BLOCK_SIZE]; /* current keystream block */
    int32_t keystream_pos;               /* position within current keystream block */
} mz_stream_wzaes;

/***************************************************************************/

/* Increment the counter block as a little-endian 128-bit integer */
static void mz_stream_wzaes_ctr_increment(uint8_t *nonce) {
    int32_t i;
    for (i = 0; i < MZ_AES_BLOCK_SIZE; i += 1) {
        nonce[i] += 1;
        if (nonce[i] != 0)
            break;
    }
}

/* Generate the next keystream block: encrypt the counter, then increment */
static void mz_stream_wzaes_ctr_next_block(mz_stream_wzaes *wzaes) {
    /* Increment counter before encryption (first block uses counter=1) */
    mz_stream_wzaes_ctr_increment(wzaes->nonce);

    /* Copy nonce to keystream buffer and encrypt in-place with AES-ECB */
    memcpy(wzaes->keystream, wzaes->nonce, MZ_AES_BLOCK_SIZE);
    mz_crypt_aes_encrypt(wzaes->aes, NULL, 0, wzaes->keystream, MZ_AES_BLOCK_SIZE);

    wzaes->keystream_pos = 0;
}

/* XOR data with keystream (CTR mode encryption/decryption are identical) */
static void mz_stream_wzaes_ctr_xor(mz_stream_wzaes *wzaes, uint8_t *buf, int32_t size) {
    int32_t i;
    for (i = 0; i < size; i += 1) {
        if (wzaes->keystream_pos >= MZ_AES_BLOCK_SIZE)
            mz_stream_wzaes_ctr_next_block(wzaes);
        buf[i] ^= wzaes->keystream[wzaes->keystream_pos];
        wzaes->keystream_pos += 1;
    }
}

/***************************************************************************/

int32_t mz_stream_wzaes_open(void *stream, const char *filename, int32_t mode) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    uint16_t salt_length = 0;
    uint16_t key_length = 0;
    uint16_t pw_length = 0;
    uint8_t kbuf[2 * MZ_AES_KEY_LENGTH_MAX + MZ_AES_AUTHCODE_SIZE];
    uint8_t verify[2];
    uint8_t verify_expected[2];
    uint8_t salt[MZ_AES_SALT_LENGTH_MAX];
    int32_t bytes_read = 0;

    MZ_UNUSED(filename);

    wzaes->total_in = 0;
    wzaes->total_out = 0;
    wzaes->initialized = 0;
    wzaes->header_verified = 0;
    wzaes->mode = mode;
    memset(wzaes->nonce, 0, sizeof(wzaes->nonce));
    memset(wzaes->keystream, 0, sizeof(wzaes->keystream));
    wzaes->keystream_pos = MZ_AES_BLOCK_SIZE; /* force generation on first use */

    if (!wzaes->password)
        return MZ_PARAM_ERROR;

    pw_length = (uint16_t)strlen(wzaes->password);
    if (pw_length > MZ_AES_PW_LENGTH_MAX)
        return MZ_PARAM_ERROR;

    salt_length = MZ_AES_SALT_LENGTH(wzaes->strength);
    key_length = MZ_AES_KEY_LENGTH(wzaes->strength);

    if (mode & MZ_OPEN_MODE_WRITE) {
        if (mz_crypt_rand(salt, salt_length) != MZ_OK)
            return MZ_CRYPT_ERROR;
    } else if (mode & MZ_OPEN_MODE_READ) {
        bytes_read = mz_stream_read(wzaes->stream.base, salt, salt_length);
        if (bytes_read != salt_length)
            return MZ_CRYPT_ERROR;
    }

    /* Derive key material: enc_key | auth_key | verify_value */
    if (mz_crypt_pbkdf2((const uint8_t *)wzaes->password, pw_length, salt, salt_length,
                        1000, kbuf, 2 * key_length + 2) != MZ_OK)
        return MZ_CRYPT_ERROR;

    /* Create AES context - always use encrypt key for CTR mode */
    wzaes->aes = mz_crypt_aes_create();
    if (!wzaes->aes)
        return MZ_MEM_ERROR;

    if (mz_crypt_aes_set_encrypt_key(wzaes->aes, kbuf, key_length, NULL, 0) != MZ_OK) {
        mz_crypt_aes_delete(&wzaes->aes);
        return MZ_CRYPT_ERROR;
    }

    /* Create HMAC context with auth key (second half of derived material) */
    wzaes->hmac = mz_crypt_hmac_create();
    if (!wzaes->hmac) {
        mz_crypt_aes_delete(&wzaes->aes);
        return MZ_MEM_ERROR;
    }

    mz_crypt_hmac_set_algorithm(wzaes->hmac, MZ_HASH_SHA1);
    if (mz_crypt_hmac_init(wzaes->hmac, kbuf + key_length, key_length) != MZ_OK) {
        mz_crypt_hmac_delete(&wzaes->hmac);
        mz_crypt_aes_delete(&wzaes->aes);
        return MZ_CRYPT_ERROR;
    }

    if (mode & MZ_OPEN_MODE_WRITE) {
        /* Write salt + password verification value */
        verify[0] = kbuf[2 * key_length];
        verify[1] = kbuf[2 * key_length + 1];

        if (mz_stream_write(wzaes->stream.base, salt, salt_length) != salt_length) {
            mz_crypt_hmac_delete(&wzaes->hmac);
            mz_crypt_aes_delete(&wzaes->aes);
            return MZ_CRYPT_ERROR;
        }
        if (mz_stream_write(wzaes->stream.base, verify, 2) != 2) {
            mz_crypt_hmac_delete(&wzaes->hmac);
            mz_crypt_aes_delete(&wzaes->aes);
            return MZ_CRYPT_ERROR;
        }
        wzaes->total_out += salt_length + 2;
    } else {
        /* Read and verify password verification value */
        bytes_read = mz_stream_read(wzaes->stream.base, verify_expected, 2);
        if (bytes_read != 2) {
            mz_crypt_hmac_delete(&wzaes->hmac);
            mz_crypt_aes_delete(&wzaes->aes);
            return MZ_CRYPT_ERROR;
        }

        verify[0] = kbuf[2 * key_length];
        verify[1] = kbuf[2 * key_length + 1];

        if (verify[0] != verify_expected[0] || verify[1] != verify_expected[1]) {
            mz_crypt_hmac_delete(&wzaes->hmac);
            mz_crypt_aes_delete(&wzaes->aes);
            return MZ_PASSWORD_ERROR;
        }

        wzaes->total_in += salt_length + 2;
        wzaes->header_verified = 1;
    }

    /* Zeroize key material */
    memset(kbuf, 0, sizeof(kbuf));
    memset(salt, 0, sizeof(salt));
    memset(verify, 0, sizeof(verify));
    memset(verify_expected, 0, sizeof(verify_expected));

    wzaes->initialized = 1;
    return MZ_OK;
}

int32_t mz_stream_wzaes_is_open(void *stream) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    if (!wzaes->initialized)
        return MZ_OPEN_ERROR;
    return MZ_OK;
}

int32_t mz_stream_wzaes_read(void *stream, void *buf, int32_t size) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    int32_t bytes_read = 0;

    if (!wzaes->initialized)
        return MZ_OPEN_ERROR;

    bytes_read = mz_stream_read(wzaes->stream.base, buf, size);
    if (bytes_read <= 0)
        return bytes_read;

    /* Update HMAC with ciphertext before decryption */
    mz_crypt_hmac_update(wzaes->hmac, (const uint8_t *)buf, bytes_read);

    /* Decrypt using CTR mode (XOR with keystream) */
    mz_stream_wzaes_ctr_xor(wzaes, (uint8_t *)buf, bytes_read);

    wzaes->total_in += bytes_read;
    return bytes_read;
}

int32_t mz_stream_wzaes_write(void *stream, const void *buf, int32_t size) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    int32_t bytes_written = 0;
    uint8_t *encrypted = NULL;

    if (!wzaes->initialized)
        return MZ_OPEN_ERROR;

    if (size == 0)
        return 0;

    encrypted = (uint8_t *)malloc((size_t)size);
    if (!encrypted)
        return MZ_MEM_ERROR;

    memcpy(encrypted, buf, (size_t)size);

    /* Encrypt using CTR mode (XOR with keystream) */
    mz_stream_wzaes_ctr_xor(wzaes, encrypted, size);

    /* Update HMAC with ciphertext after encryption */
    mz_crypt_hmac_update(wzaes->hmac, encrypted, size);

    bytes_written = mz_stream_write(wzaes->stream.base, encrypted, size);
    free(encrypted);

    if (bytes_written < 0)
        return bytes_written;

    wzaes->total_out += bytes_written;
    return bytes_written;
}

int64_t mz_stream_wzaes_tell(void *stream) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    return mz_stream_tell(wzaes->stream.base);
}

int32_t mz_stream_wzaes_seek(void *stream, int64_t offset, int32_t origin) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    return mz_stream_seek(wzaes->stream.base, offset, origin);
}

int32_t mz_stream_wzaes_close(void *stream) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    uint8_t authcode[MZ_HASH_SHA1_SIZE];
    uint8_t authcode_trunc[MZ_AES_AUTHCODE_SIZE];

    if (!wzaes->initialized)
        return MZ_OK;

    /* Finalize HMAC and write auth code */
    mz_crypt_hmac_end(wzaes->hmac, authcode, sizeof(authcode));
    memcpy(authcode_trunc, authcode, MZ_AES_AUTHCODE_SIZE);

    if (wzaes->mode & MZ_OPEN_MODE_WRITE) {
        mz_stream_write(wzaes->stream.base, authcode_trunc, MZ_AES_AUTHCODE_SIZE);
        wzaes->total_out += MZ_AES_AUTHCODE_SIZE;
    }

    memset(authcode, 0, sizeof(authcode));
    memset(authcode_trunc, 0, sizeof(authcode_trunc));

    if (wzaes->aes)
        mz_crypt_aes_delete(&wzaes->aes);
    if (wzaes->hmac)
        mz_crypt_hmac_delete(&wzaes->hmac);

    wzaes->initialized = 0;
    return MZ_OK;
}

int32_t mz_stream_wzaes_error(void *stream) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    return mz_stream_error(wzaes->stream.base);
}

void mz_stream_wzaes_set_password(void *stream, const char *password) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    wzaes->password = password;
}

void mz_stream_wzaes_set_strength(void *stream, uint8_t strength) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    wzaes->strength = strength;
}

int32_t mz_stream_wzaes_get_prop_int64(void *stream, int32_t prop, int64_t *value) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    switch (prop) {
    case MZ_STREAM_PROP_TOTAL_IN:
        *value = wzaes->total_in;
        break;
    case MZ_STREAM_PROP_TOTAL_OUT:
        *value = wzaes->total_out;
        break;
    case MZ_STREAM_PROP_HEADER_SIZE:
        *value = MZ_AES_SALT_LENGTH(wzaes->strength) + 2;
        break;
    case MZ_STREAM_PROP_FOOTER_SIZE:
        *value = MZ_AES_AUTHCODE_SIZE;
        break;
    default:
        return MZ_EXIST_ERROR;
    }
    return MZ_OK;
}

int32_t mz_stream_wzaes_set_prop_int64(void *stream, int32_t prop, int64_t value) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)stream;
    switch (prop) {
    case MZ_STREAM_PROP_TOTAL_IN_MAX:
        wzaes->max_total_in = value;
        break;
    default:
        return MZ_EXIST_ERROR;
    }
    return MZ_OK;
}

void *mz_stream_wzaes_create(void) {
    mz_stream_wzaes *wzaes = (mz_stream_wzaes *)calloc(1, sizeof(mz_stream_wzaes));
    if (wzaes) {
        wzaes->stream.vtbl = &mz_stream_wzaes_vtbl;
        wzaes->strength = MZ_AES_STRENGTH_256;
    }
    return wzaes;
}

void mz_stream_wzaes_delete(void **stream) {
    mz_stream_wzaes *wzaes = NULL;
    if (!stream)
        return;
    wzaes = (mz_stream_wzaes *)*stream;
    if (wzaes) {
        if (wzaes->aes)
            mz_crypt_aes_delete(&wzaes->aes);
        if (wzaes->hmac)
            mz_crypt_hmac_delete(&wzaes->hmac);
        free(wzaes);
    }
    *stream = NULL;
}

void *mz_stream_wzaes_get_interface(void) {
    return (void *)&mz_stream_wzaes_vtbl;
}
