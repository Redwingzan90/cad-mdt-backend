import axios, { type AxiosInstance, type AxiosResponse, type InternalAxiosRequestConfig } from "axios";

const API_BASE = import.meta.env.VITE_API_URL || "/api";

const api: AxiosInstance = axios.create({
  baseURL: API_BASE,
  timeout: 15000,
  headers: {
    "Content-Type": "application/json",
  },
});

// Request interceptor: attach auth token
api.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const token = localStorage.getItem("cad_token");
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Response interceptor: handle errors
api.interceptors.response.use(
  (response: AxiosResponse) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem("cad_token");
      window.location.hash = "#/login";
    }
    return Promise.reject(error);
  }
);

export default api;
