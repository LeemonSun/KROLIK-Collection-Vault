# KROLIK Collection Vault — карта открытых технологий

Цель этого файла — не превращать проект в набор случайных зависимостей, а фиксировать, какие зрелые open-source системы мы изучаем и какую конкретную часть Vault они могут усилить. Закрытый/проприетарный код не копируем; поведение можно воспроизводить независимо, а код используем только там, где лицензия это разрешает.

## 1. Персонаж как 2D puppet

### Inochi2D
- роль: mesh deformation, parameters, 2D puppet architecture, secondary motion;
- лицензия: BSD-2-Clause;
- использование в Vault: формат весов/мешей и runtime-идеи, без зависимости от одного редактора.

### DragonBones / weighted mesh references
- роль: skeletal clips, slots, FFD/mesh deformation, skinning, animation state;
- использование: архитектурный ориентир для собственного Godot runtime.

## 2. Автоматическая подготовка исходника

### anime-segmentation / IS-Net anime
- роль: отделение стилизованного персонажа от сложного фона;
- лицензия: Apache-2.0;
- использование: AI cutout backend в каскаде с BiRefNet/rembg и ручной маской.

### DWPose / MMPose
- роль: keypoints тела/рук/лица как сильный автоматический стартовый rig;
- лицензия: Apache-2.0;
- использование: optional ONNX detector; результат всегда редактируемый.

## 3. Живое поведение / tamagotchi

### VPet
- роль: пример зрелой виртуальной pet-архитектуры — много состояний, анимаций, действий, модов, UI и расширяемого core;
- лицензия кода: Apache-2.0 (встроенные арт/анимации имеют отдельные условия);
- использование: изучаем game-core/state/action/plugin architecture, но собственные ассеты и собственный runtime оставляем отдельными.

## 4. Опциональный 3D путь

### TripoSR
- роль: single-image → 3D mesh как вспомогательный путь для случаев, где 2D puppet не может честно показать невидимую сторону;
- лицензия: MIT;
- использование: только как optional reconstruction backend. Результат считается реконструкцией, а не истинным восстановлением скрытых пикселей.

## 5. Архитектура KROLIK после исследования

Основной pipeline:

`image -> cutout ensemble -> pose/keypoints -> editable skeleton -> semantic body regions -> weighted mesh -> IK/constraints -> animation graph -> physics -> mind/behavior -> Godot world`

Два runtime режима:
1. **Art-preserving 2D/2.5D** — основной. Максимально сохраняет исходный арт, деформирует локально и не генерирует новые детали без явного выбора.
2. **Reconstruction mode** — тяжёлый optional режим. Делает 3D/novel-view реконструкцию для свободных ракурсов и сложных поз.

## 6. Что не тащим

- неизвестные бинарники без исходников;
- проприетарный код без разрешающей лицензии;
- ассеты с неясными правами;
- модели, которые требуют облачного API для базовой работы;
- зависимости, которые нельзя отключить и которые ломают офлайн режим.

## 7. Текущий технический приоритет

1. bone-weighted mesh вместо глобального TPS;
2. DWPose/AnimeSeg adapters;
3. semantic regions: head/torso/arms/legs/hair/clothes/accessories;
4. GPU skinning в Godot;
5. constraints + collision bodies;
6. animation library + blend/state graph;
7. utility/behavior planner, navigation, schedules and persistent memory;
8. optional 3D reconstruction path.
