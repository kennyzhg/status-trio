# Battery ring top slot (issue #274)

The top gap of the battery ring used to always carry the battery status
(percentage, bolt or plug). A Mac with no internal battery — Mac mini, Mac
Studio, Mac Pro, iMac — has no level, so it showed a placeholder `100` that
carried no information. **Settings › Battery › Top Slot** now decides what the
gap shows. The ring itself always stays; only the gap content changes.

| Choice | Mac with a battery | Mac with no battery |
| --- | --- | --- |
| **Automatic** (default) | battery status (unchanged) | hidden: the gap closes into a full ring |
| **Battery** | battery status | the historical `100` |
| **Hidden** | closed gap; the arc still shows the level | closed full ring |
| **Power (Watts)** | fresh integer watts; battery status while no fresh reading | fresh integer watts; `--` while no fresh reading |
| **Watts on Power, % on Battery** | watts while connected to power, the battery status on battery | always watts (a desktop is always on power) |

- Battery presence comes from the runtime IOKit snapshot
  (`BatteryStatus.isPresent`), never from a model list. Any explicit choice
  overrides the automatic result.
- Power reuses the shared `PowerSamplingService` and the same rules as the
  centre power slot (`docs/power-center-slot.md`): integer watts, clamped to
  `0...999`, only while fresh, never a fake `0`, never an invented percentage.
  `StatusBarController` registers the single `icon` demand while the centre
  slot is Power or the top slot resolves to Power; `.automatic` never samples,
  and the adaptive choice releases the sampler while the Mac runs on battery.
- With the top slot replaced (Power), the **charging status inside the ring**
  centre mode (#253) no longer closes the gap, because the gap no longer shows
  the battery status that mode moved to the centre.
- The value is part of `BatteryIconOptions`, so it reaches the menu bar and the
  Dock through the same `IconSceneState`; the Dock render key needs no new input.
- The Icon Guide always draws the battery gap, because that is what it explains.

## Verification status

- Unit coverage: `BatteryTopSlotTests` (resolution, mapper output for each
  choice on battery and no-battery Macs, stale/missing power fallback, the #253
  interaction, persistence and the appearance publisher).
- **NOT RUN**: a real Mac mini runtime check and a live UI check of the new
  Settings row.
