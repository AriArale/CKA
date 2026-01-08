# Kubernetes CKA 學習筆記 Part1 - 備考指南與學習筆記

**目標：** 2026/01/30 考取 CKA (Certified Kubernetes Administrator)  
**角色視角：** SRE / DevOps Engineer
**date:** 2025-12-03

---
## 1. CKA 備考計劃 (9週衝刺)

### 考試重點配分 (2025 新制)
* **Troubleshooting (30%)** - *最高優先級*
* **Installation & Configuration (25%)** - *含 Cluster Upgrade, Etcd Backup*
* **Services & Networking (20%)**
* **Workloads & Scheduling (15%)**
* **Storage (10%)**
* **新考題：** Helm, Kustomize

### 學習策略
1.  **Imperative > Declarative：** 考試講求速度，能用 `kubectl run` 或 `create deployment` 生成的，絕不手寫 YAML。
2.  **肌肉記憶：** 每日 19:00-21:00 練習 (Killercoda / Killer.sh)。
3.  **抓大放小：** 優先保證 Troubleshooting 和 Cluster Maintenance 的分數。

### 階段規劃
* **Phase 1 (架構與安裝):** `kubeadm upgrade`, Etcd Backup, Helm/Kustomize 基本操作。
* **Phase 2 (工作負載):** Deployment, Scheduling (Affinity/Taints)。
* **Phase 3 (網路與存儲):** Ingress, NetworkPolicy, PV/PVC。
* **Phase 4 (故障排除):** 專攻 Node NotReady, Pod CrashLoop, Service Unreachable。

---

## 2. Pod 與多容器架構 (Multi-Container Pods)

### 基本概念
* **定義：** Pod 是邏輯主機 (Logical Host)，裡面可以運行多個 Container。
* **共享資源：**
    * **Network:** 共享 IP，透過 `localhost` 通訊 (注意 Port 不能衝突)。
    * **Storage:** 透過 Volume 共享檔案。
    * **Lifecycle:** 同生共死。

### 設計模式 (Design Patterns)
* **Sidecar (最常見):** 輔助主程式 (例：Log 收集 agent, Service Mesh proxy)。
* **Adapter:** 轉換輸出格式 (例：轉成 Prometheus metric)。
* **Ambassador:** 代理外部連線 (例：DB Proxy)。

---

## 3. 核心架構：Node vs Namespace vs Cluster

這是 K8s 架構的「二維矩陣」觀念。

| 層級                  | 定義                      | SRE 觀點 (作用)                                  |
| :------------------ | :---------------------- | :------------------------------------------- |
| **Node (物理層)**      | 提供算力 (CPU/RAM) 的實體機器。   | 決定 Pod 跑在「哪裡 (Where)」。<br>關注硬體健康、Capacity。   |
| **Namespace (邏輯層)** | 提供隔離 (Name/RBAC) 的虛擬空間。 | 決定 Pod 「歸誰管 (Who)」。<br>關注權限、配額、避免名稱衝突。       |
| **Cluster (邊界)**    | 包含多個 Node 的完整環境。        | **硬隔離**。用於區分 Dev/Prod，控制爆炸半徑 (Blast Radius)。 |

### 關鍵釐清
1.  **調度 (Scheduling):** Scheduler 預設不看 Namespace，只看 Node 資源。若要指定位置需用 `nodeSelector` 或 `Affinity`。
2.  **核心風險 (Kernel Panic):** Namespace 無法隔離共享 Kernel 的風險。若同一 Node 上某 Pod 導致 Kernel 崩潰，該 Node 上所有 Namespace 的 Pod 都會死。
3.  **API Server 數量:** 標準 `kubeadm` 安裝中，因佔用 Host Port 6443，通常 **一台 Node 只跑一個 API Server**。

### a. 視覺化模型：經緯度 / Excel 表格

想像一個 Excel 表格：

- **直行 (Columns) 是 Nodes (物理/實體層)：** 代表硬體資源（Node A, Node B, Node C）。
- **橫列 (Rows) 是 Namespaces (邏輯/管理層)：** 代表專案分組（Dev, Prod, Test）。
- **儲存格 (Cells) 是 Pods：** 每個 Pod 必然同時落在某個直行和某個橫列的交界處。

