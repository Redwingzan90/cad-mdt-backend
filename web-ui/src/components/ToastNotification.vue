<script setup lang="ts">
import type { Notification } from "@/stores/notifications";

const props = defineProps<{
  notification: Notification;
}>();

const emit = defineEmits<{
  close: [];
}>();

const typeIcons: Record<string, string> = {
  NEW_CALL: "🚨",
  BOLO_ALERT: "⚠️",
  WARRANT_ALERT: "📋",
  DISPATCH: "🚨",
  EVIDENCE: "🔍",
  REPORT: "📝",
  DEFAULT: "🔔",
};

const priorityConfig: Record<string, { class: string; glow: string }> = {
  URGENT: { class: "border-l-red-500 bg-red-500/[0.08]", glow: "shadow-red-500/20" },
  HIGH: { class: "border-l-orange-500 bg-orange-500/[0.08]", glow: "shadow-orange-500/20" },
  NORMAL: { class: "border-l-blue-500 bg-blue-500/[0.08]", glow: "shadow-blue-500/20" },
  LOW: { class: "border-l-slate-500 bg-slate-500/[0.08]", glow: "shadow-slate-500/20" },
};

const icon = typeIcons[props.notification.type] || typeIcons.DEFAULT;
const config = priorityConfig[props.notification.priority] || priorityConfig.NORMAL;
</script>

<template>
  <div
    class="border-l-4 rounded-xl p-4 shadow-2xl animate-slide-in cursor-pointer backdrop-blur-xl border border-white/[0.06] min-w-[320px] transition-all duration-200 hover:scale-[1.02]"
    :class="[config.class, config.glow]"
    @click="emit('close')"
  >
    <div class="flex items-start gap-3">
      <div class="w-8 h-8 rounded-lg bg-white/[0.06] flex items-center justify-center text-base flex-shrink-0">
        {{ icon }}
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-white truncate">{{ notification.title }}</p>
        <p class="text-xs text-dark-300 mt-1 line-clamp-2 leading-relaxed">{{ notification.message }}</p>
      </div>
      <button
        @click.stop="emit('close')"
        class="text-dark-500 hover:text-dark-200 flex-shrink-0 transition-colors p-1 rounded-lg hover:bg-white/[0.06]"
      >
        <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  </div>
</template>
