# KROLIK Vault — Next-Gen Runtime Plan

## Цель

Vault больше не рассматривается только как каталог/редактор. Финальная архитектура делится на два слоя:

1. **Vault Editor (Python + SQLite + WebView)** — импорт, каталог, версии, smart cutout, риг, карточки, ассеты, массовый QA, бэкапы.
2. **Vault Runtime (Godot 4.7.x)** — игровая сцена, Skeleton2D/Polygon2D, IK, AnimationTree, Navigation2D, физика, частицы, освещение, автономные персонажи и поведенческая симуляция.

Такой разрез позволяет не выбрасывать уже написанный редактор, но убрать потолок браузерного Canvas там, где нужен настоящий игровой runtime.

## Технологии, которые считаем приоритетными

- **Godot 4.7.x**: MIT, Windows EXE, 2D skeleton/mesh, navigation, animation state machines, shaders, particles, audio, physics.
- **Inochi2D / Inochi Creator**: BSD-2-Clause; изучаем архитектуру layered 2D puppet, mesh morphing и secondary physics. Не копируем проприетарные Live2D/Spine runtimes.
- **LimboAI**: MIT; behavior trees + state machines для автономных персонажей.
- **MMPose / RTMPose / DWPose ONNX**: Apache-2.0-направление для pose landmarks; выбираем только модели/обвязки с совместимой лицензией.
- **rembg + IS-Net anime + BiRefNet**: локальный каскад foreground segmentation/matting.
- **ONNX Runtime / DirectML/WebGPU/WASM**: аппаратное ускорение там, где оно реально доступно на пользовательском железе.
- **CC0 материалы**: Poly Haven / ambientCG или собственные процедурные материалы.

## Life Simulation

Каждый персонаж получает отдельный `mind`:

- energy;
- comfort;
- curiosity;
- social;
- autonomy;
- mobility;
- home cell;
- current cell;
- target cell;
- current state.

Базовые состояния: `idle`, `wander`, `inspect`, `social`, `rest`, `return_home`, `contained`, `disabled`.

Если персонаж свободен, runtime может выбирать действие и использовать Navigation2D. Если персонаж привязан к объекту/ограничителю, состояние принудительно становится `contained`: ходьба и выбор удалённой цели запрещаются, но остаются idle/secondary animation/reaction layers.

## Character Runtime

Целевой персонаж состоит не из одного PNG, а из:

- source image/version;
- foreground alpha;
- semantic regions;
- joint landmarks;
- Skeleton2D;
- weighted Polygon2D mesh;
- face/eyes/mouth overlays, если исходник позволяет;
- hair/accessory dynamic chains;
- animation graph;
- interaction anchors;
- collision/occlusion proxies;
- behavior profile.

Для одного изображения нельзя достоверно восстановить невидимую сторону тела. Поэтому camera profile хранит реальные доступные ракурсы, а недостающие ракурсы никогда не маскируются под «точную реконструкцию».

## Автоматический импорт будущего

`drop image -> detect subject -> choose best cutout -> pose detect -> rig proposal -> mesh generation -> QA score -> user correction only where confidence is low -> character becomes runtime-ready`.

## Массовый QA

Каждый из 82+ персонажей должен проходить один и тот же набор:

- segmentation candidates;
- edge quality;
- alpha halo/fringing;
- full-body/partial-body classification;
- pose confidence;
- joint plausibility;
- mesh deformation smoke poses;
- fixture fit smoke tests;
- animation smoke tests;
- performance/VRAM/RAM budget.

Результаты сохраняются, чтобы улучшение алгоритма можно было прогнать повторно на всей коллекции и сравнить до/после.
