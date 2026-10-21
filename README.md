# Forklift Yard

A small Godot 4.6 warehouse-yard game. Walk to the forklift, pick up pallets from INBOUND, and deliver them to the bay on your job ticket. Bay C is up the ramp on the dock.

## Play (Windows)

Download `ForkliftYard-win64.zip` from the [Releases](../../releases) page, unzip it and run `ForkliftYard.exe`.

## Controls

| Key | On foot | In the forklift |
|---|---|---|
| W A S D | walk | W/S throttle, A/D steer |
| Shift | run | |
| Space | jump | brake |
| E | get in the forklift | get out |
| R / F | | raise / lower forks |
| Mouse | orbit camera | orbit camera |
| Wheel | zoom | |
| Esc | free the mouse | |

Slide the forks under a pallet and raise them to pick it up. Lower the forks all the way to set it down.

## Run from source

Open the folder in Godot 4.6 and press play.

## Mess with it

Everything is in `scripts/`: `forklift.gd` (driving), `level.gd` (the yard and job tickets), `player.gd` (the walker). Fork it and break it.

Made by Crystal Frog Games.
