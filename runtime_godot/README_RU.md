# KROLIK Vault Runtime (Godot 4.7.x)

Это второй runtime-слой Vault. Python/SQLite остаётся редактором, импортёром, каталогом и хранилищем. Godot отвечает за то, что должно ощущаться как игра: живых персонажей, Navigation2D, Skeleton2D/Polygon2D, IK, физические ограничения, частицы, свет и автономное поведение.

Текущий runtime уже строит deformable 2D-персонажа как Polygon2D + Skeleton2D/Bone2D из экспортированного runtime-пакета, принимает solved IK joints, создаёт collision capsules на CharacterBody2D и использует NavigationAgent2D для перемещения по миру. CPU mesh deformation в Python остаётся offline/reference-инструментом.

Целевой конвейер:

`карточка -> smart cutout -> pose landmarks -> Skeleton2D/mesh weights -> animation set -> behavior brain -> scene constraints -> realtime runtime`.

При привязке персонажа к объекту/ограничителю мозг не пытается выбрать ходьбу: состояние становится `contained`. В свободном режиме utility-модель выбирает idle/wander/inspect/social/rest/return_home и runtime следует NavigationServer2D.

Следующие визуальные уровни: pose/animation clips на самом скелете, AnimationTree/blending, secondary spring chains для волос/одежды/аксессуаров и более точная геометрия navigation/collision из экспортированной сцены.
