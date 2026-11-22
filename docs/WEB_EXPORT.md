# 웹 내보내기와 아이패드 테스트

`export_presets.cfg`의 **Web** 프리셋을 쓴다.

- 스레드 끔(`variant/thread_support=false`): 사파리에서 COOP/COEP 헤더 없이 돈다.
- 모바일 텍스처 압축 켬(ETC2/ASTC, `project.godot`의 `import_etc2_astc`).
- `data/` JSON을 함께 넣는다(`include_filter`). 문서·테스트·도구는 뺀다.
- `assets/audio/`는 뺀다: 받은 곳 라이선스를 확인하기 전에는 공개 배포 금지(README).
- 터치는 입력 상태기계가 직접 받는다: 마우스 흉내 끔(`project.godot` `input_devices/pointing`).

## 내보내기

1. Godot 4.7 에디터 → 편집기 → 내보내기 템플릿 관리 → 다운로드(처음 한 번).
2. 프로젝트 → 내보내기 → Web → 프로젝트 내보내기 → `build/web/index.html`.
   명령줄: `godot --headless --path . --export-release "Web" build/web/index.html`

## 아이패드에서 보기

PC와 아이패드를 같은 와이파이에 두고 PC에서:

```bash
cd build/web && python3 -m http.server 8000
```

아이패드 사파리에서 `http://<PC의 IP>:8000`을 연다.

## 조작(터치)

첫 탭 = 미리보기, 같은 칸 두 번째 탭 = 실행, 길게 누르기 = 정보, 한 손가락 끌기 = 화면 이동, 두 손가락 = 확대.
