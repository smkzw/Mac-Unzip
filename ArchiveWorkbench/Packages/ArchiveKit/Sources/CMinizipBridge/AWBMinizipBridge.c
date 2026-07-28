#include "AWBMinizipBridge.h"
#include "mz.h"
#include "mz_os.h"
#include "mz_strm.h"
#include "mz_zip.h"
#include "mz_zip_rw.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

struct awb_mz_reader {
    void *handle;
    mz_zip_file *current;
    int64_t *index;       /* array of central directory offsets per entry ordinal */
    uint64_t index_count; /* number of entries in the index */
    uint8_t index_built;  /* 1 once the index has been fully populated */
};

struct awb_mz_writer {
    void *handle;
    uint8_t entry_open;
    uint16_t compress_method;
    int32_t encrypt_method;
};

static int32_t awb_mz_map_result(int32_t result) {
    switch (result) {
        case MZ_OK:
            return AWB_MZ_OK;
        case MZ_END_OF_LIST:
            return AWB_MZ_END;
        case MZ_PARAM_ERROR:
            return AWB_MZ_INVALID_ARGUMENT;
        case MZ_OPEN_ERROR:
            return AWB_MZ_OPEN_ERROR;
        case MZ_FORMAT_ERROR:
        case MZ_DATA_ERROR:
            return AWB_MZ_FORMAT_ERROR;
        case MZ_EXIST_ERROR:
            return AWB_MZ_OPEN_ERROR;
        case MZ_PASSWORD_ERROR:
        case MZ_CRYPT_ERROR:
            return AWB_MZ_PASSWORD_ERROR;
        case MZ_CRC_ERROR:
            return AWB_MZ_CRC_ERROR;
        case MZ_SUPPORT_ERROR:
            return AWB_MZ_UNSUPPORTED_ERROR;
        case MZ_MEM_ERROR:
            return AWB_MZ_MEMORY_ERROR;
        default:
            return AWB_MZ_IO_ERROR;
    }
}

/* Build the entry index by scanning the central directory once.
 * Each entry's CD offset is recorded so that awb_mz_reader_goto can
 * seek in O(1) via mz_zip_goto_entry instead of an O(n) linear scan. */
static int32_t awb_mz_reader_build_index(awb_mz_reader *reader) {
    if (reader->index_built) {
        return AWB_MZ_OK;
    }

    void *zip_handle = NULL;
    int32_t result = mz_zip_reader_get_zip_handle(reader->handle, &zip_handle);
    if (result != MZ_OK || zip_handle == NULL) {
        return awb_mz_map_result(result);
    }

    uint64_t total_entries = 0;
    result = mz_zip_get_number_entry(zip_handle, &total_entries);
    if (result != MZ_OK) {
        return awb_mz_map_result(result);
    }
    if (total_entries == 0) {
        reader->index = NULL;
        reader->index_count = 0;
        reader->index_built = 1;
        return AWB_MZ_OK;
    }
    if (total_entries > INT32_MAX) {
        return AWB_MZ_INVALID_ARGUMENT;
    }

    int64_t *offsets = (int64_t *)malloc((size_t)total_entries * sizeof(int64_t));
    if (offsets == NULL) {
        return AWB_MZ_MEMORY_ERROR;
    }

    /* Walk all entries recording their CD positions */
    result = mz_zip_goto_first_entry(zip_handle);
    if (result != MZ_OK) {
        free(offsets);
        return awb_mz_map_result(result);
    }

    uint64_t idx = 0;
    while (result == MZ_OK && idx < total_entries) {
        int64_t entry_offset = mz_zip_get_entry(zip_handle);
        if (entry_offset < 0) {
            free(offsets);
            return AWB_MZ_FORMAT_ERROR;
        }
        offsets[idx] = entry_offset;
        idx += 1;
        result = mz_zip_goto_next_entry(zip_handle);
    }
    /* MZ_END_OF_LIST is expected at the end */
    if (result != MZ_OK && result != MZ_END_OF_LIST) {
        free(offsets);
        return awb_mz_map_result(result);
    }

    reader->index = offsets;
    reader->index_count = idx;
    reader->index_built = 1;
    return AWB_MZ_OK;
}

