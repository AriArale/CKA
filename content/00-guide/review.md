# Kubernetes CKA 學習筆記 Part25 - 重點複習

**重點:**  Kubernetes 核心運作、CKA 考點、以及工具指令的底層邏輯拆解  
**date:** 2026-02-09

---

## 1. 核心元件與控制平面 (Control Plane & etcd)

### 1.1 etcdctl 指令順序

**問題：** `etcdctl snapshot restore` 報錯 `unknown flag: --data-dir`

**盲點：** `etcdctl` 對參數位置極度敏感，Flags 必須在 Arguments 之前

**修正：**
```bash
export ETCDCTL_API=3
# 正確：Flag 在前
etcdctl snapshot restore --data-dir=/var/lib/etcd-new /opt/backup.db
```

### 1.2 Service CIDR 修改 (Cluster Maintenance)

**概念：** ServiceCIDR 是 IP 分配池。API Server 是分配者，Controller Manager 是執法者

**操作：** 修改 Service 網段屬於「傷筋動骨」的操作，**必須同時修改**以下兩個靜態 Pod 的 Manifest 並等待重啟：
1. `/etc/kubernetes/manifests/kube-apiserver.yaml`
2. `/etc/kubernetes/manifests/kube-controller-manager.yaml`

**注意：** 舊的 Service IP 不會變，只有新建立的 Service 會拿到新網段 IP

---

## 2. Pod 與容器規格 (Pod Spec & Container)

### 2.1 Command vs Args (Docker Entrypoint vs CMD)

**結構比較：**
- **分開寫 (推薦)：** `command: ["/bin/sh", "-c"]` + `args: ["script.sh"]` - 解耦工具與行為，易於覆寫
- **合寫：** `command: ["/bin/sh", "-c", "script.sh"]` - 結構僵化

**kubectl run 行為：**
- `k run ... -- <cmd>` → 寫入 `spec.args` (預設)
- `k run ... --command -- <cmd>` → 寫入 `spec.command` (強制覆寫 Entrypoint)

### 2.2 YAML 雜訊 (Boilerplate)

**現象：** `kubectl run --dry-run=client` 產生的 YAML 包含 `creationTimestamp: null` 和 `status: {}`

**解讀：** 這是 Client 端生成的結構佔位符 (Placeholder)。API Server 收到後會忽略並填入真實數據。**CKA 考試時無需刪除，直接 Apply 即可**

### 2.3 查詢容器名稱

**快速：** `READY 2/2` 代表有 Sidecar

**精準：** 使用 JSONPath
```bash
kubectl get pod <name> -o jsonpath='{.spec.containers[*].name}'
```

---

## 3. 網路與 DNS (Networking & DNS)

### 3.1 DNS 排錯 (Troubleshooting)

**現象：** `nslookup` 回傳 `connection timed out`

**判讀：**
- `Timed out` = 封包被丟棄 (Drop) → **NetworkPolicy** 阻擋 (Egress)
- `Connection refused` = 服務沒開 → CoreDNS 掛了

**修正：** 檢查 NetworkPolicy 是否允許 UDP Port 53

### 3.2 nslookup 輸出差異

- **Glibc (Debian/Ubuntu)：** 顯示 `Server: IP#Port` - 格式標準
- **Musl (Alpine/Busybox)：** 顯示 `Address 1: IP Hostname` - 格式精簡，會多做反向解析顯示 Hostname

**結論：** 兩者含金量相同，勿被格式混淆

### 3.3 Port Forwarding

**指令：** `kubectl port-forward svc/mongo 28015:27017`

**本質：** 建立一條從 `localhost` 到 Cluster 內部的 HTTP/2 隧道 (Tunnel)

**用途：** 繞過防火牆、臨時除錯、本地開發直連 DB

### 3.4 Gateway API 邏輯陷阱

**結構：** `GatewayClass` (模具/Admin) vs `Gateway` (成品/Dev) - 類比 `StorageClass` vs `PVC`

**YAML 語法致命傷 (Hyphen `-`)：**
- **AND 邏輯 (正確)：** 同一個 `-` 下包含 `path` 和 `headers`
- **OR 邏輯 (錯誤)：** 分開兩個 `-` - 導致 `matches[0].headers` 為 `undefined` (Any Header)，造成安全漏洞

---

## 4. 儲存與狀態 (Storage & Stateful)

### 4.1 PV/PVC 綁定失敗

**狀態：** PVC 處於 `Pending`

**常見原因 (由高至低)：**
1. **Capacity：** PV 容量 < PVC 請求 (大不可配小)
2. **AccessMode：** 模式不匹配 (如 PV 無 RWX)
3. **Selector：** PVC 指定了 Label Selector，但 PV 沒貼標籤 (CKA 常考)

### 4.2 Operator 模式

**案例：** MinIO Operator vs Tenant

**關係：**
- **Operator：** 控制器 (Controller) - 負責監聽 CRD，執行自動化維運
- **Tenant (CR)：** 自定義資源 (Custom Resource) - 即「訂單/規格書」，描述想要的儲存池長相

---

## 5. CLI 工具與自動化 (Tooling & Logic)

### 5.1 grep 的誤用

**錯誤：** `grep *file=`

**原因：** `grep` 吃 Regex，`*` 代表重複前一個字元，而非 Shell 的通配符

**修正：** `grep file=` 或 `grep ".*file="`

### 5.2 JSONPath 迴圈與格式化

**需求：** 列出 Pod 內所有 Container 並分行顯示

**限制：** `custom-columns` 會將陣列 (Array) 壓扁成單行

**解法：** 使用 JSONPath `range` 進行迭代
```bash
# 關鍵在於 range 進入 containers 層級，並用 \n 換行
kubectl get pod -o jsonpath='{range .spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'
```

### 5.3 Kustomize 預覽

- **`k kustomize prod`：** Client-side Build - 單純渲染出最終 YAML (Artifact)，不聯網
- **`| kubectl diff -f -`：** Server-side Plan - 將渲染結果送給 API Server 比對線上差異 (Drift Detection)

### 5.4 Pod 內存取 API (Curl)

**Token (身分證)：** 需讀取內容 (`cat ...`)，放在 Header (`Authorization: Bearer`)

**CA Cert (信任狀)：** 需指定路徑 (`/var/...`)，放在參數 (`--cacert`)

**指令樣板：**
```bash
curl --cacert $CACERT --header "Authorization: Bearer $TOKEN" https://kubernetes.default/api
```