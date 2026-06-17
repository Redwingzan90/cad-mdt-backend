import { defineStore } from "pinia";
import { ref, computed } from "vue";
import api from "@/api/client";
import { getSocket } from "@/api/socket";

export interface Notification {
  id: string;
  type: string;
  title: string;
  message: string;
  priority: string;
  read: boolean;
  createdAt: string;
  data?: any;
}

export const useNotificationStore = defineStore("notifications", () => {
  const notifications = ref<Notification[]>([]);
  const unreadCount = ref(0);
  const toasts = ref<Notification[]>([]);

  const hasUnread = computed(() => unreadCount.value > 0);

  async function fetchNotifications() {
    try {
      const { data } = await api.get("/notifications?limit=50");
      notifications.value = data.data;
    } catch {
      // Silent fail
    }
  }

  async function fetchUnreadCount() {
    try {
      const { data } = await api.get("/notifications/unread-count");
      unreadCount.value = data.count;
    } catch {
      // Silent fail
    }
  }

  async function markRead(id: string) {
    try {
      await api.patch(`/notifications/${id}/read`);
      const notif = notifications.value.find((n) => n.id === id);
      if (notif && !notif.read) {
        notif.read = true;
        unreadCount.value = Math.max(0, unreadCount.value - 1);
      }
    } catch {
      // Silent fail
    }
  }

  async function markAllRead() {
    try {
      await api.patch("/notifications/read-all");
      notifications.value.forEach((n) => (n.read = true));
      unreadCount.value = 0;
    } catch {
      // Silent fail
    }
  }

  function addToast(notification: Notification) {
    toasts.value.push(notification);
    unreadCount.value++;

    // Auto-remove toast after 8 seconds
    setTimeout(() => {
      const idx = toasts.value.findIndex((t) => t.id === notification.id);
      if (idx !== -1) toasts.value.splice(idx, 1);
    }, 8000);
  }

  function removeToast(id: string) {
    const idx = toasts.value.findIndex((t) => t.id === id);
    if (idx !== -1) toasts.value.splice(idx, 1);
  }

  function initSocketListeners() {
    const socket = getSocket();

    socket.on("notification:new", (notification: Notification) => {
      addToast(notification);
      notifications.value.unshift(notification);
    });
  }

  return {
    notifications,
    unreadCount,
    toasts,
    hasUnread,
    fetchNotifications,
    fetchUnreadCount,
    markRead,
    markAllRead,
    addToast,
    removeToast,
    initSocketListeners,
  };
});