static int32_t awb_mz_reader_fill_info(awb_mz_reader *reader, awb_mz_entry_info *out_info) {
    if (reader == NULL || reader->handle == NULL || out_info == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }

    mz_zip_file *file_info = NULL;
    int32_t result = mz_zip_reader_entry_get_info(reader->handle, &file_info);
    if (result != MZ_OK) {
        return awb_mz_map_result(result);
    }
    if (file_info == NULL || file_info->filename == NULL ||
        file_info->compressed_size < 0 || file_info->uncompressed_size < 0) {
        return AWB_MZ_FORMAT_ERROR;
    }

    void *zip_handle = NULL;
    result = mz_zip_reader_get_zip_handle(reader->handle, &zip_handle);
    if (result != MZ_OK || zip_handle == NULL) {
        return awb_mz_map_result(result);
    }

    reader->current = file_info;
    out_info->name_bytes = (const uint8_t *)file_info->filename;
    out_info->name_size = file_info->filename_size;
    out_info->compressed_size = (uint64_t)file_info->compressed_size;
    out_info->uncompressed_size = (uint64_t)file_info->uncompressed_size;
    out_info->modified_unix_time = (int64_t)file_info->modified_date;
    out_info->is_directory = (uint8_t)(mz_zip_reader_entry_is_dir(reader->handle) == MZ_OK);
    out_info->is_symlink = (uint8_t)(mz_zip_entry_is_symlink(zip_handle) == MZ_OK);
    out_info->is_encrypted = (uint8_t)((file_info->flag & MZ_ZIP_FLAG_ENCRYPTED) != 0);
    out_info->uses_utf8_file_name = (uint8_t)((file_info->flag & MZ_ZIP_FLAG_UTF8) != 0);
    return AWB_MZ_OK;
}

const char *awb_mz_version(void) {
    return MZ_VERSION;
}