|                           | **Node 1 (實體機器 A)**        | **Node 2 (實體機器 B)**        |
| :------------------------ | :------------------------- | :------------------------- |
| **Namespace: Prod (生產組)** | **Pod A** (Prod組的程式，跑在機器A) | **Pod B** (Prod組的程式，跑在機器B) |
| **Namespace: Dev (開發組)**  | **Pod C** (Dev組的程式，跑在機器A)  | **Pod D** (Dev組的程式，跑在機器B)  |

- **Pod A 和 Pod C：** 它們是**物理上的鄰居**（都在 Node 1，共享 CPU/Kernel），但**邏輯上不認識**（不同 Namespace）。    
- **Pod A 和 Pod B：** 它們是**邏輯上的同事**（都屬 Prod，可以互叫名字），但**物理上分隔兩地**（不同 Node）。

---

### b. 深入解析：物理 vs 邏輯的作用

您說的「差別在於物理及邏輯」是完全正確的，我們把它對應到 Kubernetes 的管理指令上：

#### **Node (物理層級 - Physical)**

- **管的是「力氣」：** CPU、Memory、Disk、GPU。
- **SRE 關心的問題：**
    - 這台機器還擠得下新 Pod 嗎？ (Capacity Planning)
    - 這台機器硬碟是不是快壞了？ (Hardware Health)
    - 這台機器核心版本是不是太舊？ (OS Upgrade)
- **對應指令：** `kubectl top node` (看誰負載高)

#### **Namespace (邏輯層級 - Logical)**

- **管的是「規矩」：** 權限 (RBAC)、配額 (Quota)、名稱 (DNS)。
- **SRE 關心的問題：**
    - 開發組的人有沒有權限誤刪生產組的 Pod？ (Access Control)
    - 測試組會不會把整個 Cluster 的資源額度用光？ (Resource Quota)
    - 這兩個服務的名字會不會衝突？ (Naming)
- **對應指令：** `kubectl create rolebinding` (給權限)

---

### c. 為什麼說它們「不是」同一個層級？

如果硬要比喻，它們在 Cluster 底下確實都是「一級公民」，但它們的**生命週期**和**相依性**不同：

1. **相依性：**
    - **沒有 Node，Pod 跑不起來**（有魂無體）。
    - **沒有 Namespace，Pod 根本無法被定義**（連出生證明都開不出來，因為每個 Pod 建立時預設就在 `default` Namespace 裡）。
    
2. **管理權責：**
    - **Node** 通常歸 **「基礎設施團隊 (Infra Team)」** 管（管機房、虛擬機）。
    - **Namespace** 通常歸 **「平台工程團隊 (Platform Team)」** 管（管切分給哪個 App 團隊用）。

### 小結

您的理解修正如下會更完美：

> **Node 和 Namespace 是構成 Cluster 的兩個「互相垂直的維度」。**
> 
> - **Node (物理維度)：** 提供硬體資源，解決「跑在哪裡」的問題。
> - **Namespace (邏輯維度)：** 提供隔離邊界，解決「屬於誰、受誰限制」的問題。

在 CKA 考試中，會發現這一點很明顯：

- 當您要**修機器**（Upgrade, Backup）時，您看的是 **Nodes**。
- 當您要**修服務**（Network Policy, ServiceAccount）時，您看的是 **Namespaces**。

---

## 4. 資源物件：Deployment & ConfigMap

### Deployment (指揮官)
* **職責：** 管理 ReplicaSet，進而管理 Pod。
* **功能：** 自動復活 (Self-healing)、彈性伸縮 (Scaling)、滾動更新 (Rolling Update)。
* **檔案位置：** 存於 **Etcd 資料庫** 中，而非 Node 的檔案系統 (Static Pod 除外)。

### ConfigMap (設定檔)
* **目的：** 解耦 (Decoupling)。程式碼 (Image) 不變，透過 ConfigMap 改變行為 (Feature Toggle, DB Connection)。
* **使用方式：**
    * 注入為環境變數 (`valueFrom`).
    * 掛載為檔案 (`volumeMounts`).
