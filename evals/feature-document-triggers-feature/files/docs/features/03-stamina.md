# 03 Stamina

The player has stamina. Dodging drains it by a configurable amount; it regenerates per second while the
player is idle. The HUD flashes when it reaches zero. The brute enemy has stamina too, with its own values.

## Design

- Owning component: `Stamina` on the character, a thin wrapper over a plain `StaminaMeter` class.
- Tunables (`maxStamina`, `dodgeCost`, `regenerationPerSecond`) live in the character's `Stance` asset.
- Cross-system reactions: `OnStaminaDepleted` and `OnStaminaRestored` Hermes events carrying the GameObject.
- No pattern beyond the component itself.
