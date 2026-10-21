# Messy yard - plan

All GDScript. No new assets. Branch `chartoid/messy`.

## Pieces
1. `scripts/david.gd` - wandering David NPCs (contestant.glb). Forklift hit above 1.5 m/s: model moves to a RigidBody3D capsule, impulse + spin, flail anim. Respawn at home after 4 s.
2. `forklift.gd` - emits `crashed(collider, speed, dir, point)` from slide collisions. Soft bodies (rigid, David) slow it less than walls. Oil patches: low grip (drift velocity), weak brakes, wobble. Emits `oil_entered`.
3. `level.gd` - crash handler, MESS score + HUD label, popups, debris pool (capped, auto-free).
   - Pallet hit at 2.5+ m/s: breaks into 8 loose crates + boards. Respawn pallet later.
   - Rigid crate stacks (pyramid, tower, old 3-stack): topple from pushes; 3.8+ m/s smashes a crate.
   - Cones + barrels: rigid, pushed by forklift. Red barrels leak a new oil patch when hit hard.
   - Oil patches: fixed ones + leaks. Shared list read by the forklift.
4. `player.gd` - walker pushes rigid bodies.

## MESS points
David 250, pallet 100, crate smash 40, barrel 30 (+leak 50), cone 20, oil entry 5, toppled crate 10 (first hit).

## Keep working
Pallets in group `pallets` unchanged. Carried pallet has no collision, so it never breaks. Delivered pallets leave the group.

## Test
`tests/smoke.gd` (headless): spawn main scene, run 300 frames, crash forklift into David, pallet, crate, barrel; check MESS > 0, no script errors.
