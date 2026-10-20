use core::ffi::c_void;

// Bootstrap metadata uses primitive-only JNI, like Atlas's catalog bridge.
// These functions never dereference VM pointers or allocate Java objects.
// Use a proper JNI library when introducing dynamic strings/session commands.
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_pepicrft_faro_FaroCore_fieldLength(
    _environment: *mut c_void,
    _instance: *mut c_void,
    id: i32,
) -> i32 {
    crate::ffi::faro_metadata_length(id)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_pepicrft_faro_FaroCore_fieldByte(
    _environment: *mut c_void,
    _instance: *mut c_void,
    id: i32,
    offset: i32,
) -> i32 {
    crate::ffi::faro_metadata_byte(id, offset)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jni_matches_the_c_boundary_and_rejects_invalid_inputs() {
        let env = core::ptr::null_mut();
        let instance = core::ptr::null_mut();
        for id in -1..=4 {
            let length = Java_io_github_pepicrft_faro_FaroCore_fieldLength(env, instance, id);
            assert_eq!(length, crate::ffi::faro_metadata_length(id));
            for offset in -1..=length.max(0) {
                assert_eq!(
                    Java_io_github_pepicrft_faro_FaroCore_fieldByte(env, instance, id, offset),
                    crate::ffi::faro_metadata_byte(id, offset),
                );
            }
        }
    }
}
