# Kubernetes CKA 學習筆記 Part23 - Advanced Debugging & Scheduling Logic

**重點:** Pod Lifecycle, Kubelet Debugging, Resource Management (QoS/Preemption), JSONPath Strategy  
**date:** 2026-01-27  
**range:** 2026-01-15 ~ 2026-01-27

---

## 1. 故障排查核心邏輯 (Troubleshooting Methodology)

### A. Pod 啟動失敗分析
* **Exit Code 127:** 代表 `Command Not Found`。
    * **主因:** Pod `args` 覆蓋了 Image 的 `ENTRYPOINT`，導致執行了不存在的指令（如將 Pod 名稱誤填入 args）。
* **CreateContainerConfigError:**
    * **現象:** `log.txt` 為空，無法使用 `kubectl logs`。
    * **原因:** 容器死在「配置階段」（ConfigMap/Secret 缺失或 Key 錯誤），Process 尚未啟動，故無 stdout。
    * **解法:** 必須使用 `kubectl describe pod` 查看 Events。
* **Port 衝突 (Address in use):**
    * **現象:** `(98)Address in use`。
    * **誤區:** 修改 YAML 的 `containerPort` 無效（那是 Metadata）。
    * **正解:** 必須修改應用程式的啟動參數（`args` 或 `env`），或使用 ConfigMap 覆寫設定檔。
    * **工具:** `ss -tulpn` (查 PID), `fuser -k` (殺 Process)。
* **Multi-Container Debug:**
    * **關鍵:** 當 Pod 狀態為 `1/2 Running` 時，`logs` 預設顯示活著的那個。
    * **指令:** 必須指定 `-c`，例如 `k logs <pod> -c <dead-container>`。

### B. Deployment 的資訊隔離 (Visibility Gap)
* **Deployment 層:** 只負責 ReplicaSet 的數量管理（Events 顯示 Scaled up）。
* **Pod 層:** 負責實際執行。
* **SRE 觀點:** Deployment 顯示 Available=0 時，無法從 Deployment `describe` 看到死因，必須往下挖到 Pod 層級。

### C. Kubelet 故障 (Systemd Chain)
* **錯誤特徵:** `unknown flag: --improve-speed`。
* **根源分析:** Kubelet 啟動參數由 Systemd 組合而成。
    * `/var/lib/kubelet/kubeadm-flags.env` (Kubeadm 自動生成)
    * `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` (外掛設定)
* **修復 SOP:** 找到並刪除錯誤 Flag $\rightarrow$ `systemctl daemon-reload` $\rightarrow$ `systemctl restart kubelet`。

---

## 2. 資源管理與調度 (Resource & Scheduling)

### A. 資源限制層級 (The Hierarchy)
* **Request (訂位):** 決定 Pod **能否被調度**。若 Node Allocatable < Request，則 Pending。
* **Limit (天花板):** 決定 Pod **能否存活**。超過 Memory Limit 會被 OOMKilled；超過 CPU Limit 會被 Throttling。
* **QoS 階級制度:**
    1.  **Guaranteed:** Request = Limit (VIP，最後殺)。
    2.  **Burstable:** Request < Limit (平民)。
    3.  **BestEffort:** 未設定 (賤民，資源不足時優先處決)。

### B. 資源不足與搶佔 (Capacity & Preemption)
* **場景:** Node 還有空間，但新 Pod 卻 Pending？可能是 Namespace Quota 限制。
* **場景:** Namespace 無 Quota，但新 Pod Pending？那是 Node 物理空間不足 (Allocatable Memory 用盡)。
* **解決:** 使用 **PriorityClass**。
    * 設定高優先級 (`value` 較大) 的 Pod，可觸發 Scheduler 的 **Preemption (搶佔)** 機制，驅逐 (Evict) 低優先級 Pod 以騰出空間。

### C. 監控指令辨析
* **`kubectl top node`:** 查看 **實際使用量 (Usage)** (需 Metrics Server)。
* **`kubectl describe node`:** 查看 **帳面預訂量 (Request/Limit)** (非當下負載)。
* **`df -h`:** 查看 **硬碟** 空間，與 CPU/Memory 無關。

---

## 3. Kubernetes 物件與策略 (Objects & Policies)

### A. 物件不可變性 (Immutability)
* Pod 建立後，除了 `image`, `activeDeadlineSeconds`, `tolerations` 等少數欄位外，**規格 (Spec)** 不可修改。
* **VolumeMounts 陷阱:** 修改 MountPath 屬於結構變更，必須重建 Pod (`replace --force`)。
* **Literal 陷阱:** `mountPath: /etc/*` 會建立一個名為 `*` 的目錄，而非萬用字元。

### B. 版本偏差策略 (Version Skew Policy)
* **kubectl (Client):** 可比 Server 新或舊 1 個版本 (+/- 1 Minor)。
* **kubelet (Node):** **絕對不能**比 API Server 新 (只能舊)。升級順序：Control Plane $\rightarrow$ Nodes。

### C. Kubeadm Token
* **`token generate`:** 離線產生亂數格式字串（無效，需再註冊）。
* **`token create`:** 線上向 API Server 註冊 Secret（有效，可直接 Join）。

### D. YAML 結構解析
* **兩層 Spec:**
    * 外層 `spec`: Deployment 的策略 (Replicas, Selector)。
    * 內層 `template.spec`: Pod 的實體 (Containers, Volumes)。
* **Selector & Template:** 兩者標籤必須一致，且為 Deployment 必要欄位。
* **Label Selector:**
    * `operator: In`: 白名單包含 (`values` 為 OR 邏輯陣列)。

---

## 4. CLI 高效技巧 (Efficiency)

### A. 指令生成 (Imperative)
* **ConfigMap/Secret:** `--from-literal=key=value` (自動 Base64 編碼，考試神器)。
* **CronJob:** 注意 `--` 分隔符，區分 `kubectl` 參數與 Container 指令。

### B. 輸出排序
* **Linux `sort`:** 當欄位包含空白 (如 `RESTARTS: 2 (10m ago)`) 時會失效。
* **K8s Native:** 使用 `--sort-by` 搭配 JSONPath。
    * **查路徑法:** `k get pod <name> -o yaml` 逆向推導層級。
    * **範例:** `--sort-by=.spec.nodeName` 或 `--sort-by=.status.podIP`。