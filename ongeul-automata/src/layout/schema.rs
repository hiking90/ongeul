/// JSON5 자판 레이아웃 스키마용 serde 타입
use std::collections::HashMap;

use serde::Deserialize;

/// 자판 타입: 두벌식(jamo) 또는 세벌식(jaso)
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LayoutType {
    Jamo,
    Jaso,
}

/// 조합 규칙 항목 (겹모음/겹종성)
#[derive(Debug, Clone, Deserialize)]
pub struct CombinationEntry {
    /// 첫째 자모 (16진수 문자열, 예: "0x3157")
    pub first: String,
    /// 둘째 자모 (16진수 문자열, 예: "0x314F")
    pub second: String,
    /// 결합 결과 (16진수 문자열, 예: "0x3158")
    pub result: String,
}

/// 레이아웃 옵션
#[derive(Debug, Clone, Default, Deserialize)]
pub struct LayoutOptions {
    // 향후 레이아웃별 옵션 추가 시 사용
}

/// JSON5 레이아웃 최상위 스키마
#[derive(Debug, Clone, Deserialize)]
pub struct LayoutSchema {
    /// 레이아웃 식별자 (예: "2-standard")
    pub id: String,
    /// 레이아웃 이름 (예: "두벌식 표준")
    pub name: String,
    /// 자판 타입
    #[serde(rename = "type")]
    pub layout_type: LayoutType,
    /// 키 → 자모 매핑 (키 레이블 → 16진수 코드포인트)
    pub keymap: HashMap<String, String>,
    /// 조합 규칙 (겹모음, 겹종성 등)
    #[serde(default)]
    pub combinations: Vec<CombinationEntry>,
    /// 옵션
    #[serde(default)]
    pub options: LayoutOptions,
}
