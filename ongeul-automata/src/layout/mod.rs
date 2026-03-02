/// 자판 레이아웃 로딩 및 키맵/조합 조회
pub mod schema;

use std::collections::HashMap;

use schema::{LayoutSchema, LayoutType};

/// 파싱된 자판 레이아웃
#[derive(Debug, Clone)]
pub struct KeyboardLayout {
    pub id: String,
    pub name: String,
    pub layout_type: LayoutType,
    /// 키 레이블 → 자모 char 매핑
    keymap: HashMap<String, char>,
    /// (첫째 자모, 둘째 자모) → 결합 결과
    combinations: HashMap<(char, char), char>,
}

/// 16진수 문자열("0x3131" 등)을 char로 변환
fn parse_hex_char(s: &str) -> Option<char> {
    let hex = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X"))?;
    let code = u32::from_str_radix(hex, 16).ok()?;
    char::from_u32(code)
}

impl KeyboardLayout {
    /// JSON5 문자열에서 레이아웃을 파싱한다.
    pub fn from_json(json: &str) -> Result<Self, String> {
        let schema: LayoutSchema =
            json5::from_str(json).map_err(|e| format!("JSON5 parse error: {e}"))?;

        let mut keymap = HashMap::with_capacity(schema.keymap.len());
        for (key, hex) in &schema.keymap {
            let ch = parse_hex_char(hex)
                .ok_or_else(|| format!("Invalid hex in keymap: {key} → {hex}"))?;
            keymap.insert(key.clone(), ch);
        }

        let mut combinations = HashMap::with_capacity(schema.combinations.len());
        for entry in &schema.combinations {
            let first = parse_hex_char(&entry.first)
                .ok_or_else(|| format!("Invalid hex in combination first: {}", entry.first))?;
            let second = parse_hex_char(&entry.second)
                .ok_or_else(|| format!("Invalid hex in combination second: {}", entry.second))?;
            let result = parse_hex_char(&entry.result)
                .ok_or_else(|| format!("Invalid hex in combination result: {}", entry.result))?;
            combinations.insert((first, second), result);
        }

        Ok(KeyboardLayout {
            id: schema.id,
            name: schema.name,
            layout_type: schema.layout_type,
            keymap,
            combinations,
        })
    }

    /// 키 레이블로 자모를 조회
    pub fn map_key(&self, key: &str) -> Option<char> {
        self.keymap.get(key).copied()
    }

    /// 두 자모의 조합 결과를 조회
    pub fn combine(&self, first: char, second: char) -> Option<char> {
        self.combinations.get(&(first, second)).copied()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MINIMAL_JAMO_JSON: &str = r#"{
        id: "test-2bul",
        name: "테스트 두벌식",
        type: "jamo",
        keymap: {
            "q": "0x3142",  // ㅂ
            "w": "0x3148",  // ㅈ
            "k": "0x314F",  // ㅏ
        },
        combinations: [
            { first: "0x3157", second: "0x314F", result: "0x3158" },  // ㅗ + ㅏ = ㅘ
        ],
    }"#;

    #[test]
    fn test_parse_layout() {
        let layout = KeyboardLayout::from_json(MINIMAL_JAMO_JSON).unwrap();
        assert_eq!(layout.id, "test-2bul");
        assert_eq!(layout.layout_type, LayoutType::Jamo);
    }

    #[test]
    fn test_map_key() {
        let layout = KeyboardLayout::from_json(MINIMAL_JAMO_JSON).unwrap();
        assert_eq!(layout.map_key("q"), Some('ㅂ'));
        assert_eq!(layout.map_key("w"), Some('ㅈ'));
        assert_eq!(layout.map_key("k"), Some('ㅏ'));
        assert_eq!(layout.map_key("z"), None);
    }

    #[test]
    fn test_combine() {
        let layout = KeyboardLayout::from_json(MINIMAL_JAMO_JSON).unwrap();
        // ㅗ + ㅏ = ㅘ
        assert_eq!(layout.combine('ㅗ', 'ㅏ'), Some('ㅘ'));
        // 정의되지 않은 조합
        assert_eq!(layout.combine('ㅏ', 'ㅏ'), None);
    }

