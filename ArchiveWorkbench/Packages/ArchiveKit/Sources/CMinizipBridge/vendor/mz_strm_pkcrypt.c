/* mz_strm_pkcrypt.c -- Stream for traditional PKWARE encryption
   part of the minizip-ng project

   Copyright (C) Nathan Moinvaziri
      https://github.com/zlib-ng/minizip-ng

   This program is distributed under the terms of the same license as zlib.
   See the accompanying LICENSE file for the full text of the license.
*/

#include "mz.h"
#include "mz_crypt.h"
#include "mz_strm.h"
#include "mz_strm_pkcrypt.h"

/***************************************************************************/

static mz_stream_vtbl mz_stream_pkcrypt_vtbl = {
    mz_stream_pkcrypt_open,
    mz_stream_pkcrypt_is_open,
    mz_stream_pkcrypt_read,
    mz_stream_pkcrypt_write,
    mz_stream_pkcrypt_tell,
    mz_stream_pkcrypt_seek,
    mz_stream_pkcrypt_close,
    mz_stream_pkcrypt_error,
    mz_stream_pkcrypt_create,
    mz_stream_pkcrypt_delete,
    mz_stream_pkcrypt_get_prop_int64,
    mz_stream_pkcrypt_set_prop_int64
};

/***************************************************************************/

typedef struct mz_stream_pkcrypt_s {
    mz_stream stream;
    uint32_t keys[3];
    const char *password;
    uint8_t verify1;
    uint8_t verify2;
    uint16_t version_needed;
    int64_t total_in;
    int64_t max_total_in;
    int64_t total_out;
    uint8_t initialized;
} mz_stream_pkcrypt;

/***************************************************************************/

#define PKCRYPT_HEADER_SIZE (12)

static uint8_t mz_stream_pkcrypt_decode_byte(mz_stream_pkcrypt *pkcrypt) {
    uint16_t temp = (uint16_t)(pkcrypt->keys[2] | 2);
    return (uint8_t)((temp * (temp ^ 1)) >> 8);
}

static void mz_stream_pkcrypt_update_keys(mz_stream_pkcrypt *pkcrypt, uint8_t c) {
    pkcrypt->keys[0] = mz_crypt_crc32_update(pkcrypt->keys[0], &c, 1);
    pkcrypt->keys[1] += pkcrypt->keys[0] & 0xff;
    pkcrypt->keys[1] = pkcrypt->keys[1] * 134775813L + 1;
    c = (uint8_t)(pkcrypt->keys[1] >> 24);
    pkcrypt->keys[2] = mz_crypt_crc32_update(pkcrypt->keys[2], &c, 1);
}

static void mz_stream_pkcrypt_init_keys(mz_stream_pkcrypt *pkcrypt) {
    const char *password = pkcrypt->password;

    pkcrypt->keys[0] = 305419896L;
    pkcrypt->keys[1] = 591751049L;
    pkcrypt->keys[2] = 878082192L;

    if (password) {
        while (*password) {
            mz_stream_pkcrypt_update_keys(pkcrypt, (uint8_t)*password);
            password += 1;
        }
    }
}

/***************************************************************************/

int32_t mz_stream_pkcrypt_open(void *stream, const char *filename, int32_t mode) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    uint8_t header[PKCRYPT_HEADER_SIZE];
    int32_t bytes_read = 0;
    int32_t i = 0;

    MZ_UNUSED(filename);

    pkcrypt->total_in = 0;
    pkcrypt->total_out = 0;
    pkcrypt->initialized = 0;

    mz_stream_pkcrypt_init_keys(pkcrypt);

    if (mode & MZ_OPEN_MODE_WRITE) {
        /* Generate random encryption header */
        if (mz_crypt_rand(header, PKCRYPT_HEADER_SIZE) != MZ_OK)
            return MZ_CRYPT_ERROR;

        /* Set the last byte of the header to the verification byte */
        header[PKCRYPT_HEADER_SIZE - 1] = pkcrypt->verify1;

        /* Encrypt the header */
        for (i = 0; i < PKCRYPT_HEADER_SIZE; i += 1) {
            uint8_t t = header[i];
            header[i] ^= mz_stream_pkcrypt_decode_byte(pkcrypt);
            mz_stream_pkcrypt_update_keys(pkcrypt, t);
        }

        if (mz_stream_write(pkcrypt->stream.base, header, PKCRYPT_HEADER_SIZE) != PKCRYPT_HEADER_SIZE)
            return MZ_WRITE_ERROR;

        pkcrypt->total_out += PKCRYPT_HEADER_SIZE;
    } else if (mode & MZ_OPEN_MODE_READ) {
        /* Read and decrypt the encryption header */
        bytes_read = mz_stream_read(pkcrypt->stream.base, header, PKCRYPT_HEADER_SIZE);
        if (bytes_read != PKCRYPT_HEADER_SIZE)
            return MZ_CRYPT_ERROR;

        for (i = 0; i < PKCRYPT_HEADER_SIZE; i += 1) {
            uint8_t c = header[i];
            header[i] ^= mz_stream_pkcrypt_decode_byte(pkcrypt);
            mz_stream_pkcrypt_update_keys(pkcrypt, header[i]);
            header[i] = c; /* restore for potential re-read */
        }

        /* Verify the last header byte */
        /* For version >= 2.0, verify against high byte of CRC; otherwise high byte of mod time */
        if (header[PKCRYPT_HEADER_SIZE - 1] != pkcrypt->verify1) {
            /* Wrong password - but we continue and let CRC check catch it */
            /* Some implementations use verify2 for older versions */
            if (pkcrypt->version_needed < 20 && header[PKCRYPT_HEADER_SIZE - 1] != pkcrypt->verify2)
                return MZ_PASSWORD_ERROR;
        }

        pkcrypt->total_in += PKCRYPT_HEADER_SIZE;
    }

    pkcrypt->initialized = 1;
    return MZ_OK;
}

