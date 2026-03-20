use ongeul_update::parse_release_response;

#[test]
fn parse_valid_release() {
    let json = r#"{
        "tag_name": "v0.3.0",
        "prerelease": false,
        "html_url": "https://github.com/hiking90/ongeul/releases/tag/v0.3.0"
    }"#;
    let info = parse_release_response(json, "0.2.0").unwrap();
    assert_eq!(info.latest_version, "0.3.0");
    assert!(info.is_update_available);
    assert!(info.download_url.contains("v0.3.0"));
}

#[test]
fn parse_same_version() {
    let json = r#"{
        "tag_name": "v0.2.0",
        "prerelease": false,
        "html_url": "https://github.com/hiking90/ongeul/releases/tag/v0.2.0"
    }"#;
    let info = parse_release_response(json, "0.2.0").unwrap();
    assert!(!info.is_update_available);
}

#[test]
fn invalid_json_returns_none() {
    assert!(parse_release_response("not json", "0.2.0").is_none());
    assert!(parse_release_response("", "0.2.0").is_none());
}

#[test]
fn tag_without_v_prefix() {
    let json = r#"{
        "tag_name": "0.3.0",
        "prerelease": false,
        "html_url": "https://github.com/hiking90/ongeul/releases/tag/0.3.0"
    }"#;
    let info = parse_release_response(json, "0.2.0").unwrap();
    assert_eq!(info.latest_version, "0.3.0");
    assert!(info.is_update_available);
}

/// 실제 GitHub API 응답에는 수십 개의 필드가 포함된다.
/// serde가 미지 필드를 무시하고 필요한 필드만 정상 추출하는지 검증한다.
#[test]
fn parse_realistic_github_response() {
    let json = r#"{
        "url": "https://api.github.com/repos/hiking90/ongeul/releases/12345",
        "assets_url": "https://api.github.com/repos/hiking90/ongeul/releases/12345/assets",
        "upload_url": "https://uploads.github.com/repos/hiking90/ongeul/releases/12345/assets{?name,label}",
        "html_url": "https://github.com/hiking90/ongeul/releases/tag/v0.3.0",
        "id": 12345,
        "author": {
            "login": "hiking90",
            "id": 67890
        },
        "node_id": "RE_abc123",
        "tag_name": "v0.3.0",
        "target_commitish": "main",
        "name": "Ongeul 0.3.0",
        "draft": false,
        "prerelease": false,
        "created_at": "2026-03-19T00:00:00Z",
        "published_at": "2026-03-19T01:00:00Z",
        "assets": [
            {
                "name": "Ongeul-0.3.0.pkg",
                "content_type": "application/x-xar",
                "size": 5242880,
                "download_count": 42,
                "browser_download_url": "https://github.com/hiking90/ongeul/releases/download/v0.3.0/Ongeul-0.3.0.pkg"
            }
        ],
        "tarball_url": "https://api.github.com/repos/hiking90/ongeul/tarball/v0.3.0",
        "zipball_url": "https://api.github.com/repos/hiking90/ongeul/zipball/v0.3.0",
        "body": "Changes: new feature added"
    }"#;
    let info = parse_release_response(json, "0.2.0").unwrap();
    assert_eq!(info.latest_version, "0.3.0");
    assert_eq!(
        info.download_url,
        "https://github.com/hiking90/ongeul/releases/tag/v0.3.0"
    );
    assert!(info.is_update_available);
}