    #[test]
    fn test_invalid_json() {
        let result = KeyboardLayout::from_json("not json");
        assert!(result.is_err());
    }

    #[test]
    fn test_parse_hex_char() {
        assert_eq!(parse_hex_char("0x3131"), Some('ㄱ'));
        assert_eq!(parse_hex_char("0xAC00"), Some('가'));
        assert_eq!(parse_hex_char("invalid"), None);
    }

    // ── 오류 처리 테스트 ──

    #[test]
    fn test_missing_required_fields() {
        // id 누락
        let json = r#"{ name: "test", type: "jamo", keymap: {}, combinations: [] }"#;
        assert!(KeyboardLayout::from_json(json).is_err());

        // name 누락
        let json = r#"{ id: "test", type: "jamo", keymap: {}, combinations: [] }"#;
        assert!(KeyboardLayout::from_json(json).is_err());

        // type 누락
        let json = r#"{ id: "test", name: "test", keymap: {}, combinations: [] }"#;
        assert!(KeyboardLayout::from_json(json).is_err());
    }

    #[test]
    fn test_invalid_hex_in_keymap() {
        let json = r#"{
            id: "test", name: "test", type: "jamo",
            keymap: { "a": "not_hex" },
            combinations: [],
        }"#;
        let result = KeyboardLayout::from_json(json);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid hex"));
    }

    #[test]
    fn test_invalid_hex_in_combination() {
        // first가 잘못된 hex
        let json = r#"{
            id: "test", name: "test", type: "jamo",
            keymap: {},
            combinations: [{ first: "bad", second: "0x3131", result: "0x3132" }],
        }"#;
        assert!(KeyboardLayout::from_json(json)
            .unwrap_err()
            .contains("Invalid hex"));

        // second가 잘못된 hex
        let json = r#"{
            id: "test", name: "test", type: "jamo",
            keymap: {},
            combinations: [{ first: "0x3131", second: "bad", result: "0x3132" }],
        }"#;
        assert!(KeyboardLayout::from_json(json)
            .unwrap_err()
            .contains("Invalid hex"));

        // result가 잘못된 hex
        let json = r#"{
            id: "test", name: "test", type: "jamo",
            keymap: {},
            combinations: [{ first: "0x3131", second: "0x3132", result: "bad" }],
        }"#;
        assert!(KeyboardLayout::from_json(json)
            .unwrap_err()
            .contains("Invalid hex"));
    }

    #[test]
    fn test_empty_keymap_is_valid() {
        let json = r#"{
            id: "test", name: "test", type: "jamo",
            keymap: {},
            combinations: [],
        }"#;
        let layout = KeyboardLayout::from_json(json).unwrap();
        assert_eq!(layout.map_key("a"), None);
    }

    #[test]
    fn test_invalid_layout_type() {
        let json = r#"{
            id: "test", name: "test", type: "unknown",
            keymap: {},
            combinations: [],
        }"#;
        assert!(KeyboardLayout::from_json(json).is_err());
    }

    #[test]
    fn test_parse_hex_char_edge_cases() {
        // 0x 접두사 없음
        assert_eq!(parse_hex_char("3131"), None);
        // 빈 문자열
        assert_eq!(parse_hex_char(""), None);
        // 0x만
        assert_eq!(parse_hex_char("0x"), None);
        // 대문자 0X 접두사
        assert_eq!(parse_hex_char("0X3131"), Some('ㄱ'));
        // 잘못된 유니코드 코드포인트 (서로게이트)
        assert_eq!(parse_hex_char("0xD800"), None);
    }

    #[test]
    fn test_duplicate_key_last_wins() {
        // JSON5에서 동일 키가 중복되면 마지막 값이 사용됨
        let json = r#"{
            id: "test", name: "test", type: "jamo",
            keymap: {
                "a": "0x3131",  // ㄱ
                "a": "0x3134",  // ㄴ (덮어씀)
            },
            combinations: [],
        }"#;
        let layout = KeyboardLayout::from_json(json).unwrap();
        assert_eq!(layout.map_key("a"), Some('ㄴ'));
    }
}
