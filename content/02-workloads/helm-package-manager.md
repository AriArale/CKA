# Kubernetes CKA 學習筆記 Part15 - Helm 實戰、網路架構與資源監控

**重點:** `kubectl top` 監控指令、Metrics Server 架構、Helm 操作與 Pod 網路觀念
**date:** 2025/12/30

---
## 1. 資源監控：kubectl top 與 Metrics Server

這是 K8s 的「即時體檢儀」，依賴 **Metrics Server** 從 Kubelet 收集數據。

### 核心觀念
* **數據來源:** Metrics Server 定期 (預設 60s) 從 Node 上的 Kubelet (cAdvisor) 抓取 CPU/RAM 使用量。
* **特性:** **In-Memory (無狀態)**。重啟後數據歸零，且**不保存歷史紀錄** (它不是 Prometheus)。
* **用途:** 支援 `kubectl top` 指令與 **HPA (Horizontal Pod Autoscaler)** 自動擴展。

### 關鍵指令 (SRE 必備)
1.  **查 Node 負載 (基礎設施層):**
```bash
    k top node
    # 用途: 檢查是否有 Node 過勞，可能導致 Pod 被驅逐。
    ```
2.  **查 Pod 總量 (應用層):**
```bash
    k top po
    # 顯示 Pod 內「所有 Container 的加總」。
    ```
3.  **查 Container 明細 (除錯層 - 殺手鐧):**
```bash
    k top po <pod-name> --containers
    # 用途: 當 Pod OOM 時，抓出是主程式還是 Sidecar (Log Agent) 在吃記憶體。
    # 驗證: Pod Total Usage ≈ Sum(Container Usages)。
    ```
4.  **快速排序 (篩選):**
```bash
    k top po --sort-by=cpu     # 抓 CPU 怪獸
    k top po --sort-by=memory  # 抓 RAM 怪獸
    ```

---
## 2. Helm: Kubernetes 的包裝管理員

### 核心價值
解決 Kubernetes YAML 檔案過多 (Deployment + Service + CM + SA...) 管理困難的問題。將多個關聯的 YAML 打包成一個 **Chart**。

### 關鍵指令 (Cheatsheet)
* **Repo 管理:** 
	* `helm repo add <name> <url>`: 新增倉庫。 
	* `helm repo update`: 更新倉庫索引 (類似 apt-update)。 
	* `helm search repo <keyword>`: 搜尋套件。
* **安裝與升級:**
	* `helm install <release-name> <chart>`: 安裝。 
	* `helm upgrade <release-name> <chart>`: 升級 (修改設定)。 
	* **關鍵參數:** `--set key=value` (指令覆蓋) 或 `--values my-values.yaml` (檔案覆蓋)。 
	* **優先權:** `--set` > `values.yaml` > `chart defaults`。
* **檢視與除錯:**
    * `helm list -A`: 列出所有軟體。
    * `helm status <release-name>`: 看安裝結果與相關資源。
    * `helm get manifest <release>`: **(除錯神器)** 匯出最終渲染出的 K8s YAML，檢查 Helm 到底幫你生成了什麼。
* **回滾 (Rollback):**
    * `helm history <release>`: 查看修訂版本 (Revision)。
    * `helm rollback <release> <revision>`: 救命藥，回到上一版。

---
## 3. Pod 網路硬核觀念

### Container 關係
* **共用:** 同一個 Pod 內的 Container 共用 **Network Namespace** (同一個 IP, 同一張網卡 `eth0`)。
* **通訊:** 可透過 `localhost:port` 互相溝通。
* **限制:** **Port 不能衝突**。Container A 佔用 80，Container B 就絕對不能用 80。

### 流量路徑 (NodePort)
`Client` -> `NodePort (Node IP:30080)` -> `Service IP (ClusterIP)` -> `Pod IP` -> `TargetPort (Container 實際監聽的 Port)`

---
## 4. 架構比較：Metrics Server vs CNI

這兩個是完全獨立的系統，常被混淆。

| 元件       | **CNI (Container Network Interface)** | **Metrics Server**                |
| :------- | :------------------------------------ | :-------------------------------- |
| **職責**   | **網路連通 (Connectivity)**               | **資源監控 (Monitoring)**             |
| **功能**   | 分配 IP、處理路由、Pod 互通                     | 收集 CPU/Memory 使用量                 |
| **代表工具** | Calico, Flannel, Cilium               | Metrics Server (官方專案)             |
| **故障影響** | Node NotReady，Pod 無法連網 (重大災情)         | `kubectl top` 失效，HPA 失效 (服務網路仍正常) |
| **關係**   | 它是「鋪路工程」 (基礎設施)                       | 它是「路邊監視器」 (加值功能)                  |

---
## 5. 常見誤區提醒

1.  **Metrics API not available:** 代表 Metrics Server 沒裝或還在啟動中。跟 CNI 沒關係。
2.  **歷史數據:** `kubectl top` **不能**看「昨天的」數據。要看歷史趨勢必須架設 Prometheus。
3.  **HPA 風險:** HPA 依賴 Metrics Server。若 Metrics Server 掛掉，HPA 會無法擴展。實務上建議改用 Prometheus Adapter 或設定 `minReplicas` 作為保底。