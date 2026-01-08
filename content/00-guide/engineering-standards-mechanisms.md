# Kubernetes CKA 學習筆記 Part18 - Kubernetes 工程規範與底層機制筆記


**重點:** Version Skew Policy, Static Pods, Systemd
**date:** 2025-01-08

---
## 1. Kubernetes 運維機制 (Operations)

### 版本偏差策略 (Version Skew Policy)
* **現象：** `kubectl` (Client) 版本比 `kube-apiserver` (Server) 新是允許的。
* **黃金法則：** 容許 **+/- 1 Minor Version** 的差異 (例如 Client 1.35 vs Server 1.34)。
* **SRE 觀點：** 這是為了支援 **叢集升級 (Cluster Upgrade)** 流程。標準 SOP 是「先升級管理工具 (Client)」，確保能兼容新舊 API，再升級 Control Plane。

### 關鍵目錄差異 (`/etc/kubernetes`)
| 路徑                     | 內容物                                  | 本質                  | SRE 類比                                                      |
| :--------------------- | :----------------------------------- | :------------------ | :---------------------------------------------------------- |
| **`/etc/kubernetes/`** | `*.conf` (admin.conf, kubelet.conf)  | **Kubeconfig (憑證)** | **識別證 (ID Card)**。組件用來證明身分並連接 API Server。                   |
| **`.../manifests/`**   | `*.yaml` (etcd.yaml, apiserver.yaml) | **Static Pod (定義)** | **DNA 藍圖**。Kubelet 透過 File Watcher 直接啟動這些 Pod，繞過 Scheduler。 |

* **實驗驗證：** 移動 manifests 裡的 yaml 檔，對應的 Control Plane Pod 會立刻消失；移回則重生。

---
## 2. Linux 系統管理基礎

### `service` vs `systemctl`
* **`service`:** 舊時代 SysVinit 的遺留產物 (Wrapper)。現代系統中，它只是轉譯指令去呼叫 systemctl。
* **`systemctl`:** Systemd (PID 1) 的原生溝通工具。
* **SRE 規範：** 強制使用 **`systemctl`**。
    * **理由：** 避免環境變數汙染、提供更完整的除錯資訊 (CGroup tree, Exit Code)、符合 K8s 生態標準。

