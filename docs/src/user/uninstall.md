# 제거

## 1. 앱 삭제

설치 방법에 따라 해당 경로의 `Ongeul.app`을 삭제합니다.

### .pkg로 설치한 경우

```bash
sudo rm -rf "/Library/Input Methods/Ongeul.app"
```

### install.sh로 설치한 경우

```bash
rm -rf ~/Library/Input\ Methods/Ongeul.app
```

## 2. 입력 소스 제거

1. **시스템 설정** → **키보드** → **입력 소스** → **편집...** 을 클릭합니다.
2. 목록에서 **Ongeul** 을 선택합니다.
3. **−** 버튼을 클릭하여 제거합니다.
4. **ABC** 등 다른 입력 소스를 추가합니다 (입력 소스가 최소 1개 필요).

## 3. 로그아웃/로그인

변경 사항을 완전히 반영하려면 로그아웃 후 재로그인하세요.
