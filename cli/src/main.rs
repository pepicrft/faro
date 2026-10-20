use faro_core::{Field, metadata};
use std::process::ExitCode;

fn output(args: &[String]) -> Result<String, &'static str> {
    let text = |field| metadata(field).to_str().expect("core metadata is UTF-8");
    match args {
        [] => Ok(format!(
            "{}\n{}\n\n{}",
            text(Field::Name),
            text(Field::Tagline),
            text(Field::Status),
        )),
        [flag] if flag == "--version" || flag == "-V" => {
            Ok(format!("{} {}", text(Field::Name), text(Field::Version)))
        }
        [flag] if flag == "--help" || flag == "-h" => Ok(format!(
            "{}\n\nUsage: faro [--help | --version]\n\nThis scaffold does not connect to a model yet.",
            text(Field::Tagline),
        )),
        _ => Err("unexpected arguments; use faro --help"),
    }
}

fn main() -> ExitCode {
    match output(&std::env::args().skip(1).collect::<Vec<_>>()) {
        Ok(text) => {
            println!("{text}");
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("faro: {error}");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shows_shared_metadata_by_default() {
        let text = output(&[]).unwrap();
        assert!(text.starts_with("Faro\n"));
        assert!(text.contains("Agent runtime coming next."));
    }

    #[test]
    fn supports_help_and_version() {
        assert!(output(&["--help".into()]).unwrap().contains("Usage: faro"));
        assert_eq!(output(&["--version".into()]).unwrap(), "Faro 0.1.0");
    }

    #[test]
    fn rejects_unknown_and_extra_arguments() {
        assert!(output(&["ask".into()]).is_err());
        assert!(output(&["--help".into(), "extra".into()]).is_err());
    }
}
