# Kubernetes CKA 學習筆記 Part12 - DaemonSet 實戰、除錯 SOP 與 Cluster 建置

**重點:** DaemonSet Node Config、Shell 模式 (`sh -c`)、CrashLoopBackOff 排查、Kubeadm Init 與 Join 流程  
**date:** 2025-12-22

---

## 1. DaemonSet 實戰：節點初始化 (Node Bootstrap)

### 核心概念
利用 DaemonSet 的「全節點覆蓋」特性，配合 `hostPath` 穿透容器隔離，對 Node 進行檔案寫入或系統設定。

### 關鍵 YAML 結構解析
```yaml
apiVersion: apps/v1
kind: DaemonSet
spec:
  template:
    spec:
      containers:
      - name: configurator
        image: bash
        # ⚠️ 關鍵指令區塊
        command:
        - sh
        - -c   # 必須加，開啟 Command Mode
        - 'echo "data" > /mount/config && sleep 1d'
        
        # ⚠️ 檔案系統穿透
        volumeMounts:
        - name: vol
          mountPath: /mount      # Container 內的路徑
      volumes:
      - name: vol
        hostPath:
          path: /configurator    # Node 實體路徑
````

### SRE 批判性思維

1. **為什麼要 `sleep 1d`？**
    
    - **原因：** DaemonSet 的職責是確保 Pod **Running**。若指令執行完 (`echo`) 就結束 (Exit Code 0)，K8s 會判定 Pod 終止並重啟，導致無限重啟迴圈。
    - **解法：** 使用 `sleep` 掛起行程，維持 Pod 存活。

2. **為什麼用 `hostPath`？**
    
    - **風險：** 這是開後門行為，有資安風險。
    - **髒狀態 (Dirty State)：** Pod 刪除後，寫入 Node 的檔案**不會**消失，需自行管理清理機制。

---
## 2. YAML Command 語法與除錯 (The Shell Form)

### 語法陷阱：`sh -c` vs `sh c`

|**寫法**|**YAML 結構**|**行為解析**|**結果**|
|---|---|---|---|
|**正確**|`["sh", "-c", "echo..."]`|呼叫 sh，`-c` 告訴它讀取**後面的字串**當作程式碼執行。|✅ 執行成功|
|**錯誤**|`["sh", "c", "echo..."]`|呼叫 sh，它以為 **`c`** 是一個檔案名稱，試圖開啟它。|❌ Crash: `can't open 'c': No such file`|
|**錯誤**|`["echo", ">", "file"]`|直接呼叫 echo。`>` 被當作純文字參數印出來，**不會**寫入檔案。|❌ 輸出字串但沒寫檔|

---
## 3. Kubernetes 排錯 (Troubleshooting) SOP

### 場景 A：Pod 狀態 `CrashLoopBackOff`

Pod 啟動後馬上掛掉，不斷重試。

1. **驗屍 (Logs):** `k logs <pod>` (查 `can't open file` 或 `Permission denied`)。
2. **查死因 (Exit Code):** `k describe pod <pod>` (Code 0 為邏輯錯，Code 1 為語法錯)。
3. **驗配置 (Get YAML):** 檢查 `command` 陣列結構。

### 場景 B：Create Deployment 報錯 `exactly one NAME is required`

原因： Shell 變數展開時包含空白鍵 (d="--dry-run= client" )。  
修正： 去除空白 (export d="--dry-run=client -o yaml")。

---
## 4. Kubeadm Cluster 建置流程 (Init & Join)

這是從零建立叢集的標準兩步曲。
### Phase 1: 初始化 Control Plane (大腦)

在 `controlplane` 節點執行：

```bash
kubeadm init \
  --kubernetes-version=1.34.1 \
  --pod-network-cidr=192.168.0.0/16 \
  --ignore-preflight-errors=NumCPU,Mem
```

- **`--pod-network-cidr`**: 預留 IP 給未來的 CNI (如 Calico)。**必設！**
- **`admin.conf`**: 執行後務必執行 `cp /etc/kubernetes/admin.conf ~/.kube/config`，否則 `kubectl` 無法運作。

### Phase 2: 加入 Worker Node (四肢)

將 `node-summer` 加入叢集。
#### 1. 產生 Join Command (在 Control Plane)

Token 通常只有 24 小時效期。如果找不到 `init` 時輸出的指令，可用此指令重新產生：

```bash
kubeadm token create --print-join-command
# 輸出範例：kubeadm join 172.30.1.2:6443 --token <token> --discovery-token-ca-cert-hash <hash>
```

#### 2. 執行加入 (在 Worker Node)

登入 `node-summer` 並貼上上述指令 (需 sudo 權限)。

- **機制：** Worker 透過 Token 驗證身分，透過 Hash 驗證 API Server 的憑證 (雙向信任)。
- **網路需求：** Worker 必須能連線到 Control Plane 的 **6443** Port。

#### 3. 驗證狀態 (在 Control Plane)

```bash
kubectl get nodes
```

- **預期結果：** 應該看到兩個節點 (`controlplane`, `node-summer`)。
- **SRE 提醒：** 此時狀態通常是 **`NotReady`**，這是正常的！因為 **CNI (網路插件)** 還沒安裝，節點間無法通訊。

---
## 5. 操作技巧與必記指令 (Cheatsheet)

- **熱修復 (Hot Patch):** `kubectl edit daemonset <name>` (直接生效，不需 delete)。
- **變數除錯:** `echo "$d"` (檢查空白鍵)。
- **產生 Join 指令:** `kubeadm token create --print-join-command` (背下來，考試救命用)。
- **快速查閱指令解析:** `k get pod <name> -o yaml | grep -A 5 command`。