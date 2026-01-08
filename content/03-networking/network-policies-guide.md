# Kubernetes CKA 學習筆記 Part6 - NetworkPolicy 實戰與架構解析

**重點:** NetworkPolicy 白名單機制、YAML 結構陷阱、kubectl exec 參數詳解
**date:** 2025-12-12

---

## 1. NetworkPolicy 核心觀念：白名單 (Whitelist)

* **基本原則：** NetworkPolicy 預設不影響任何流量，除非 Pod 被選中。
* **Default Deny (預設拒絕)：**
    * 一旦 Pod 被 `podSelector` 選中，該 Pod 立即進入隔離狀態。
    * **口訣：** 「一旦選中，立即隔離」。只有在規則 (`ingress`/`egress`) 中明確允許的流量才能通過。
* **控制方向 (`policyTypes`)：**
    * **Ingress:** 控制「進來」的流量。
    * **Egress:** 控制「出去」的流量。

---

## 2. YAML 撰寫關鍵技巧

### Namespace 選擇器 (必背 Label)
在 `namespaceSelector` 中，不需手動打標籤，直接使用 K8s 自動生成的標籤：
* **Key:** `kubernetes.io/metadata.name`
* **Value:** `<namespace名稱>`
* **用途：** 快速選取特定的 Namespace，CKA 考試省時神器。

### YAML 結構細節
* **全選 Pod:** `podSelector: {}` 代表選取該 Namespace 下的 **所有** Pod。
* **多物件分隔:** 使用 `---` 可以在同一份檔案中定義多個 NetworkPolicy (或其他資源)。每一段都必須包含完整的 `apiVersion`, `kind`, `metadata`。

### Namespace 指定優先權
* **情境：** YAML 內寫死 `metadata.namespace: space1`，但指令下 `kubectl apply -f np.yaml -n space2`。
* **結果：** **報錯 (Conflict)**。Kubernetes 會保護定義的一致性，不允許 CLI 覆蓋 YAML 內的指定。
* **通用模板技巧：** 若希望 YAML 能隨意套用到不同環境 (Dev/Prod)，YAML 內就 **不要寫** `namespace` 欄位，改由 CLI 的 `-n` 控制。

---

## 3. 指令參數拆解：`kubectl exec` 與 `curl`

範例指令：
`k -n space1 exec app1-0 -- curl -m 1 microservice1.space2.svc.cluster.local`

| 參數部份 | 解釋 |
| :--- | :--- |
| **`-n space1`** | 指定 kubectl 操作的 Namespace。 |
| **`exec app1-0`** | 指示要進入 `app1-0` 這個 Pod 執行命令。 |
| **`--`** | **分隔符號 (重要)**。左邊是給 kubectl 看的參數，右邊是給容器內部執行的指令。 |
| **`curl`** | 用來測試連線的工具。 |
| **`-m 1`** | **Max-time 1秒**。若封包被 NetworkPolicy Drop 掉，curl 會卡住很久，設定 1 秒逾時可快速驗證「通」或「不通」。 |

---

## 4. 底層運作架構：從 Apply 到 Enforcement

* **邏輯層 (API Server / Etcd):** `kubectl apply` 只是將 NetworkPolicy 的「期望狀態」存入資料庫。它屬於 **Namespaced** 資源。
* **執行層 (Data Plane / Node):**
    * 每一台 Node 上的 **CNI Plugin** (如 Calico, Cilium, Flannel) 負責監聽 (Watch) API Server。
    * 當發現有新的 Policy，CNI 會自動在 Node 底層 (iptables / eBPF) 設定防火牆規則。
    * **結論：** 設定是透過 API 下達，但阻擋動作是由 Node 上的 CNI 實作。

* 這並不是 NetworkPolicy 獨有的特權，**所有的資源（包括 ConfigMap, Deployment）都是這樣的。**
- **如果 YAML 裡寫了 `namespace: space1`**：Kubernetes 就會照著檔案裡的指示，把它塞進 `space1`。這時候你在指令列打不打 `-n` 都沒關係（通常檔案裡的優先權最高）。
- **如果 YAML 裡「沒寫」 `namespace`**：Kubernetes 就不知道要放哪。這時候它會看你在指令列有沒有打 `-n`，或者看你目前的 Context 預設在哪個 Namespace。    

**💡 為什麼你之前的經驗覺得 ConfigMap 需要指定 `-n`？** 

很可能是因為在之前的練習中，為了讓 YAML 保持通用性（Generic），我們通常**故意不在 YAML 裡寫死 Namespace**。這樣同一份 YAML 就可以透過 `k -n dev apply ...` 放到開發環境，也可以透過 `k -n prod apply ...` 放到生產環境。