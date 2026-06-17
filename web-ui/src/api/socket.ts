import { io, type Socket } from "socket.io-client";
import { ref } from "vue";

const SOCKET_URL = import.meta.env.VITE_SOCKET_URL || window.location.origin;

let socket: Socket | null = null;
const isConnected = ref(false);

export function getSocket(): Socket {
  if (!socket) {
    const token = localStorage.getItem("cad_token") || "";

    socket = io(SOCKET_URL, {
      auth: { token },
      transports: ["websocket", "polling"],
      reconnection: true,
      reconnectionAttempts: 10,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 5000,
      timeout: 20000,
    });

    socket.on("connect", () => {
      isConnected.value = true;
      console.log("[Socket] Connected");
    });

    socket.on("disconnect", (reason) => {
      isConnected.value = false;
      console.log("[Socket] Disconnected:", reason);
    });

    socket.on("connect_error", (err) => {
      console.error("[Socket] Connection error:", err.message);
    });
  }

  return socket;
}

export function disconnectSocket() {
  if (socket) {
    socket.disconnect();
    socket = null;
    isConnected.value = false;
  }
}

export { isConnected };