* **Scope (作用域):** **Namespace Level**。Pod 只能讀取同一個 Namespace 下的 ConfigMap。

### ConfigMap 除錯
* **狀態：** `CreateContainerConfigError` 通常代表 ConfigMap 不存在或 Key 寫錯。
* **驗證指令：** `k get cm <name> -o yaml` 確認 `data` 區塊內的 Key 是否與 Pod YAML 吻合。

---

## 5. Troubleshooting (故障排除實戰)

### Log 分析原則
* **忽略雜訊：** Lab 環境常見的 `xfce`, `lightdm`, `cloud-init`, `systemd` 錯誤通常可忽略。
* **關注重點：** 搜尋 `kubelet`, `apiserver`, `containerd` 相關錯誤。

### API Server 故障 (`connection refused: 6443`)
* **現象：** `kubectl` 沒反應，`connection refused`。
* **連鎖反應：** `calico-kube-controllers` 等元件會因為連不上 API Server 而 CrashLoopBackOff。
* **SOP：**
    1.  `systemctl status kubelet` (檢查 Kubelet)。
    2.  `crictl ps | grep apiserver` (檢查容器是否活著)。
    3.  **檢查 `/etc/kubernetes/manifests/kube-apiserver.yaml`** (最常見考題：打錯字、路徑錯)。

### Port 衝突 (Port Conflict)
* **情境 A：Service NodePort 衝突**
    * 錯誤：`nodePort: 30005 provided port is already allocated`。
    * 解法：修改 Service YAML，換一個沒人用的 NodePort (如 30006)。
* **情境 B：Pod Bind Port 衝突 (Address already in use)**
    * 錯誤：Pod Crash，Log 顯示 Port 被佔用。
    * 解法：
        1.  修改 **Deployment** (透過 `env` 或 `command` 叫 App 改聽別的 Port)。
        2.  同步修改 **Service** 的 `targetPort` 以匹配新 Port。

---

## 6. 常用指令速查 (Cheat Sheet)

Log locations to check:
- `/var/log/pods`
- `/var/log/containers`
- `crictl ps` + `crictl logs`
- `docker ps` + `docker logs` (in case when Docker is used)
- kubelet logs: `/var/log/syslog` or `journalctl` - pod 完全沒啟的時候看，搭配 grep 使用

```bash
# 設定別名與輸出 (考試第一件事)
alias k=kubectl
export do="--dry-run=client -o yaml"
sed ~/.vimrc set autoindent

# 查詢 Namespace 下的 ConfigMap
k -n <namespace> get cm

# 查詢 Namespace 下的 後端 Pod IP
k -n <namespace> get ep

# 查詢 Namespace 下的 Service IP, Port
k -n <namespace> get svc

# 匯出 Deployment YAML (備份/修改用)
k get deploy <name> -o yaml > deploy.yaml

# 檢查 Pod 為什麼起不來 (ConfigMap Key 錯誤常用)
k describe pod <pod-name>

# 檢查 Control Plane 元件 (當 API Server 掛掉時)
crictl ps -a | grep apiserver
cd /etc/kubernetes/manifests/

# always make a backup !
cp /etc/kubernetes/manifests/kube-apiserver.yaml ~/kube-apiserver.yaml.ori

# make the change
vim /etc/kubernetes/manifests/kube-apiserver.yaml

# wait till container restarts
watch crictl ps

# check for apiserver pod
k -n kube-system get pod

# seems like the kubelet can't even create the apiserver pod/container
/var/log/pods # nothing
crictl logs # nothing

# syslogs:
tail -f /var/log/syslog | grep apiserver
> Could not process manifest file err="/etc/kubernetes/manifests/kube-apiserver.yaml: couldn't parse as pod(yaml: mapping values are not allowed in this context), please check config file"

# 只列出最後 5 行
tail -5

# or:
journalctl | grep apiserver
> Could not process manifest file" err="/etc/kubernetes/manifests/kube-apiserver.yaml: couldn't parse as pod(yaml: mapping values are not allowed in this context), please check config file

```