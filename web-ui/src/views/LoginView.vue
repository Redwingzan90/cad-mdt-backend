<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";

const router = useRouter();
const authStore = useAuthStore();

const username = ref("");
const password = ref("");
const showPassword = ref(false);

async function handleLogin() {
  if (!username.value || !password.value) return;

  try {
    await authStore.login(username.value, password.value);
    router.push("/dashboard");
  } catch {
    // Error is handled by the store
  }
}
</script>

<template>
  <div class="h-full flex items-center justify-center bg-dark-950 overflow-hidden">
    <!-- Background pattern -->
    <div class="fixed inset-0 opacity-5">
      <div
        class="absolute inset-0"
        style="
          background-image: radial-gradient(circle at 1px 1px, white 1px, transparent 0);
          background-size: 40px 40px;
        "
      />
    </div>

    <div class="relative w-full max-w-md mx-4">
      <!-- Logo -->
      <div class="text-center mb-8">
        <div class="text-6xl mb-4">🛡️</div>
        <h1 class="text-2xl font-bold text-white">Police CAD/MDT</h1>
        <p class="text-dark-400 mt-1">Computer Aided Dispatch System</p>
      </div>

      <!-- Login Card -->
      <div class="card p-8">
        <form @submit.prevent="handleLogin" class="space-y-5">
          <!-- Error Message -->
          <div
            v-if="authStore.error"
            class="p-3 rounded-lg bg-red-500/10 border border-red-500/30 text-red-400 text-sm"
          >
            {{ authStore.error }}
          </div>

          <!-- Username -->
          <div>
            <label class="block text-sm font-medium text-dark-300 mb-1.5">Username</label>
            <input
              v-model="username"
              type="text"
              class="input"
              placeholder="Enter your username"
              autocomplete="username"
              autofocus
            />
          </div>

          <!-- Password -->
          <div>
            <label class="block text-sm font-medium text-dark-300 mb-1.5">Password</label>
            <div class="relative">
              <input
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                class="input pr-10"
                placeholder="Enter your password"
                autocomplete="current-password"
              />
              <button
                type="button"
                @click="showPassword = !showPassword"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-dark-500 hover:text-dark-300"
              >
                <svg v-if="!showPassword" class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                    d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                </svg>
                <svg v-else class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                    d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
                </svg>
              </button>
            </div>
          </div>

          <!-- Submit -->
          <button
            type="submit"
            :disabled="authStore.loading || !username || !password"
            class="btn-primary w-full py-3 text-base font-semibold"
          >
            <span v-if="authStore.loading" class="flex items-center justify-center gap-2">
              <svg class="animate-spin h-4 w-4" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none" />
                <path class="opacity-75" fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
              Signing in...
            </span>
            <span v-else>Sign In</span>
          </button>
        </form>
      </div>

      <p class="text-center text-dark-500 text-xs mt-6">
        Secure connection • Authorized personnel only
      </p>
    </div>
  </div>
</template>