int32_t mz_stream_pkcrypt_is_open(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    if (!pkcrypt->initialized)
        return MZ_OPEN_ERROR;
    return MZ_OK;
}

int32_t mz_stream_pkcrypt_read(void *stream, void *buf, int32_t size) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    uint8_t *buf_ptr = (uint8_t *)buf;
    int32_t bytes_read = 0;
    int32_t i = 0;

    if (!pkcrypt->initialized)
        return MZ_OPEN_ERROR;

    bytes_read = mz_stream_read(pkcrypt->stream.base, buf, size);
    if (bytes_read < 0)
        return bytes_read;

    for (i = 0; i < bytes_read; i += 1) {
        uint8_t decoded = buf_ptr[i] ^ mz_stream_pkcrypt_decode_byte(pkcrypt);
        mz_stream_pkcrypt_update_keys(pkcrypt, decoded);
        buf_ptr[i] = decoded;
    }

    pkcrypt->total_in += bytes_read;
    return bytes_read;
}

int32_t mz_stream_pkcrypt_write(void *stream, const void *buf, int32_t size) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    const uint8_t *buf_ptr = (const uint8_t *)buf;
    uint8_t *encrypted = NULL;
    int32_t bytes_written = 0;
    int32_t i = 0;

    if (!pkcrypt->initialized)
        return MZ_OPEN_ERROR;

    if (size == 0)
        return 0;

    encrypted = (uint8_t *)malloc((size_t)size);
    if (!encrypted)
        return MZ_MEM_ERROR;

    for (i = 0; i < size; i += 1) {
        encrypted[i] = buf_ptr[i] ^ mz_stream_pkcrypt_decode_byte(pkcrypt);
        mz_stream_pkcrypt_update_keys(pkcrypt, buf_ptr[i]);
    }

    bytes_written = mz_stream_write(pkcrypt->stream.base, encrypted, size);
    free(encrypted);

    if (bytes_written < 0)
        return bytes_written;

    pkcrypt->total_out += bytes_written;
    return bytes_written;
}

int64_t mz_stream_pkcrypt_tell(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    return mz_stream_tell(pkcrypt->stream.base);
}

int32_t mz_stream_pkcrypt_seek(void *stream, int64_t offset, int32_t origin) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    return mz_stream_seek(pkcrypt->stream.base, offset, origin);
}

int32_t mz_stream_pkcrypt_close(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    pkcrypt->initialized = 0;
    return MZ_OK;
}

int32_t mz_stream_pkcrypt_error(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    return mz_stream_error(pkcrypt->stream.base);
}

void mz_stream_pkcrypt_set_password(void *stream, const char *password) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    pkcrypt->password = password;
}

void mz_stream_pkcrypt_set_verify(void *stream, uint8_t verify1, uint8_t verify2, uint16_t version_needed) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    pkcrypt->verify1 = verify1;
    pkcrypt->verify2 = verify2;
    pkcrypt->version_needed = version_needed;
}

int32_t mz_stream_pkcrypt_get_prop_int64(void *stream, int32_t prop, int64_t *value) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    switch (prop) {
    case MZ_STREAM_PROP_TOTAL_IN:
        *value = pkcrypt->total_in;
        break;
    case MZ_STREAM_PROP_TOTAL_OUT:
        *value = pkcrypt->total_out;
        break;
    case MZ_STREAM_PROP_HEADER_SIZE:
        *value = PKCRYPT_HEADER_SIZE;
        break;
    case MZ_STREAM_PROP_FOOTER_SIZE:
        *value = 0;
        break;
    default:
        return MZ_EXIST_ERROR;
    }
    return MZ_OK;
}

int32_t mz_stream_pkcrypt_set_prop_int64(void *stream, int32_t prop, int64_t value) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    switch (prop) {
    case MZ_STREAM_PROP_TOTAL_IN_MAX:
        pkcrypt->max_total_in = value;
        break;
    default:
        return MZ_EXIST_ERROR;
    }
    return MZ_OK;
}

void *mz_stream_pkcrypt_create(void) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)calloc(1, sizeof(mz_stream_pkcrypt));
    if (pkcrypt)
        pkcrypt->stream.vtbl = &mz_stream_pkcrypt_vtbl;
    return pkcrypt;
}

void mz_stream_pkcrypt_delete(void **stream) {
    mz_stream_pkcrypt *pkcrypt = NULL;
    if (!stream)
        return;
    pkcrypt = (mz_stream_pkcrypt *)*stream;
    if (pkcrypt) {
        memset(pkcrypt, 0, sizeof(mz_stream_pkcrypt));
        free(pkcrypt);
    }
    *stream = NULL;
}

void *mz_stream_pkcrypt_get_interface(void) {
    return (void *)&mz_stream_pkcrypt_vtbl;
}
