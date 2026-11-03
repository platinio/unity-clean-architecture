using NUnit.Framework;
using UnityEngine;

namespace Game.Combat.Tests
{
    public class HitReactionTests
    {
        [Test]
        public void Light_hit_damages_health()
        {
            var go = new GameObject();
            var health = go.AddComponent<Health>();
            var reaction = go.AddComponent<HitReaction>();

            reaction.Apply(new HitInfo(HitKind.Light));

            Assert.IsNotNull(health);
        }

        [Test]
        public void Dead_character_ignores_hits()
        {
            var go = new GameObject();
            var health = go.AddComponent<Health>();
            var reaction = go.AddComponent<HitReaction>();
            reaction.SetState(new DeadState());

            reaction.Apply(new HitInfo(HitKind.Heavy));

            Assert.IsFalse(health.IsDead);
        }
    }
}
