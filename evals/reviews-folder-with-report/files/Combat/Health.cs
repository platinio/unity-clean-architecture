using System;
using UnityEngine;

namespace Game.Combat
{
    public sealed class Health : MonoBehaviour
    {
        [SerializeField] private int maxHealth = 100;

        private int currentHealth;

        public event Action Died;

        public bool IsDead => currentHealth <= 0;

        private void Awake() => currentHealth = maxHealth;

        public void TakeDamage(int amount)
        {
            currentHealth -= amount;
            if (currentHealth <= 0)
            {
                Died?.Invoke();
            }
        }
    }
}
