# dumbgame

A physics-based medieval sword fighting game in **Godot 4.7**, in the spirit
of Half Sword. Every fighter is an active ragdoll: nothing is animated, you
drag your weapon through the air with the mouse, and hits land with real
momentum. Cuts bleed, limbs can come off, and you can trip, stumble and get
knocked down.

This build has one fighter, a dirt fighting pit, a sparring partner in a
kettle hat and padded jack, and a longsword.

![Cutting at the sparring partner](docs/screenshot.png)

## Playing it

- **Download:** grab the Windows or Linux build from the
  [latest release](https://github.com/kierbob/dumbgame/releases/tag/latest),
  unzip it and run it. Every push to `main` rebuilds it automatically.
- **From source:** install [Godot 4.7](https://godotengine.org/download),
  click **Import**, pick this folder's `project.godot` and press **F5**.

## Controls

| Input | Action |
| --- | --- |
| Click | Capture the mouse |
| Mouse | Look and turn |
| **Hold left mouse** | **Drag your sword arm.** Wind up, then sweep through |
| **Hold right mouse** | Half-sword grip: off hand grabs the blade for more control and less reach |
| Alt or middle mouse (hold) | Bring the point in line with the crosshair, then push the mouse forward to thrust |
| Scroll wheel | Reach in or out |
| Q / E | Roll the blade (edge or flat) |
| C | Back to guard |
| WASD | Move |
| Shift | Sprint (tap it while moving to dodge) |
| Ctrl | Crouch |
| Space | Kick |
| Tab | Lock on to your opponent |
| V | First person |
| T | New sparring partner |
| R | Respawn |
| F (hold) | Go limp |
| H | Hide the controls |
| Esc | Free the mouse |

## How fighting works

- **Weight.** The sword is a 1.5 kg physics object held in a physics hand.
  Moving the mouse moves where your fist wants to be, and your arm muscles
  have to haul the blade there. Big strokes need a wind-up and carry through.
  Swinging wildly costs balance.
- **Edge alignment.** The edge turns to face the direction of your stroke on
  its own. A clean edge-on hit is a **cut**. Roll the blade with Q/E and you
  slap with the flat instead (a **blow**). Point-first hits are **stabs**.
- **Wounds.** Damage comes from impact energy (½·m·v²). Cuts and stabs
  bleed, and a bleeding fighter weakens as blood runs out. Hurt limbs lose
  muscle strength and go limp. A hard enough cut severs a limb at the joint.
  Losing a leg takes you down for good. A ruined head or torso, or bleeding
  out, kills.
- **Armour.** The kettle hat stops almost any cut to the head (you hear the
  clang), though a hard blow still rings the wearer's bell. The padded jack
  soaks up part of every cut to the torso and upper arms, and less of a thrust.
- **Footwork.** Feet plant on the ground and step when your body drifts off
  them, so shoves, kicks and heavy swings turn into stumbling. Tip over far
  enough and you go down, then drag yourself back up.

The panel in the top-left shows the sparring partner's wounds: parts shade
red as they're hurt, outlined parts are bleeding, and crossed-out parts are
gone.

## Code

Everything is in `scripts/`:

- **`active_ragdoll.gd`** is the core fighter. It builds 11 `RigidBody3D`
  body parts joined by `PinJoint3D`s and drives them with PD "muscles": a
  hover spring at the hips, capped balance torques, two-bone IK for arms and
  legs, planted-foot stepping, kicks, dodges, the grip and wrist that drive a
  weapon, and the whole wound model (bleeding, limp limbs, severing, death).
- **`player.gd`** maps mouse and keyboard onto the fighter: arm drag on a
  sphere around the shoulder, edge alignment, half-sword stance and thrusts.
- **`dummy.gd`** is the sparring partner: same fighter, fists up, faces you,
  walks back to its spot.
- **`sword.gd`** is the longsword. It reports hits with speed, edge and point
  alignment, and makes a whoosh that follows the tip speed.
- **`gore.gd`** handles blood sprays, dripping wounds and blood stains
  (decals on bodies and the ground).
- **`looks.gd`** holds procedural materials (dirt, wood, straw, steel, cloth,
  skin) made from noise, so no texture files are needed.
- **`sfx.gd`** synthesises the steel clang, cut and thud sounds.
- **`arena.gd`**, **`camera_rig.gd`**, **`hud.gd`** and **`main.gd`** cover
  the pit, the camera, the HUD and the wiring.

Physics runs at 120 Hz on Jolt.

### Tuning

The Player and Dummy nodes expose their feel in the inspector: movement,
balance and muscle strength, grip and wrist strength, how much a swing costs
in balance, knockdown thresholds, blood and severing damage. The outfit
(colours, helmet, padding) is set there too.

## Assets

See [CREDITS.md](CREDITS.md). Almost everything is generated in code.
