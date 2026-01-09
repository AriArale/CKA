# Kubernetes CKA 學習筆記 Part13 - 叢集升級與維護模式

**重點:** Cluster Upgrade 流程、版本傾斜策略 (Version Skew)、Drain/Uncordon 維護與 Kustomize  
**date:** 2025-12-23

---
## 1. 批判性思維：版本號的陷阱

在實戰或考試中，教材/題目的指示可能過時。

### 核心原則
* **不要死背版本號：** 題目說要升級到 `1.34.1`，但環境可能已經是 `1.34.3`。
* **以環境為準：** 執行指令查詢當下可用的版本，這才是真理。
```bash
    apt-cache madison kubeadm   # 查詢倉庫中所有可用版本
    apt-cache show kubeadm | grep Version
```
* **Kustomize 觀察：** `kubectl version` 顯示的 `Kustomize Version` 代表 `kubectl` 內建了配置管理引擎 (原生支援 `-k` 參數)。

---
## 2. 升級戰略 I：Control Plane (大腦)

升級順序：**先大腦 (Control Plane)，後四肢 (Worker Node)。**
工具順序：**先 Kubeadm -> 再 Cluster -> 最後 Kubelet/Kubectl。**

### 標準 SOP
1.  **升級工具本身 (kubeadm):**
```bash
    apt-get update && apt-get install -y kubeadm=1.34.x-1.1
```
2.  **制定計畫 (Plan):**
```bash
    kubeadm upgrade plan
    # 檢查是否可以升級，並顯示目標版本
```
3.  **執行升級 (Apply):**
 ```bash
    # ⚠️ 這是 Control Plane 專用指令
    kubeadm upgrade apply v1.34.x
```
4.  **升級二進制檔 (Binary) 與重啟:**
```bash
    apt-get install -y kubelet=1.34.x-1.1 kubectl=1.34.x-1.1
    systemctl daemon-reload
    systemctl restart kubelet
```

---
## 3. 升級戰略 II：Worker Node (四肢)

### 版本傾斜策略 (Version Skew Policy)
* **原則：** Control Plane 版本必須 **>=** Worker Node 版本。
* **容許值：** kubelet 最多可以落後 apiserver **3 個小版本 (Minor Version)**。
* **禁止：** Worker 版本比 Control Plane 新 (向上不相容風險)。

### 標準 SOP (與 Control Plane 的差異)
1.  **升級 Kubeadm:** `apt-get install -y kubeadm=1.34.x-1.1`
2.  **執行升級 (Node):**
```bash
    # ⚠️ 這是 Worker Node 專用指令，注意沒有 "apply" 且不用指定版本
    # 它會自動去讀取 Control Plane 的設定
    kubeadm upgrade node
```
3.  **升級 Kubelet 並重啟:** 同上。

---
## 4. SRE 維護核心：優雅升級 (Graceful Upgrade)

為了達成高可用性 (HA)，在對 Node 進行會中斷服務的操作 (升級 Kubelet、重開機) 前，必須進行「清場」。

| 步驟 | 指令 (在 Control Plane 執行) | 意義 (SRE 解析) |
| :--- | :--- | :--- |
| **1. 封 (Cordon)** | (包含在 Drain 指令中) | 標記 Node 為 `Unschedulable`。告訴 Scheduler：「這台維修中，別派新單進來」。 |
| **2. 趕 (Evict)** | `kubectl drain node01 --ignore-daemonsets` | 禮貌地請現有的 Pod 結束並搬家到別台。`--ignore-daemonsets` 是必須的，因為 DS 趕不走。 |
| **3. 修 (Upgrade)** | (SSH 到 Node 操作) | 執行軟體升級或重開機。此時 Node 上沒有業務 Pod，安全無虞。 |
| **4. 解 (Uncordon)** | `kubectl uncordon node01` | 移除 `Unschedulable` 標記。告訴 Scheduler：「維修結束，恢復接客」。 |

**風險提示：** 若跳過 Drain 直接升級，Pod 會被強制 Kill，導致服務中斷 (Downtime)。

---
## 5. 關鍵指令集 (Cheatsheet)

```bash
# 1. 查版本真相
apt-cache madison kubeadm
apt-cache show kubeadm | grep Version

# 2. Control Plane 升級關鍵指令
kubeadm upgrade plan
kubeadm upgrade apply v1.34.3

# 3. Worker Node 升級關鍵指令
kubeadm upgrade node

# 4. 維護模式 (Drain/Uncordon)
k drain node01 --ignore-daemonsets
k uncordon node01
```