int32_t awb_mz_reader_open(const char *path, awb_mz_reader **out_reader) {
    if (path == NULL || out_reader == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    *out_reader = NULL;

    awb_mz_reader *reader = (awb_mz_reader *)calloc(1, sizeof(awb_mz_reader));
    if (reader == NULL) {
        return AWB_MZ_MEMORY_ERROR;
    }
    reader->handle = mz_zip_reader_create();
    if (reader->handle == NULL) {
        free(reader);
        return AWB_MZ_MEMORY_ERROR;
    }

    int32_t result = mz_zip_reader_open_file(reader->handle, path);
    if (result != MZ_OK) {
        mz_zip_reader_delete(&reader->handle);
        free(reader);
        return awb_mz_map_result(result);
    }

    *out_reader = reader;
    return AWB_MZ_OK;
}

int32_t awb_mz_reader_open_with_password(const char *path, const char *password, awb_mz_reader **out_reader) {
    if (path == NULL || out_reader == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    *out_reader = NULL;

    awb_mz_reader *reader = (awb_mz_reader *)calloc(1, sizeof(awb_mz_reader));
    if (reader == NULL) {
        return AWB_MZ_MEMORY_ERROR;
    }
    reader->handle = mz_zip_reader_create();
    if (reader->handle == NULL) {
        free(reader);
        return AWB_MZ_MEMORY_ERROR;
    }

    if (password != NULL && password[0] != '\0') {
        mz_zip_reader_set_password(reader->handle, password);
    }

    int32_t result = mz_zip_reader_open_file(reader->handle, path);
    if (result != MZ_OK) {
        mz_zip_reader_delete(&reader->handle);
        free(reader);
        return awb_mz_map_result(result);
    }

    *out_reader = reader;
    return AWB_MZ_OK;
}

int32_t awb_mz_reader_first(awb_mz_reader *reader, awb_mz_entry_info *out_info) {
    if (reader == NULL || reader->handle == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    int32_t result = mz_zip_reader_goto_first_entry(reader->handle);
    if (result != MZ_OK) {
        return awb_mz_map_result(result);
    }
    return awb_mz_reader_fill_info(reader, out_info);
}

int32_t awb_mz_reader_next(awb_mz_reader *reader, awb_mz_entry_info *out_info) {
    if (reader == NULL || reader->handle == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    int32_t result = mz_zip_reader_goto_next_entry(reader->handle);
    if (result != MZ_OK) {
        return awb_mz_map_result(result);
    }
    return awb_mz_reader_fill_info(reader, out_info);
}

int32_t awb_mz_reader_goto(awb_mz_reader *reader, uint64_t ordinal, awb_mz_entry_info *out_info) {
    if (reader == NULL || reader->handle == NULL || out_info == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }

    /* Build the index on first use (one-time O(n) scan of the central directory) */
    int32_t result = awb_mz_reader_build_index(reader);
    if (result != AWB_MZ_OK) {
        return result;
    }

    if (ordinal >= reader->index_count) {
        return AWB_MZ_END;
    }

    /* O(1) seek via mz_zip_reader_goto_cd_pos which properly updates
     * the reader's internal file_info cache (unlike raw mz_zip_goto_entry). */
    result = mz_zip_reader_goto_cd_pos(reader->handle, reader->index[ordinal]);
    if (result != MZ_OK) {
        return awb_mz_map_result(result);
    }

    return awb_mz_reader_fill_info(reader, out_info);
}

int32_t awb_mz_reader_open_current(awb_mz_reader *reader) {
    if (reader == NULL || reader->handle == NULL || reader->current == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    return awb_mz_map_result(mz_zip_reader_entry_open(reader->handle));
}

int32_t awb_mz_reader_read_current(awb_mz_reader *reader, uint8_t *buffer, int32_t capacity) {
    if (reader == NULL || reader->handle == NULL || buffer == NULL || capacity <= 0) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    int32_t result = mz_zip_reader_entry_read(reader->handle, buffer, capacity);
    if (result >= 0) {
        return result;
    }
    return awb_mz_map_result(result);
}

int32_t awb_mz_reader_close_current(awb_mz_reader *reader) {
    if (reader == NULL || reader->handle == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    int32_t result = mz_zip_reader_entry_close(reader->handle);
    reader->current = NULL;
    return awb_mz_map_result(result);
}

void awb_mz_reader_close(awb_mz_reader **reader) {
    if (reader == NULL || *reader == NULL) {
        return;
    }
    if ((*reader)->handle != NULL) {
        mz_zip_reader_close((*reader)->handle);
        mz_zip_reader_delete(&(*reader)->handle);
    }
    free((*reader)->index);
    (*reader)->index = NULL;
    free(*reader);
    *reader = NULL;
}

int32_t awb_mz_writer_open(const char *path, awb_mz_writer **out_writer) {
    if (path == NULL || out_writer == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    *out_writer = NULL;

    awb_mz_writer *writer = (awb_mz_writer *)calloc(1, sizeof(awb_mz_writer));
    if (writer == NULL) {
        return AWB_MZ_MEMORY_ERROR;
    }
    writer->handle = mz_zip_writer_create();
    if (writer->handle == NULL) {
        free(writer);
        return AWB_MZ_MEMORY_ERROR;
    }
    mz_zip_writer_set_compress_method(writer->handle, MZ_COMPRESS_METHOD_DEFLATE);
    mz_zip_writer_set_compress_level(writer->handle, MZ_COMPRESS_LEVEL_NORMAL);
    writer->compress_method = MZ_COMPRESS_METHOD_DEFLATE;
    mz_zip_writer_set_follow_links(writer->handle, 0);
    mz_zip_writer_set_store_links(writer->handle, 0);

    int32_t result = mz_zip_writer_open_file(writer->handle, path, 0, 0);
    if (result != MZ_OK) {
        mz_zip_writer_delete(&writer->handle);
        free(writer);
        return awb_mz_map_result(result);
    }

    *out_writer = writer;
    return AWB_MZ_OK;
}

int32_t awb_mz_writer_open_with_password(const char *path, const char *password, int32_t encrypt_method, awb_mz_writer **out_writer) {
    if (path == NULL || out_writer == NULL || password == NULL || password[0] == '\0') {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    if (encrypt_method != AWB_MZ_ENCRYPT_AES256 && encrypt_method != AWB_MZ_ENCRYPT_ZIPCRYPTO) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    *out_writer = NULL;

    awb_mz_writer *writer = (awb_mz_writer *)calloc(1, sizeof(awb_mz_writer));
    if (writer == NULL) {
        return AWB_MZ_MEMORY_ERROR;
    }
    writer->handle = mz_zip_writer_create();
    if (writer->handle == NULL) {
        free(writer);
        return AWB_MZ_MEMORY_ERROR;
    }
    mz_zip_writer_set_compress_method(writer->handle, MZ_COMPRESS_METHOD_DEFLATE);
    mz_zip_writer_set_compress_level(writer->handle, MZ_COMPRESS_LEVEL_NORMAL);
    mz_zip_writer_set_follow_links(writer->handle, 0);
    mz_zip_writer_set_store_links(writer->handle, 0);

    /* Set encryption password and method */
    mz_zip_writer_set_password(writer->handle, password);
    if (encrypt_method == AWB_MZ_ENCRYPT_AES256) {
        mz_zip_writer_set_aes(writer->handle, 1);
    } else {
        /* ZipCrypto: no AES */
        mz_zip_writer_set_aes(writer->handle, 0);
    }

    int32_t result = mz_zip_writer_open_file(writer->handle, path, 0, 0);
    if (result != MZ_OK) {
        mz_zip_writer_delete(&writer->handle);
        free(writer);
        return awb_mz_map_result(result);
    }

    *out_writer = writer;
    writer->encrypt_method = encrypt_method;
    return AWB_MZ_OK;
}

int32_t awb_mz_writer_open_configured(const char *path, int32_t compress_level, const char *password, int32_t encrypt_method, awb_mz_writer **out_writer) {
    if (path == NULL || out_writer == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    if (password != NULL && password[0] != '\0') {
        if (encrypt_method != AWB_MZ_ENCRYPT_AES256 && encrypt_method != AWB_MZ_ENCRYPT_ZIPCRYPTO) {
            return AWB_MZ_INVALID_ARGUMENT;
        }
    }
    *out_writer = NULL;

    awb_mz_writer *writer = (awb_mz_writer *)calloc(1, sizeof(awb_mz_writer));
    if (writer == NULL) {
        return AWB_MZ_MEMORY_ERROR;
    }
    writer->handle = mz_zip_writer_create();
    if (writer->handle == NULL) {
        free(writer);
        return AWB_MZ_MEMORY_ERROR;
    }

    if (compress_level == AWB_MZ_LEVEL_STORE) {
        mz_zip_writer_set_compress_method(writer->handle, MZ_COMPRESS_METHOD_STORE);
        mz_zip_writer_set_compress_level(writer->handle, MZ_COMPRESS_LEVEL_NORMAL);
        writer->compress_method = MZ_COMPRESS_METHOD_STORE;
    } else {
        mz_zip_writer_set_compress_method(writer->handle, MZ_COMPRESS_METHOD_DEFLATE);
        mz_zip_writer_set_compress_level(writer->handle, compress_level);
        writer->compress_method = MZ_COMPRESS_METHOD_DEFLATE;
    }
    mz_zip_writer_set_follow_links(writer->handle, 0);
    mz_zip_writer_set_store_links(writer->handle, 0);

    if (password != NULL && password[0] != '\0') {
        mz_zip_writer_set_password(writer->handle, password);
        if (encrypt_method == AWB_MZ_ENCRYPT_AES256) {
            mz_zip_writer_set_aes(writer->handle, 1);
        } else {
            mz_zip_writer_set_aes(writer->handle, 0);
        }
    }

    int32_t result = mz_zip_writer_open_file(writer->handle, path, 0, 0);
    if (result != MZ_OK) {
        mz_zip_writer_delete(&writer->handle);
        free(writer);
        return awb_mz_map_result(result);
    }

    *out_writer = writer;
    writer->encrypt_method = (password != NULL && password[0] != '\0') ? encrypt_method : AWB_MZ_ENCRYPT_NONE;
    return AWB_MZ_OK;
}

int32_t awb_mz_writer_add_file(
    awb_mz_writer *writer,
    const char *source_path,
    const char *archive_path
) {
    if (writer == NULL || writer->handle == NULL || source_path == NULL || archive_path == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    return awb_mz_map_result(mz_zip_writer_add_file(writer->handle, source_path, archive_path));
}

int32_t awb_mz_writer_open_entry(
    awb_mz_writer *writer,
    const char *archive_path,
    uint64_t uncompressed_size,
    int64_t modified_unix_time
) {
    if (writer == NULL || writer->handle == NULL || writer->entry_open ||
        archive_path == NULL || archive_path[0] == '\0' || uncompressed_size > INT64_MAX) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    size_t path_length = strlen(archive_path);
    if (path_length > UINT16_MAX) {
        return AWB_MZ_INVALID_ARGUMENT;
    }

    mz_zip_file file_info;
    memset(&file_info, 0, sizeof(file_info));
    file_info.version_madeby = MZ_VERSION_MADEBY;
    file_info.flag = MZ_ZIP_FLAG_UTF8;
    file_info.compression_method = writer->compress_method;
    file_info.modified_date = (time_t)modified_unix_time;
    file_info.uncompressed_size = (int64_t)uncompressed_size;
    file_info.filename = archive_path;
    file_info.filename_size = (uint16_t)path_length;
    if (writer->encrypt_method == AWB_MZ_ENCRYPT_AES256) {
        file_info.aes_version = 2;
        file_info.aes_strength = 3;
    }

    int32_t result = mz_zip_writer_entry_open(writer->handle, &file_info);
    if (result == MZ_OK) {
        writer->entry_open = 1;
    }
    return awb_mz_map_result(result);
}

int32_t awb_mz_writer_open_entry_raw(
    awb_mz_writer *writer,
    const uint8_t *name_bytes,
    uint16_t name_size,
    uint8_t uses_utf8_name,
    uint64_t uncompressed_size,
    int64_t modified_unix_time
) {
    if (writer == NULL || writer->handle == NULL || writer->entry_open ||
        name_bytes == NULL || name_size == 0 || uncompressed_size > INT64_MAX) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    for (uint16_t index = 0; index < name_size; index += 1) {
        if (name_bytes[index] == 0) {
            return AWB_MZ_INVALID_ARGUMENT;
        }
    }

    char *name_copy = (char *)malloc((size_t)name_size + 1);
    if (name_copy == NULL) {
        return AWB_MZ_MEMORY_ERROR;
    }
    memcpy(name_copy, name_bytes, name_size);
    name_copy[name_size] = '\0';

    mz_zip_file file_info;
    memset(&file_info, 0, sizeof(file_info));
    file_info.version_madeby = MZ_VERSION_MADEBY;
    file_info.flag = uses_utf8_name ? MZ_ZIP_FLAG_UTF8 : 0;
    file_info.compression_method = writer->compress_method;
    file_info.modified_date = (time_t)modified_unix_time;
    file_info.uncompressed_size = (int64_t)uncompressed_size;
    file_info.filename = name_copy;
    file_info.filename_size = name_size;
    if (writer->encrypt_method == AWB_MZ_ENCRYPT_AES256) {
        file_info.aes_version = 2;
        file_info.aes_strength = 3;
    }

    int32_t result = mz_zip_writer_entry_open(writer->handle, &file_info);
    free(name_copy);
    if (result == MZ_OK) {
        writer->entry_open = 1;
    }
    return awb_mz_map_result(result);
}

int32_t awb_mz_writer_write_entry(
    awb_mz_writer *writer,
    const uint8_t *buffer,
    int32_t length
) {
    if (writer == NULL || writer->handle == NULL || !writer->entry_open ||
        length < 0 || (length > 0 && buffer == NULL)) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    int32_t written = mz_zip_writer_entry_write(writer->handle, buffer, length);
    if (written < 0) {
        return awb_mz_map_result(written);
    }
    return written;
}

int32_t awb_mz_writer_close_entry(awb_mz_writer *writer) {
    if (writer == NULL || writer->handle == NULL || !writer->entry_open) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    int32_t result = mz_zip_writer_entry_close(writer->handle);
    writer->entry_open = 0;
    return awb_mz_map_result(result);
}

int32_t awb_mz_writer_close(awb_mz_writer **writer) {
    if (writer == NULL || *writer == NULL) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    int32_t result = MZ_OK;
    if ((*writer)->handle != NULL) {
        if ((*writer)->entry_open) {
            result = mz_zip_writer_entry_close((*writer)->handle);
            (*writer)->entry_open = 0;
        }
        int32_t close_result = mz_zip_writer_close((*writer)->handle);
        if (result == MZ_OK) {
            result = close_result;
        }
        mz_zip_writer_delete(&(*writer)->handle);
    }
    free(*writer);
    *writer = NULL;
    return awb_mz_map_result(result);
}

int32_t awb_mz_writer_open_split(const char *path, uint64_t disk_size, awb_mz_writer **out_writer) {
    if (path == NULL || out_writer == NULL || disk_size == 0) {
        return AWB_MZ_INVALID_ARGUMENT;
    }
    *out_writer = NULL;

    awb_mz_writer *writer = (awb_mz_writer *)calloc(1, sizeof(awb_mz_writer));
    if (writer == NULL) {
        return AWB_MZ_MEMORY_ERROR;
    }
    writer->handle = mz_zip_writer_create();
    if (writer->handle == NULL) {
        free(writer);
        return AWB_MZ_MEMORY_ERROR;
    }
    mz_zip_writer_set_compress_method(writer->handle, MZ_COMPRESS_METHOD_DEFLATE);
    mz_zip_writer_set_compress_level(writer->handle, MZ_COMPRESS_LEVEL_NORMAL);
    mz_zip_writer_set_follow_links(writer->handle, 0);
    mz_zip_writer_set_store_links(writer->handle, 0);

    /* disk_size is passed to mz_zip_writer_open_file which enables splitting:
     * minizip-ng will create .z01, .z02, ... .zip volumes automatically. */
    int32_t result = mz_zip_writer_open_file(writer->handle, path, (int64_t)disk_size, 0);
    if (result != MZ_OK) {
        mz_zip_writer_delete(&writer->handle);
        free(writer);
        return awb_mz_map_result(result);
    }

    *out_writer = writer;
    return AWB_MZ_OK;
}

int32_t awb_mz_reader_open_split(const char *path, awb_mz_reader **out_reader) {
    /* minizip-ng transparently resolves split volumes (.z01, .z02, ...)
     * when opening the final .zip segment via mz_zip_reader_open_file.
     * If a preceding volume is missing the open call fails with MZ_OPEN_ERROR. */
    return awb_mz_reader_open(path, out_reader);
}
