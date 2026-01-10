# Kubernetes CKA 學習筆記 Part19 - Core Architecture & Interaction

**重點:** Client/Server Model, Controller Pattern, Push vs Pull, Reverse Proxy Path, Diagramming Standards  
**date:** 2026-01-10

---

## 1. 組件角色與互動邏輯 (Component Roles)

### Kubectl vs. API Server vs. Kubelet
* **Kubectl (The Trigger / Client):**
    * **角色:** 瞬態的指令工具 (Ephemeral CLI)。
    * **行為:** 負責將人類意圖轉為 HTTP Request 發送給 API Server。指令結束即消失，不負責後續狀態維護。
    * **觀念修正:** Kubectl 不是 Controller Manager 的代言人，它只負責「下單」。
* **API Server (The Hub / Server):**
    * **角色:** 唯一的狀態儲存入口與通訊中心。
    * **行為:** 被動等待連線 (Listen Port 6443)。
* **Kubelet (The Worker):**
    * **角色:** Node 上的代理人。
    * **行為:** 負責執行 Pod 生命周期。與 API Server 雖在同一個 Node (Control Plane 情境)，但透過網路 (Network Interface) 溝通，彼此邏輯隔離 (Container vs Host Process)。

### Controller Manager (The Reconciler)
* **角色:** 自動駕駛系統 (Autopilot)。
* **核心機制:** **Reconciliation Loop (調和迴圈)**。
    * **Observe:** 觀察現況 (Current State)。
    * **Diff:** 比較與期望狀態 (Desired State) 的差異。
    * **Act:** 執行修正 (如建立/刪除 Pod)。
* **價值:** 如果沒有它，K8s 只是靜態的資料庫；有了它，K8s 才有自我修復 (Self-healing) 能力。

---

## 2. 通訊流向架構 (Traffic Flow)

### Pull vs. Push 模型
* **架構圖箭頭:** `Kubelet` -> `API Server`。
* **機制:** **Pull (拉取) / Watch**。
    * API Server 不會主動推播工作給 Kubelet (Push)。
    * Kubelet 主動連線並監聽 (Watch) API Server，詢問「有我的工作嗎？」。
    * **優勢:** 即使 Node 在防火牆後 (Edge Computing)，只要能連出 (Outbound) 即可運作。

### 特殊反向路徑 (The Reverse Path)
* **情境:** `kubectl logs`, `kubectl exec`, `kubectl attach`, `kubectl top` (Metrics)。
* **流向:** `User` -> `API Server` -> **`Kubelet (Port 10250)`** -> `Container Runtime`。
* **機制:** API Server 轉職為 **Proxy (代理)**。
    * 此時 API Server 會主動發起連線至 Node 的 **TCP 10250**。
    * 這是**串流 (Streaming)** 連線。
* **排查重點:** 若 `get pods` 正常但 `logs` timeout，通常是防火牆擋住了 Control Plane 連往 Worker Node 的 10250 Port。

---

## 3. 架構圖繪製標準 (Diagramming Standards)

在理解 Kubernetes 架構時，正確解讀圖表中的箭頭含義至關重要。依據情境不同，箭頭代表的意義分為以下三類：

### A. 系統架構圖 / 拓樸圖 (System Topology)
* **畫法：** **單向箭頭** (Client $\rightarrow$ Server)。
* **代表意義：** **連線發起方 (Connection Initiator)** 與依賴關係 (Dependency)。即「誰主動去戳誰」。
* **為什麼不畫 Response (回傳)？**
    1.  **隱式契約 (Implicit Contract):** TCP/HTTP 協定中，有 Request 必有 Response。畫出回傳箭頭屬多餘資訊，易造成視覺雜訊。
    2.  **防火牆規則 (Firewall Rules):** 現代防火牆 (Stateful) 只要允許了 Outbound (Request)，會自動允許對應的 Inbound。因此技術上只需關注「誰發起連線」，這決定了 ACL (存取控制列表) 的設定方向。
* **範例：** `Web App` $\rightarrow$ `Database`。代表 App 主動連線 DB。

### B. 時序圖 (Sequence Diagram)
* **畫法：** **雙向拆解** (實線 Request $\rightarrow$ / 虛線 Response $\dashleftarrow$)。
* **代表意義：** **時間流動與阻塞 (Time & Blocking)**。
* **使用時機：**
    * 分析 **Latency (延遲)**：觀察 Request 發出到 Response 回來的時間差。
    * 分析 **非同步/死鎖 (Deadlock)**：確認 Client 是在空轉等待 (Blocking) 還是繼續執行。
* **範例：** OAuth 登入流程、K8s Pod 建立流程 (Kubectl $\rightarrow$ API $\rightarrow$ Etcd)。需確認每個步驟是否成功 ACK。

### C. 資料流向圖 (Data Flow Diagram, DFD)
* **畫法：** 箭頭代表 **資料流動方向 (Data Movement)**，不一定等於連線方向。
* **代表意義：** **Payload 的搬運**。
* **易混淆點：** 資料流向可能與連線方向相反。
* **範例：** Prometheus (Pull 模式) 監控 Node Exporter。
    * **架構連線面 (TCP):** `Prometheus` $\rightarrow$ `Node Exporter` (Prometheus 主動發起連線去抓)。
    * **資料流向面 (Payload):** `Prometheus` $\leftarrow$ `Node Exporter` (監控數據是從 Node 流向 Prometheus)。
* **建議：** 繪製此類圖表時，應標註清楚是 "Traffic Flow" 還是 "Data Stream" 以避免誤解。