use std::cmp::Ordering;

/// base version (숫자 부분)만 비교. Greater/Less/Equal 반환.
fn compare_base(a: &str, b: &str) -> Ordering {
    let parse = |v: &str| -> Vec<u32> {
        v.split('.').filter_map(|s| s.parse().ok()).collect()
    };
    let a_parts = parse(a);
    let b_parts = parse(b);
    let max_len = a_parts.len().max(b_parts.len());
    for i in 0..max_len {
        let x = a_parts.get(i).copied().unwrap_or(0);
        let y = b_parts.get(i).copied().unwrap_or(0);
        match x.cmp(&y) {
            Ordering::Equal => continue,
            other => return other,
        }
    }
    Ordering::Equal
}

/// Semantic version 비교. `latest`가 `current`보다 새로우면 `true`.
///
/// - 정식 버전 사용 시: 정식 버전만 업데이트 대상 (pre-release 제외)
/// - pre-release 사용 시: base가 더 큰 버전 또는 같은 base의 정식 버전이 대상
/// - 같은 base의 pre-release 간 비교는 `false` 반환
///   (날짜 기반 비교는 `parse_releases_response()`에서 GitHub API 순서로 처리)
#[uniffi::export]
pub fn is_newer_version(latest: &str, current: &str) -> bool {
    let current_is_pre = current.contains('-');
    let latest_is_pre = latest.contains('-');

    // 정식 사용자에게 pre-release 제외
    if !current_is_pre && latest_is_pre {
        return false;
    }

    let latest_base = latest.split('-').next().unwrap_or(latest);
    let current_base = current.split('-').next().unwrap_or(current);

    match compare_base(latest_base, current_base) {
        Ordering::Greater => true,
        Ordering::Less => false,
        Ordering::Equal => {
            // 같은 base: 정식 > pre-release
            !latest_is_pre && current_is_pre
        }
    }
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
    fn official_ignores_prerelease() {
        // 정식 버전 사용자에게 pre-release는 업데이트 대상 아님
        assert!(!is_newer_version("0.3.0-rc1", "0.2.0"));
        assert!(!is_newer_version("0.2.0-rc1", "0.2.0"));
    }

    #[test]
    fn prerelease_to_official() {
        // pre-release 사용 중 같은 base의 정식 출시 → 업데이트
        assert!(is_newer_version("0.3.0", "0.3.0-rc1"));
    }

    #[test]
    fn prerelease_same_base_returns_false() {
        // 같은 base의 pre-release 간 비교는 false (날짜로 판단)
        assert!(!is_newer_version("0.3.0-rc2", "0.3.0-rc1"));
        assert!(!is_newer_version("0.3.0-rc1", "0.3.0-rc1"));
    }

    #[test]
    fn prerelease_different_base() {
        // base가 다른 pre-release → base 비교로 판단
        assert!(is_newer_version("0.4.0-rc1", "0.3.0-rc1"));
        assert!(!is_newer_version("0.2.0-rc1", "0.3.0-rc1"));
    }

    #[test]
    fn different_length() {
        assert!(is_newer_version("0.2.1", "0.2"));
        assert!(!is_newer_version("0.2", "0.2.1"));
    }
}
