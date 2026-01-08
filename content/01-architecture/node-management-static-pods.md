# Kubernetes CKA 學習筆記 Pare14 - Node Join, Certs & Static Pods

**重點:** Kubeadm Join 流程、憑證更新、Static Pod 運作機制 (Mirror Pod) 與 DaemonSet 架構比較
**date:** 2025-12-29

---
## 1. 節點擴充：加入 Worker Node (Join)

### 核心情境
將一個尚未加入 Cluster 的節點 (`node01`)納入管理。

### 關鍵指令
1.  **在 Control Plane 產生指令 (Token):**
  ```bash
    kubeadm token create --print-join-command
    # 輸出範例: kubeadm join <IP>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
    ```
2.  **在 Worker Node 執行:**
    * 直接貼上上述指令 (需 sudo 權限)。

### SRE 偵查思維：如何確認「隱藏節點」存在？
在節點加入前，Control Plane 對它一無所知 (`kubectl get nodes` 看不到)。
* **❌ ARP (`ip neigh`):** 資訊太少 (僅 IP/MAC)，且被動 (無流量則無紀錄)，不推薦。
* **✅ 電話簿 (`cat /etc/hosts`):** 考試/Lab 環境最權威的來源，清楚列出 Hostname 與 IP 對應。
* **✅ 聲納 (`ping <hostname>`):** 確認 DNS 解析與網路連通性。

---
## 2. 憑證管理 (Certificate Management)

### 核心情境
檢查並更新 K8s 元件 (API Server, Scheduler 等) 的 TLS 憑證效期。

### 關鍵指令
```bash
# 1. 檢查效期 (Check Expiration)
kubeadm certs check-expiration

# 2. 更新憑證 (Renew)
kubeadm certs renew apiserver
kubeadm certs renew scheduler.conf
# 或是全部更新: kubeadm certs renew all
```

---
### 排錯：Tab 補全失效 (No Auto-Completion)

- **現象:** 輸入 `kubeadm cer` 按 Tab 沒反應。
- **原因:** Shell 未載入 `kubeadm` 的補全腳本。
- **解法 (Magic Command):** `source <(kubeadm completion bash)`
- **考試策略:** 相關指令很少 (`check-expiration`, `renew`)，建議直接背下來或打完，不要花時間 debug Shell 環境。

---
## 3. Static Pod (靜態 Pod) 深度解析

### 核心定義

由特定 Node 上的 **Kubelet** 直接管理的 Pod，**不受 API Server (Control Plane) 控制**。

- **設定位置:** `/etc/kubernetes/manifests/` (預設)。
- **識別特徵:** Pod 名稱帶有 `-<NodeName>` 後綴 (例如 `nginx-node01`)。
- **Owner Reference:** `Node/<node_name>`。
### Mirror Pod (鏡像 Pod) 的哲學

- **是什麼？** Kubelet 通知 API Server 建立的一個 **「唯讀投影 (Read-Only Projection)」**。
- **為什麼要存在？** 為了 **資源記帳 (Resource Accounting)**。讓 Scheduler 知道該 Node 已經被佔用了多少 CPU/RAM，避免重複派發任務導致資源衝突。
- **操作限制 (SRE 必考):**
    - **kubectl delete:** 無效。Kubelet 發現本地檔案還在，會立刻重建 Mirror Pod (殭屍復活)。
    - **kubectl edit:** 無效。API Server 無法更改由 Kubelet 管理的物件。

### 實戰操作：移動 Static Pod (Move)

因為不能用 kubectl 操作，必須進行「物理搬運」：

1. **複製 (Copy):** `scp node01:/etc/kubernetes/manifests/pod.yaml .`
2. **修改 (Edit):** 修改 YAML 內容 (如改名)。
3. **部署 (Deploy):** `mv pod.yaml /etc/kubernetes/manifests/` (移入 Control Plane 的 manifests 資料夾，Kubelet 自動啟動)。
4. **刪除舊的 (Delete):** `ssh node01 -- rm /etc/kubernetes/manifests/pod.yaml` (檔案刪除，Pod 即死)。

---
## 4. 架構比較：Static Pod vs. DaemonSet

|**特性**|**Static Pod**|**DaemonSet**|
|---|---|---|
|**管理模式**|**諸侯自治 (Local)**|**中央集權 (Central)**|
|**管理者**|Node 上的 **Kubelet**|Control Plane 的 **DaemonSet Controller**|
|**資料來源**|本地檔案 (`/etc/kubernetes/manifests`)|etcd 資料庫 (API Object)|
|**適用場景**|**Bootstrap (啟動引導):** 跑起 K8s 自己的元件 (etcd, apiserver)。|**Day-2 Ops (維運):** Log Agent, Monitoring, CNI Plugins。|
|**操作方式**|SSH 進 Node 改檔案|`kubectl apply/delete/edit`|
|**可否排程**|綁死在特定 Node|可透過 Affinity/Toleration 調度|

**結論：**

- **Static Pod** 是用來生出 Control Plane 的 (雞生蛋問題的解法)。
- **DaemonSet** 是 Control Plane 生出來管理 Worker Node 的。

---
## 5. 常用指令集 (Cheatsheet)

```bash
# 產生 Join Token (Control Plane)
kubeadm token create --print-join-command

# 檢查憑證過期日
kubeadm certs check-expiration

# 驗證 Static Pod 檔案位置 (需 SSH 到 Node)
cat /var/lib/kubelet/config.yaml | grep staticPodPath
# 通常輸出: staticPodPath: /etc/kubernetes/manifests

# 刪除 Static Pod (唯一解法)
rm /etc/kubernetes/manifests/<pod-name>.yaml
```