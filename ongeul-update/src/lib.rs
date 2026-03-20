uniffi::setup_scaffolding!();

mod release;
mod version;

pub use release::{parse_release_response, UpdateInfo};
pub use version::is_newer_version;
