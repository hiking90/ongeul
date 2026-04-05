uniffi::setup_scaffolding!();

mod release;
mod version;

pub use release::{UpdateInfo, parse_release_response, parse_releases_response};
pub use version::is_newer_version;
