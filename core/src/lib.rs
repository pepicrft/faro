//! Platform-independent Faro core. Native clients consume the same metadata
//! through a small C/JNI boundary; the CLI and GPUI use Rust directly.

mod ffi;

#[cfg(any(target_os = "android", test))]
mod jni;

use std::ffi::CStr;

/// Stable field IDs shared by the native adapters. Strings are immutable and
/// live for the lifetime of the process. Adding fields must preserve these IDs.
#[derive(Clone, Copy)]
#[repr(i32)]
pub enum Field {
    Name = 0,
    Tagline = 1,
    Status = 2,
    Version = 3,
}

pub fn metadata(field: Field) -> &'static CStr {
    match field {
        Field::Name => c"Faro",
        Field::Tagline => c"Your personal, open-source agent.",
        Field::Status => c"A shared Rust core. Native on every device. Agent runtime coming next.",
        Field::Version => c"0.1.0",
    }
}

pub(crate) fn field(id: i32) -> Option<&'static CStr> {
    let field = match id {
        0 => Field::Name,
        1 => Field::Tagline,
        2 => Field::Status,
        3 => Field::Version,
        _ => return None,
    };
    Some(metadata(field))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metadata_is_nonempty_utf8() {
        for id in 0..4 {
            let value = field(id).unwrap().to_str().unwrap();
            assert!(!value.is_empty());
        }
        assert_eq!(metadata(Field::Name).to_str().unwrap(), "Faro");
    }

    #[test]
    fn rejects_unknown_fields() {
        for id in [i32::MIN, -1, 4, i32::MAX] {
            assert!(field(id).is_none());
        }
    }
}
