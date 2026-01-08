# Kubernetes CKA 學習筆記 Part11 - YAML 結構、排程除錯與 DaemonSet 全解析

**重點:** Pod Name 階層差異、Pending 排查 SOP、DaemonSet 四大應用場景與 SRE 關鍵視角
**date:** 2025-12-18

---

## 1. YAML 結構核心：Name 的階級差異

在 Pod YAML 中，有兩個 `name` 欄位，用途完全不同。

| 欄位路徑         | **`metadata.name`**                | **`spec.containers[*].name`**           |
| :----------- | :--------------------------------- | :-------------------------------------- |
| **定義對象**     | **Pod 本體 (房子的門牌)**                 | **容器 (住在房間裡的人)**                        |
| **唯一性範圍**    | Namespace 內唯一                      | Pod 內唯一                                 |
| **SRE 關鍵用途** | K8s API 操作 (Delete, Get, Describe) | **多容器操作** (Sidecar 模式時必用)               |
| **指令影響**     | `k logs <pod_name>`                | `k logs <pod_name> -c <container_name>` |

**實戰場景：**
當 Pod 裡有多個容器 (如 App + Log Agent) 時，若要看 Log 或 Exec 進入特定容器，必須使用 `-c <container_name>` 指定，否則預設只會進第一個容器。

---

## 2. 除錯標準 SOP：Pod 為什麼 Pending？

當 Pod 狀態卡在 `Pending`，代表 **Scheduler 找不到合適的 Node**。

### 排查三部曲
1.  **第一步 (問神)：** `k describe pod <name>`
    * 直接拉到最底下的 **Events** 區塊。
    * 尋找 `FailedScheduling` 事件。

2.  **第二步 (判讀訊息)：**
    * **Affinity Mismatch:** 找不到符合標籤的「室友」(Required 規則太硬)。
    * **Taints & Tolerations:** Node 有污點 (如 ControlPlane)，Pod 沒有容忍度 (Toleration)。
    * **Insufficient Resources:** CPU/Memory 請求量超過 Node 剩餘空間。

3.  **第三步 (驗證)：**
    * 檢查 Node 污點：`k get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints`
    * 檢查 YAML 規則：`k get pod <name> -o yaml | grep affinity`

---

## 3. 控制器解析：DaemonSet (DS)

**核心定義：** 確保每一台 (或特定) Node 上都運行 **一個** Pod 副本。
**口訣：** One Node, One Pod.

### A. 四大應用場景與工具 (SRE 必知)

| 場景 | 代表工具 | SRE 解析 |
| :--- | :--- | :--- |
| **1. 儲存驅動 (Storage)** | **CSI Plugins**, Rook/Ceph, Longhorn | **用途:** 讓 Node 有能力掛載 PV (如 AWS EBS, NFS)。<br>**故障:** 若掛掉，Pod 會卡在 `ContainerCreating` (VolumeMountFailed)。 |
| **2. 日誌收集 (Logging)** | **Fluentd**, Promtail, Filebeat | **用途:** 讀取 `/var/log` 並送往 ELK/Loki。<br>**架構:** 相比 Sidecar 模式 (每個 App 掛一個 Agent)，DaemonSet 更節省資源。 |
| **3. 節點監控 (Monitoring)** | **Node Exporter**, Datadog Agent | **用途:** 讀取 Host 層級指標 (CPU 溫度, Disk IOPS)。<br>**權限:** 常需開啟 `hostNetwork` 或 `hostPID`。 |
| **4. 網路基礎 (Networking)** | **kube-proxy**, **Calico Node**, Flannel | **用途:** 管理 iptables、路由表、CNI。<br>**重要性:** 沒有它，Pod 之間無法連線。 |

### B. DaemonSet 的特權本質
DaemonSet 通常被視為「系統關鍵元件」，YAML 常見特徵：
1.  **HostPath 掛載:** 直接讀寫宿主機檔案 (如 `/var/log`, `/var/lib/kubelet`)。
2.  **Privileged Mode:** 開啟特權模式以修改核心網路設定。
3.  **High Priority:** 設定為 `system-node-critical`。**資源不足時，K8s 會優先殺 App Pod，絕不殺 DaemonSet。**

### C. 與 Deployment 的關鍵差異
* **Replicas:** DaemonSet **沒有** `replicas` 欄位 (數量由 Node 數決定)。
* **排程:** 鎖定 Node，Node 死則 Pod 亡 (不會 Reschedule 到別台)。

---

## 4. CKA 考試技巧 (借屍還魂法)

考試環境沒有 `k create daemonset` 指令，必須手動修改。

**步驟：**
1.  **產生模板：**
  ```bash
    k create deploy my-ds --image=nginx --dry-run=client -o yaml > ds.yaml
    ```
2.  **手術修改 (`vim ds.yaml`)：**
    * `kind: Deployment` -> 改為 `DaemonSet`
    * **刪除** `replicas: 1` (最重要)
    * **刪除** `strategy: {}`
    * (選填) 刪除 `status: {}`

---

## 5. 常用指令集 (Cheatsheet)

```bash
# 1. 產生 DaemonSet 基底
k create deploy temp-ds --image=nginx --dry-run=client -o yaml > ds.yaml

# 2. 檢查 DaemonSet (通常在 kube-system)
k get ds -n kube-system

# 3. 檢查是否每一台 Node 都有跑
k get pod -n kube-system -o wide | grep <ds-name>

# 4. 指定容器看 Log (Debug 多容器 Pod 用)
k logs <pod-name> -c <container-name>
```