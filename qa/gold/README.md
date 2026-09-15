# Gold character regression

`gold-elf-v1` is the mandatory user-provided stylized-character reference for the production import/runtime path.

A green structural rig alone is not sufficient. The reference must also satisfy the practical visual/runtime gates:

- the automatic cutout is accepted without manual-review status and does not carry a deformable studio-floor/background region;
- DWPose remains the accepted autorig backend;
- the runtime package contains 15 joints, 14 bones, skin weights and collision proxies;
- per-joint confidence survives into the runtime manifest so uncertain interaction anchors can be handled safely;
- the exact package loads through the production Godot GPU-skin path and produces non-trivial rendered deformation;
- generated overlay, cutout, baseline render and posed render are retained as QA evidence for human inspection.

The original user PNG identity is pinned in `gold_elf_v1.json`; CI uses a deterministic compact derivative only to keep repeated regression runs small. Expected landmark tolerances are frozen only after a visually accepted model run, never invented in advance.
