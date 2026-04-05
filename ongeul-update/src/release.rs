use serde::Deserialize;

/// Swift에 반환할 업데이트 정보
#[derive(uniffi::Record, Debug, Clone)]
pub struct UpdateInfo {
    /// 최신 버전 (예: "0.3.0")
    pub latest_version: String,
    /// GitHub Release 페이지 URL
    pub download_url: String,
    /// 업데이트 가능 여부
    pub is_update_available: bool,
}

/// GitHub API 응답 중 필요한 필드만 추출.
/// serde는 기본적으로 미지 필드를 무시하므로, 실제 API 응답의 수십 개 필드가
/// 있어도 안전하게 파싱된다.
#[derive(Deserialize)]
struct GitHubRelease {
    tag_name: String,
    html_url: String,
    #[serde(default)]
    draft: bool,
}

/// GitHub API `/releases/latest` 응답 JSON을 파싱하여 업데이트 정보를 반환한다.
///
/// - `json`: GitHub API 응답 본문 (JSON 문자열)
/// - `current_version`: 현재 앱 버전 (예: "0.2.0")
///
/// 파싱 실패 시 `None`을 반환한다.
/// `/releases/latest` API는 pre-release를 반환하지 않으며,
/// `is_newer_version()`도 정식 사용자에게 pre-release를 제외하므로 이중 방어된다.
#[uniffi::export]
pub fn parse_release_response(json: &str, current_version: &str) -> Option<UpdateInfo> {
    let release: GitHubRelease = json5::from_str(json).ok()?;

    // "v0.2.0" → "0.2.0"
    let latest = release
        .tag_name
        .strip_prefix('v')
        .unwrap_or(&release.tag_name);

    Some(UpdateInfo {
        latest_version: latest.to_string(),
        download_url: release.html_url,
        is_update_available: crate::version::is_newer_version(latest, current_version),
    })
}

/// GitHub `/releases` API 응답(JSON 배열)에서 업데이트 가능한 최신 버전을 반환한다.
///
/// GitHub API는 `published_at` 역순(최신순)으로 반환하므로,
/// 첫 번째 적격 릴리스가 가장 최신이다.
///
/// pre-release 사용자가 `/releases` 전체 목록에서 업데이트를 찾을 때 사용한다.
/// 같은 base version의 pre-release 간 비교는 리스트 순서(= 날짜순)로 판단한다.
///
/// 업데이트 없으면 `None` (에러가 아님).
#[uniffi::export]
pub fn parse_releases_response(json: &str, current_version: &str) -> Option<UpdateInfo> {
    let releases: Vec<GitHubRelease> = json5::from_str(json).ok()?;

    let current_base = current_version.split('-').next().unwrap_or(current_version);
    let current_is_pre = current_version.contains('-');

    for release in &releases {
        if release.draft {
            continue;
        }
        let version = release
            .tag_name
            .strip_prefix('v')
            .unwrap_or(&release.tag_name);

        if version == current_version {
            continue;
        }

        // base가 더 크거나, 같은 base에서 정식 출시 → 업데이트
        if crate::version::is_newer_version(version, current_version) {
            return Some(UpdateInfo {
                latest_version: version.to_string(),
                download_url: release.html_url.clone(),
                is_update_available: true,
            });
        }

        // 같은 base의 pre-release 간: 리스트 앞에 있으므로 날짜순 최신
        let version_base = version.split('-').next().unwrap_or(version);
        if version_base == current_base && version.contains('-') && current_is_pre {
            return Some(UpdateInfo {
                latest_version: version.to_string(),
                download_url: release.html_url.clone(),
                is_update_available: true,
            });
        }
    }

    None
}
