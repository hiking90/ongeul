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
}

/// GitHub API `/releases/latest` 응답 JSON을 파싱하여 업데이트 정보를 반환한다.
///
/// - `json`: GitHub API 응답 본문 (JSON 문자열)
/// - `current_version`: 현재 앱 버전 (예: "0.2.0")
///
/// 파싱 실패 시 `None`을 반환한다.
/// pre-release 필터링은 `/releases/latest` API가 자체 처리하므로 별도로 하지 않는다.
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
