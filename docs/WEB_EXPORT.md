# 웹 내보내기와 아이패드 테스트

`export_presets.cfg`의 **Web** 프리셋을 쓴다.

- 스레드 끔(`variant/thread_support=false`): 사파리에서 COOP/COEP 헤더 없이 돈다.
- 모바일 텍스처 압축 켬(ETC2/ASTC, `project.godot`의 `import_etc2_astc`).
- `data/` JSON을 함께 넣는다(`include_filter`). 문서·테스트·도구는 뺀다.
- `assets/audio/`는 뺀다: 받은 곳 라이선스를 확인하기 전에는 공개 배포 금지(README).
- 터치 → 마우스 흉내 켬(`project.godot` `input_devices/pointing`): 창·버튼(Control)은 마우스만 받아서 끄면 소지품 창 등이 터치에 안 먹는다.
  맵 입력 상태기계(input_router.gd)는 터치를 직접 받고, 흉내 낸 마우스(device = DEVICE_ID_EMULATION)는 버린다.
- 아이패드 키보드: 사파리는 tabindex 없는 캔버스에 포커스를 주지 않아 키가 body로 간다. 프리셋 `html/head_include` 스크립트가
  캔버스에 tabindex를 달고, 터치하면 포커스를 주고, 캔버스 밖으로 간 키를 캔버스로 넘긴다.
  게임은 자리 키(`physical_keycode`)로 판정한다 — 한글 입력 상태에서도 I·K·숫자키가 먹는다.

## 내보내기

1. Godot 4.7 에디터 → 편집기 → 내보내기 템플릿 관리 → 다운로드(처음 한 번).
2. 프로젝트 → 내보내기 → Web → 프로젝트 내보내기 → `build/web/index.html`.
   명령줄: `godot --headless --path . --export-release "Web" build/web/index.html`

## GitHub Pages(자동 배포)

`.github/workflows/web.yml`이 push마다 Godot 4.7.2로 웹 빌드를 만들고, `main`이면 Pages에 올린다.

- 주소: https://rin1015sh.github.io/DuskFall/ — 아이패드 사파리로 연다(홈 화면에 추가하면 전체 화면).
- 처음 한 번: 저장소 Settings → Pages → Source를 **GitHub Actions**로.
- 다른 브랜치는 빌드만 한다(Actions 실행의 `github-pages` 산출물을 받아 로컬에서 볼 수 있다).

## 아이패드에서 보기(로컬)

PC와 아이패드를 같은 와이파이에 두고 PC에서:

```bash
cd build/web && python3 -m http.server 8000
```

아이패드 사파리에서 `http://<PC의 IP>:8000`을 연다.

## 조작(터치)

첫 탭 = 미리보기, 같은 칸 두 번째 탭 = 실행, 길게 누르기 = 정보, 한 손가락 끌기 = 화면 이동, 두 손가락 = 확대.
