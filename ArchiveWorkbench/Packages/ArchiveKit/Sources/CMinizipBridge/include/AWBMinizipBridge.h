#ifndef AWB_MINIZIP_BRIDGE_H
#define AWB_MINIZIP_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AWB_MZ_OK 0
#define AWB_MZ_END 1
#define AWB_MZ_INVALID_ARGUMENT -1
#define AWB_MZ_OPEN_ERROR -2
#define AWB_MZ_FORMAT_ERROR -3
#define AWB_MZ_PASSWORD_ERROR -4
#define AWB_MZ_CRC_ERROR -5
#define AWB_MZ_UNSUPPORTED_ERROR -6
#define AWB_MZ_IO_ERROR -7
#define AWB_MZ_MEMORY_ERROR -8

/* Encryption methods for writer */
#define AWB_MZ_ENCRYPT_NONE 0
#define AWB_MZ_ENCRYPT_AES256 1
#define AWB_MZ_ENCRYPT_ZIPCRYPTO 2

typedef struct awb_mz_reader awb_mz_reader;
typedef struct awb_mz_writer awb_mz_writer;

typedef struct {
    const uint8_t *name_bytes;
    uint16_t name_size;
    uint64_t compressed_size;
    uint64_t uncompressed_size;
    int64_t modified_unix_time;
    uint8_t is_directory;
    uint8_t is_symlink;
    uint8_t is_encrypted;
    uint8_t uses_utf8_file_name;
} awb_mz_entry_info;

const char *awb_mz_version(void);
int32_t awb_mz_reader_open(const char *path, awb_mz_reader **out_reader);
int32_t awb_mz_reader_open_with_password(const char *path, const char *password, awb_mz_reader **out_reader);
int32_t awb_mz_reader_first(awb_mz_reader *reader, awb_mz_entry_info *out_info);
int32_t awb_mz_reader_next(awb_mz_reader *reader, awb_mz_entry_info *out_info);
int32_t awb_mz_reader_goto(awb_mz_reader *reader, uint64_t ordinal, awb_mz_entry_info *out_info);
int32_t awb_mz_reader_open_current(awb_mz_reader *reader);
int32_t awb_mz_reader_read_current(awb_mz_reader *reader, uint8_t *buffer, int32_t capacity);
int32_t awb_mz_reader_close_current(awb_mz_reader *reader);
void awb_mz_reader_close(awb_mz_reader **reader);
int32_t awb_mz_writer_open(const char *path, awb_mz_writer **out_writer);
int32_t awb_mz_writer_open_with_password(const char *path, const char *password, int32_t encrypt_method, awb_mz_writer **out_writer);
int32_t awb_mz_writer_add_file(
    awb_mz_writer *writer,
    const char *source_path,
    const char *archive_path
);
int32_t awb_mz_writer_open_entry(
    awb_mz_writer *writer,
    const char *archive_path,
    uint64_t uncompressed_size,
    int64_t modified_unix_time
);
int32_t awb_mz_writer_open_entry_raw(
    awb_mz_writer *writer,
    const uint8_t *name_bytes,
    uint16_t name_size,
    uint8_t uses_utf8_name,
    uint64_t uncompressed_size,
    int64_t modified_unix_time
);
int32_t awb_mz_writer_write_entry(
    awb_mz_writer *writer,
    const uint8_t *buffer,
    int32_t length
);
int32_t awb_mz_writer_close_entry(awb_mz_writer *writer);
int32_t awb_mz_writer_close(awb_mz_writer **writer);

/* Split (multipart) writer: creates archive.z01, .z02, ..., archive.zip
 * disk_size is the maximum bytes per volume (e.g. 4*1024*1024 for 4 MB).
 * path must end in .zip; preceding volumes are named .z01, .z02, etc. */
int32_t awb_mz_writer_open_split(const char *path, uint64_t disk_size, awb_mz_writer **out_writer);

/* Reader: open a split archive set by pointing at the final .zip segment.
 * minizip-ng resolves preceding .z01/.z02/... volumes automatically.
 * Returns AWB_MZ_OPEN_ERROR when a required volume is missing. */
int32_t awb_mz_reader_open_split(const char *path, awb_mz_reader **out_reader);

#ifdef __cplusplus
}
#endif

#endif
