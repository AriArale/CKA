# Kubernetes CKA 學習筆記 Part22 - Networking Deep Dive & Exam Strategy

**重點:** Imperative vs Declarative Strategy, Service Exposure Levels, Ingress Traffic Flow, PathTypes  
**date:** 2026-01-13

---

## 1. 考試戰術：指令生成 vs 文件複製 (Creation Strategy)

在 CKA 考試中，速度是關鍵。應根據資源類型的複雜度，決定使用「CLI Dry-Run」還是「Copy-Paste」。

### 必須使用 Dry-Run 的資源 (The Imperative Whitelist)
這些資源結構簡單，手寫 YAML 容易出錯（縮排、Base64），**務必用指令生成骨架**。

* **指令技巧:** 設定 alias `export do="--dry-run=client -o yaml"`
* **清單:**
    * **Pod:** `k run my-pod --image=nginx --restart=Never $do`
    * **Deployment:** `k create deploy my-dep --image=nginx --replicas=3 $do`
    * **Service:** `k deploy my-dep --port=80 --type=NodePort --name=my-svc $do` 或 `k create svc nodeport my-svc --tcp=80:8080 $do`
    * **CronJob:** `k create cronjob my-job --image=busybox --schedule="*/1 * * * *" $do` (手寫必錯)
    * **Secret/ConfigMap:** `k create secret generic my-secret --from-literal=pass=1234 $do` (自動 Base64)
    * **RBAC:** `k create role my-role --verb=get,list,watch --resource=pods,svc $do` 或 `k create rolebinding my-bind --role=my-role --user=system:serviceaccount:default:default $do`

### 必須複製文件的資源 (The Docs-First Whitelist)
這些資源結構高度巢狀 (Nested) 或 CLI 不支援，**不要嘗試用指令建立**。

* **NetworkPolicy:** (絕對第一名) `ingress`, `egress`, `ipBlock` 結構太複雜。
* **PV / PVC:** CLI 不支援詳細參數。
* **StorageClass:** CLI 不支援。
* **Ingress:** 雖然有 `create ingress`，但涉及 Annotation 或 Rewrite 時，複製範本較安全。

---

## 2. 服務暴露邏輯 (Service Exposure Logic)

`kubectl expose` 的行為完全取決於 `--type`，這決定了是否需要 Ingress。

| Service Type | 外部可存取性 | 是否需要 Ingress? | SRE 觀點 |
| :--- | :--- | :--- | :--- |
| **ClusterIP** (Default) | **No** (僅限叢集內) | **YES** (必須透過 Proxy/Ingress) | 正式環境後端標準配置 |
| **NodePort** | **YES** (透過 NodeIP:Port) | **NO** (防火牆打洞) | 適合測試或非 HTTP 服務 |
| **LoadBalancer** | **YES** (透過 Public IP) | **NO** (雲端廠商提供 IP) | 適合雲端環境的 Entrypoint |

* **觀念修正:** Ingress 不是唯一的入口。如果 Service 是 NodePort/LoadBalancer，外部可以直接連線。Ingress 的價值在於 **L7 路由 (Host/Path based)** 與 **TLS 管理**。

---

## 3. Ingress 流量與除錯 (Ingress Architecture)

### 流量路徑 (Traffic Flow)
User $\rightarrow$ **NodePort (e.g., 30080)** $\rightarrow$ **Ingress Controller Service** $\rightarrow$ **Ingress Controller Pod (Nginx)** $\rightarrow$ **Backend Service** $\rightarrow$ **Backend Pod**

### 實務架構 (Port 80 vs 30080)
* **Lab/CKA 環境:** 使用 **NodePort (30080)** 作為入口，因為沒有外部負載平衡器。
* **Cloud 環境:** AWS ELB (Port 80) $\rightarrow$ NodePort (30080)。User 看到的是 Port 80。
* **On-Prem 環境:** MetalLB (BGP/ARP) 或 HW LB (F5) $\rightarrow$ NodePort。

### 關鍵除錯指令
在寫 Ingress YAML 前，必須先探勘環境參數：
1.  **找大門 (Port):** `k get svc -n ingress-nginx` $\rightarrow$ 確認 NodePort 是多少 (如 30080)。
2.  **找管理員 (Class):** `k get ingressclass` $\rightarrow$ 確認 `ingressClassName` (如 nginx)。

---

## 4. PathType: Prefix vs. Exact

決定路由匹配的嚴格程度。

| PathType | 邏輯 | 範例 (`/foo`) | 匹配結果 |
| :--- | :--- | :--- | :--- |
| **Exact** | **字串完全相等** | `/foo` | ✅ Match |
| | | `/foo/` | ❌ Mismatch (多一個斜線都不行) |
| | | `/foo/bar` | ❌ Mismatch |
| **Prefix** | **路徑階層匹配** | `/foo` | ✅ Match |
| | | `/foo/` | ✅ Match |
| | | `/foo/bar` | ✅ Match (允許子路徑) |
| | | `/foobar` | ❌ Mismatch (以 `/` 為階層分隔) |

* **優先權:** 若規則衝突，**最長路徑優先 (Longest match)**；長度相同則 **Exact > Prefix**。