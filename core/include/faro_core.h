#ifndef FARO_CORE_H
#define FARO_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Field IDs: 0 = name, 1 = tagline, 2 = status, 3 = version.
 * Strings are immutable, process-lifetime UTF-8. Never free or modify them.
 * Invalid IDs return NULL; invalid IDs/offsets return -1 for integer calls.
 * Lengths exclude the terminating NUL. */
const char *faro_metadata_field(int32_t id);
int32_t faro_metadata_length(int32_t id);
int32_t faro_metadata_byte(int32_t id, int32_t offset);

#ifdef __cplusplus
}
#endif

#endif
