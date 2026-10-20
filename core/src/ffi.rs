use core::ffi::c_char;

/// Returns an immutable process-lifetime UTF-8 C string, or null for an unknown
/// field. Callers must not mutate or free the returned pointer.
#[unsafe(no_mangle)]
pub extern "C" fn faro_metadata_field(id: i32) -> *const c_char {
    crate::field(id).map_or(core::ptr::null(), |value| value.as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn faro_metadata_length(id: i32) -> i32 {
    crate::field(id).map_or(-1, |value| value.to_bytes().len() as i32)
}

#[unsafe(no_mangle)]
pub extern "C" fn faro_metadata_byte(id: i32, offset: i32) -> i32 {
    usize::try_from(offset)
        .ok()
        .and_then(|offset| crate::field(id)?.to_bytes().get(offset))
        .map_or(-1, |byte| i32::from(*byte))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn c_and_byte_bridges_match_the_core() {
        for id in 0..4 {
            let expected = crate::field(id).unwrap();
            assert_eq!(faro_metadata_field(id), expected.as_ptr());
            let length = faro_metadata_length(id);
            let bytes: Vec<_> = (0..length)
                .map(|offset| faro_metadata_byte(id, offset) as u8)
                .collect();
            assert_eq!(bytes, expected.to_bytes());
            assert_eq!(faro_metadata_byte(id, length), -1);
        }
    }

    #[test]
    fn invalid_indices_are_safe() {
        for id in [-1, 4, i32::MAX] {
            assert!(faro_metadata_field(id).is_null());
            assert_eq!(faro_metadata_length(id), -1);
            assert_eq!(faro_metadata_byte(id, 0), -1);
        }
        for offset in [-1, i32::MAX] {
            assert_eq!(faro_metadata_byte(0, offset), -1);
        }
    }
}
