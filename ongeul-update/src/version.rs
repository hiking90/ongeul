/// Semantic version 비교. `latest`가 `current`보다 새로우면 `true`.
///
/// pre-release suffix는 제거 후 기본 버전만 비교한다.
/// 예: `"0.3.0-rc1"` → `"0.3.0"`
#[uniffi::export]
pub fn is_newer_version(latest: &str, current: &str) -> bool {
    let parse = |v: &str| -> Vec<u32> {
        // pre-release suffix 제거
        let base = v.split('-').next().unwrap_or(v);
        base.split('.').filter_map(|s| s.parse().ok()).collect()
    };

    let latest_parts = parse(latest);
    let current_parts = parse(current);

    let max_len = latest_parts.len().max(current_parts.len());
    for i in 0..max_len {
        let l = latest_parts.get(i).copied().unwrap_or(0);
        let c = current_parts.get(i).copied().unwrap_or(0);
        match l.cmp(&c) {
            std::cmp::Ordering::Greater => return true,
            std::cmp::Ordering::Less => return false,
            std::cmp::Ordering::Equal => continue,
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn newer_version() {
        assert!(is_newer_version("0.3.0", "0.2.0"));
        assert!(is_newer_version("0.2.1", "0.2.0"));
        assert!(is_newer_version("1.0.0", "0.9.9"));
    }

    #[test]
    fn same_version() {
        assert!(!is_newer_version("0.2.0", "0.2.0"));
    }

    #[test]
    fn older_version() {
        assert!(!is_newer_version("0.1.0", "0.2.0"));
    }

    #[test]
    fn prerelease_suffix_stripped() {
        assert!(!is_newer_version("0.2.0-rc1", "0.2.0"));
        assert!(is_newer_version("0.3.0-rc1", "0.2.0"));
    }

    #[test]
    fn different_length() {
        assert!(is_newer_version("0.2.1", "0.2"));
        assert!(!is_newer_version("0.2", "0.2.1"));
    }
}
