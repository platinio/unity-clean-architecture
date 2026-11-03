using UnityEngine;

namespace Game.Combat
{
    public sealed class HitReaction : MonoBehaviour
    {
        [SerializeField] private Animator animator;
        [SerializeField] private Health health;

        private CharacterState current;

        public void Apply(HitInfo hit)
        {
            if (health?.IsDead == true)
            {
                return;
            }

            if (current is KnockedDownState)
            {
                return;
            }

            if (current is DeadState)
            {
                return;
            }

            switch (hit.Kind)
            {
                case HitKind.Light:
                    animator.SetTrigger("Flinch");
                    health.TakeDamage(10);
                    break;
                case HitKind.Heavy:
                    animator.SetTrigger("Stagger");
                    health.TakeDamage(25);
                    break;
                case HitKind.Launch:
                    animator.SetTrigger("Launch");
                    health.TakeDamage(40);
                    break;
            }
        }

        public void SetState(CharacterState state) => current = state;
    }

    public enum HitKind { Light, Heavy, Launch }

    public readonly struct HitInfo
    {
        public readonly HitKind Kind;
        public HitInfo(HitKind kind) => Kind = kind;
    }

    public abstract class CharacterState { }
    public sealed class LocomotionState : CharacterState { }
    public sealed class KnockedDownState : CharacterState { }
    public sealed class DeadState : CharacterState { }
}
